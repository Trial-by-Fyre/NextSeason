//
//  RefreshScheduler.swift
//  NextSeason
//

import BackgroundTasks
import Foundation
import Synchronization
import os

/// Registers and runs the app’s best-effort background watchlist refresh
/// (`BGAppRefreshTask`, ~12h production cadence via `BackgroundRefreshConfiguration`).
///
/// Lifecycle:
/// 1. `registerBackgroundTask()` — tell the system how to launch this identifier.
///    Called once from `NextSeasonApp.init`, before composition, because Apple
///    requires registration before launch finishes and kills the app on a second
///    registration. A successful persistence recovery composes after launch, so
///    composition must never register.
/// 2. `configure(refreshHandler:)` — store the async work to run (typically
///    `WatchlistRefreshService.refreshAll`). Set by every successful composition
///    (`AppCompositionRoot.configureBackgroundRefresh`), including after recovery.
/// 3. `scheduleNextRefresh()` — submit the next earliest-begin request.
/// 4. When iOS launches the task → `handleAppRefresh` runs the handler, then
///    marks the task completed (or cancelled on expiration). With no handler
///    (the app is in persistence recovery) it completes with failure at once.
///    The launch handler is delivered on the main queue (`using: .main`).
///    `expirationHandler` may arrive on another queue and must hop to
///    `@MainActor` before cancelling work or completing the `BGAppRefreshTask`.
///
/// Background refresh is not guaranteed on interval; iOS may delay or skip runs.
enum RefreshScheduler {
    static let taskIdentifier = "com.TrialByFyre.NextSeason.watchlist-refresh"

    /// Closure invoked when a background refresh task runs (set once at launch).
    /// Returns whether the refresh pass succeeded for `BGAppRefreshTask` (R12).
    @MainActor private static var refreshHandler: (() async -> Bool)?
    @MainActor private static var diagnostics: BetaRefreshDiagnostics?

    /// Stores the work to perform when iOS delivers a background refresh.
    @MainActor
    static func configure(
        diagnostics: BetaRefreshDiagnostics? = nil,
        refreshHandler: @escaping () async -> Bool
    ) {
        self.diagnostics = diagnostics
        self.refreshHandler = refreshHandler
    }

    /// The process's single system registration (see `registerBackgroundTask`).
    @MainActor private static let registration = BackgroundTaskRegistration(
        register: registerWithSystem)

    /// Must be called during app launch (before the app finishes launching) so
    /// the system can associate `taskIdentifier` with our handler. Registers at
    /// most once per process; later calls are ignored.
    @MainActor
    static func registerBackgroundTask() {
        registration.registerIfNeeded()
    }

