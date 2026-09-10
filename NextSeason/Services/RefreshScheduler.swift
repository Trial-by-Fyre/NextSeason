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
/// Lifecycle (wired from `AppCompositionRoot.configureBackgroundRefresh`):
/// 1. `registerBackgroundTask()` — tell the system how to launch this identifier.
/// 2. `configure(refreshHandler:)` — store the async work to run (typically
///    `WatchlistRefreshService.refreshAll`).
/// 3. `scheduleNextRefresh()` — submit the next earliest-begin request.
/// 4. When iOS launches the task → `handleAppRefresh` runs the handler, then
///    marks the task completed (or cancelled on expiration).
///    The launch handler is delivered on the main queue (`using: .main`).
///    `expirationHandler` may arrive on another queue and must hop to
///    `@MainActor` before cancelling work or completing the `BGAppRefreshTask`.
///
/// Background refresh is not guaranteed on interval; iOS may delay or skip runs.
enum RefreshScheduler {
    static let taskIdentifier = "com.TrialByFyre.NextSeason.watchlist-refresh"

    /// Closure invoked when a background refresh task runs (set once at launch).
    @MainActor private static var refreshHandler: (() async -> Void)?
    @MainActor private static var diagnostics: BetaRefreshDiagnostics?

    /// Stores the work to perform when iOS delivers a background refresh.
    @MainActor
    static func configure(
        diagnostics: BetaRefreshDiagnostics? = nil,
        refreshHandler: @escaping () async -> Void
    ) {
        self.diagnostics = diagnostics
        self.refreshHandler = refreshHandler
    }

    /// Must be called during app launch (before the app finishes launching) so
    /// the system can associate `taskIdentifier` with our handler.
    static func registerBackgroundTask() {
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
        // Chain the next request immediately so a failure/expiration mid-run
        // does not leave the app without a future schedule.
        scheduleNextRefresh()

        let work = Task { @MainActor in
            AppDiagnosticsLogger.logTaskStart("bg_app_refresh")
            await refreshHandler?()
            if Task.isCancelled {
                AppDiagnosticsLogger.logTaskCancel("bg_app_refresh")
                completion.finish(success: false)
            } else {
                AppDiagnosticsLogger.logTaskComplete("bg_app_refresh")
                completion.finish(success: true)
            }
        }

        // Expiration handler: BackgroundTasks may invoke this on a non-main
        // queue. Logging is nonisolated; cancel + `setTaskCompleted` must hop.
        refreshTask.expirationHandler = {
            AppDiagnosticsLogger.logger(for: .tasks).notice("background_task_expired")
            AppDiagnosticsLogger.breadcrumb("background_task_expired")
            handleExpiredAppRefresh(work: work, completion: completion)
        }
    }

    /// Safe to call from `BGAppRefreshTask.expirationHandler`, which
    /// BackgroundTasks may invoke on a non-main queue.
    ///
    /// Hops to the main actor before cancelling work or completing the BG task
    /// so Swift 6 executor checking does not trap in `setTaskCompleted`.
    nonisolated static func handleExpiredAppRefresh(
        work: Task<Void, Never>,
        completion: BackgroundRefreshCompletion
    ) {
        Task { @MainActor in
            work.cancel()
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