    /// The single system registration; call only through `registration`.
    private static func registerWithSystem() -> Bool {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: .main
        ) { task in
            // Launch handler: BGTaskScheduler delivers this closure on the
            // main queue when `using: .main`. Hop explicitly so
            // `handleAppRefresh` is not relying on that queue alone.
            Task { @MainActor in
                handleAppRefresh(task)
            }
        }
    }

    /// Runs one background refresh pass and always completes the `BGTask`.
    @MainActor
    private static func handleAppRefresh(_ task: BGTask) {
        guard let refreshTask = task as? BGAppRefreshTask else {
            AppDiagnosticsLogger.logger(for: .tasks)
                .fault("background_task_unexpected_type")
            task.setTaskCompleted(success: false)
            return
        }

        // Work and expiration may both try to finish; guard so we only call once.
        let completion = BackgroundRefreshCompletion(refreshTask: refreshTask)

        AppDiagnosticsLogger.breadcrumb("background_task_started")
        let work = startRefresh(
            handler: refreshHandler,
            completion: completion,
            scheduleNext: scheduleNextRefresh
        )

        // Expiration handler: BackgroundTasks may invoke this on a non-main
        // queue. Logging is nonisolated; cancel + `setTaskCompleted` must hop.
        refreshTask.expirationHandler = {
            AppDiagnosticsLogger.logger(for: .tasks).notice("background_task_expired")
            AppDiagnosticsLogger.breadcrumb("background_task_expired")
            handleExpiredAppRefresh(work: work, completion: completion)
        }
    }

    /// Runs one delivered background refresh and returns its work, if any.
    ///
    /// With no `handler` (the app is in persistence recovery, so nothing was
    /// composed), completes with failure at once, touches no watchlist data, and
    /// does not reschedule: iOS would otherwise keep waking an app that cannot
    /// refresh. The next successful composition schedules again.
    ///
    /// Otherwise chains the next request first, so a failure or expiration
    /// mid-run does not leave the app without a future schedule.
    @MainActor
    static func startRefresh(
        handler: (() async -> Bool)?,
        completion: BackgroundRefreshCompletion,
        scheduleNext: () -> Void
    ) -> Task<Void, Never>? {
        guard let handler else {
            AppDiagnosticsLogger.logger(for: .tasks).notice("background_task_unconfigured")
            AppDiagnosticsLogger.breadcrumb("background_task_unconfigured")
            completion.finish(success: false)
            return nil
        }
        scheduleNext()

        return Task { @MainActor in
            AppDiagnosticsLogger.logTaskStart("bg_app_refresh")
            let refreshSucceeded = await handler()
            if Task.isCancelled {
                AppDiagnosticsLogger.logTaskCancel("bg_app_refresh")
                completion.finish(success: false)
            } else {
                AppDiagnosticsLogger.logTaskComplete("bg_app_refresh")
                completion.finish(success: refreshSucceeded)
            }
        }
    }

    /// Safe to call from `BGAppRefreshTask.expirationHandler`, which
    /// BackgroundTasks may invoke on a non-main queue.
    ///
    /// Hops to the main actor before cancelling work or completing the BG task
    /// so Swift 6 executor checking does not trap in `setTaskCompleted`.
    /// `work` is nil when the task already completed without a handler.
    nonisolated static func handleExpiredAppRefresh(
        work: Task<Void, Never>?,
        completion: BackgroundRefreshCompletion
    ) {
        Task { @MainActor in
            work?.cancel()
            completion.finish(success: false)
        }
    }

    /// Submits the next `BGAppRefreshTaskRequest` at the configured interval.
    /// Safe to call from launch and again at the start of each background run.
    @MainActor
    static func scheduleNextRefresh() {
        let interval = BackgroundRefreshConfiguration.refreshInterval
        let nextRefreshAt = Date(timeIntervalSinceNow: interval)
        diagnostics?.recordNextScheduledRefresh(at: nextRefreshAt)
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        // Earliest begin date is a hint, not a guarantee of fire time.
        request.earliestBeginDate = nextRefreshAt
        do {
            try BGTaskScheduler.shared.submit(request)
            AppDiagnosticsLogger.logger(for: .tasks)
                .notice("background_task_scheduled earliest=\(interval, privacy: .public)s")
            AppDiagnosticsLogger.breadcrumb("background_task_scheduled")
        } catch {
            AppDiagnosticsLogger.logger(for: .tasks)
                .error(
                    "background_task_schedule_failed error=\(String(describing: error), privacy: .public)"
                )
        }
    }
}

// MARK: - Registration guard

/// Performs a background-task registration at most once.
///
/// The system kills the app on a second registration of the same identifier,
/// so repeated calls are ignored. A `false` result (the identifier is missing
/// from the built app's `BGTaskSchedulerPermittedIdentifiers`) is logged and
/// not retried; later submissions then fail and are logged on their own.
@MainActor
final class BackgroundTaskRegistration {
    private let register: @MainActor () -> Bool
    /// True once `register` has been called, whatever it returned.
    private(set) var hasAttempted = false
    /// What the single `register` call returned.
    private(set) var didRegister = false

    init(register: @escaping @MainActor () -> Bool) {
        self.register = register
    }

    func registerIfNeeded() {
        guard !hasAttempted else {
            AppDiagnosticsLogger.breadcrumb("background_task_register_repeat_ignored")
            return
        }
        hasAttempted = true
        didRegister = register()
        if didRegister {
            AppDiagnosticsLogger.breadcrumb("background_task_registered")
        } else {
            AppDiagnosticsLogger.logger(for: .tasks).fault("background_task_register_failed")
            AppDiagnosticsLogger.breadcrumb("background_task_register_failed")
        }
    }
}

// MARK: - Completion guard

/// Ensures `BGAppRefreshTask.setTaskCompleted` is invoked at most once.
///
/// Needed because normal completion and the expiration handler can race; calling
/// `setTaskCompleted` twice is undefined / logged as an error by the system.
///
/// `@MainActor` is required: the task is registered with `using: .main`, and
/// `setTaskCompleted` must run on that executor. Callers that may be off-main
/// (the expiration handler) must hop before `finish(success:)`.
///
/// The type is implicitly `Sendable` via main-actor isolation, so it can be
/// captured by the `@Sendable` expiration handler without `@unchecked Sendable`.
/// `BGAppRefreshTask` stays on this actor and is not shared across executors.
@MainActor
final class BackgroundRefreshCompletion {
    private let finished = Mutex(false)
    private let complete: @MainActor (Bool) -> Void

    init(refreshTask: BGAppRefreshTask) {
        self.complete = { success in
            refreshTask.setTaskCompleted(success: success)
        }
    }

    init(complete: @escaping @MainActor (Bool) -> Void) {
        self.complete = complete
    }

    @MainActor
    func finish(success: Bool) {
        let shouldComplete = finished.withLock { finished in
            guard !finished else { return false }
            finished = true
            return true
        }
        guard shouldComplete else { return }
        complete(success)
    }
}
