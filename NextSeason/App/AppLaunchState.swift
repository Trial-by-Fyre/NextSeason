//
//  AppLaunchState.swift
//  NextSeason
//

import Foundation
import UserNotifications
import os

/// Result of app bootstrap: a working composition root, or a blocking
/// recovery flow when the watchlist store cannot be opened or a crash loop
/// is detected.
enum AppLaunchState {
    case ready(AppCompositionRoot)
    case recovery(RecoveryContext)

    /// Why recovery is showing. Distinguishes a generic crash loop (no
    /// persistence evidence) from a SwiftData open failure (reset is allowed).
    enum RecoveryKind: Sendable, Equatable {
        /// Composition was skipped after repeated unexpected process launches.
        case crashLoop
        /// Creating `AppCompositionRoot` threw (typically `ModelContainer`).
        case persistenceFailure
        /// The on-disk store was removed, but a new container still will not open.
        case persistenceFailureAfterReset
    }

    /// User-facing recovery payload after a persistence open failure or
    /// repeated unexpected launches.
    struct RecoveryContext {
        let kind: RecoveryKind
        /// Most recent `ModelContainer` / composition failure, or a
        /// `RepeatedLaunchFailure` when composition was skipped.
        let error: any Error
        /// First launch failure, when a later retry failed with a different error.
        let originalError: (any Error)?
        /// Failure from `PersistentStoreReset`, if the user chose Reset Local Data
        /// and the store files could not be removed.
        let resetError: (any Error)?
        /// Consecutive unexpected launches recorded at the time of this recovery.
        let consecutiveLaunchFailures: Int

        init(
            kind: RecoveryKind,
            error: any Error,
            originalError: (any Error)? = nil,
            resetError: (any Error)? = nil,
            consecutiveLaunchFailures: Int = 0
        ) {
            self.kind = kind
            self.error = error
            self.originalError = originalError
            self.resetError = resetError
            self.consecutiveLaunchFailures = consecutiveLaunchFailures
        }

        /// True after the on-disk watchlist store was successfully removed.
        var didResetStore: Bool { kind == .persistenceFailureAfterReset }

        /// Destructive reset is only offered when persistence has actually
        /// failed to open — not for a generic crash loop.
        var allowsPersistenceReset: Bool { kind == .persistenceFailure }

        /// Non-destructive retry: crash-loop recovery, or after a successful
        /// store wipe that still cannot initialize.
        var allowsRetry: Bool {
            kind == .crashLoop || kind == .persistenceFailureAfterReset
        }

        /// Shareable diagnostics for this failure. Includes the current and
        /// original SwiftData errors plus any reset failure and crash-loop
        /// markers; these are for TestFlight triage, not on-screen copy.
        ///
        /// Notification authorization is not queried during recovery (the
        /// flow stays synchronous), so the report records that status as
        /// unavailable rather than as disabled.
        func diagnosticsReport() -> String {
            AnalyticsDiagnosticsReport.formatted(
                counters: AnalyticsCountersStore().snapshot(),
                notificationsEnabled: nil,
                persistenceFailure: String(describing: error),
                originalPersistenceFailure: originalError.map { String(describing: $0) },
                persistenceResetFailure: resetError.map { String(describing: $0) },
                localStoreWasReset: didResetStore,
                consecutiveLaunchFailures: consecutiveLaunchFailures,
                compositionSkippedDueToCrashLoop: kind == .crashLoop
            )
        }
    }

    /// Records this process launch, then attempts composition. On a crash
    /// loop, skips opening the store and returns `.recovery`. On a thrown
    /// composition failure, logs diagnostics and returns `.recovery`
    /// instead of crashing.
    static func bootstrap(
        makeRoot: () throws -> AppCompositionRoot = { try AppCompositionRoot() },
        failureTracker: LaunchFailureTracker = LaunchFailureTracker()
    ) -> AppLaunchState {
        var attempt: LaunchAttemptResult
        if UITestingConfiguration.isEnabled {
            attempt = LaunchAttemptResult(
                consecutiveUnexpectedLaunchCount: 0,
                shouldSkipComposition: false
            )
        } else {
            attempt = failureTracker.beginLaunchAttempt()
        }
        if RecoveryFixture.forcesCrashLoop {
            // DEBUG recovery fixture: present crash-loop recovery on demand.
            attempt = LaunchAttemptResult(
                consecutiveUnexpectedLaunchCount: attempt.consecutiveUnexpectedLaunchCount,
                shouldSkipComposition: true
            )
        }

        if attempt.shouldSkipComposition {
            AppDiagnosticsLogger.breadcrumb("crash_loop_recovery_presented")
            AppDiagnosticsLogger.persistBreadcrumbsNow()
            failureTracker.noteReachedSafePath()
            return .recovery(
                RecoveryContext(
                    kind: .crashLoop,
                    error: RepeatedLaunchFailure(
                        consecutiveCount: attempt.consecutiveUnexpectedLaunchCount
                    ),
                    consecutiveLaunchFailures: attempt.consecutiveUnexpectedLaunchCount
                )
            )
        }

        return attemptComposition(
            makeRoot: makeRoot,
            failureTracker: failureTracker,
            consecutiveLaunchFailures: attempt.consecutiveUnexpectedLaunchCount
        )
    }

    /// Retries composition in this already-running process without recording
    /// a new launch. Bypasses the crash-loop skip so an explicit user retry
    /// can actually attempt to open the store.
    mutating func retryLaunch(
        makeRoot: () throws -> AppCompositionRoot = { try AppCompositionRoot() },
        failureTracker: LaunchFailureTracker = LaunchFailureTracker()
    ) {
        guard case .recovery(let previous) = self else { return }

        AppDiagnosticsLogger.breadcrumb("launch_retry_requested")
        AppDiagnosticsLogger.persistBreadcrumbsNow()

        switch Self.attemptComposition(
            makeRoot: makeRoot,
            failureTracker: failureTracker,
            consecutiveLaunchFailures: previous.consecutiveLaunchFailures
        ) {
        case .ready(let root):
            self = .ready(root)
        case .recovery(let fresh):
            let kind: RecoveryKind =
                previous.kind == .persistenceFailureAfterReset
                ? .persistenceFailureAfterReset
                : .persistenceFailure
            self = .recovery(
                RecoveryContext(
                    kind: kind,
                    error: fresh.error,
                    originalError: previous.originalError ?? previous.error,
                    resetError: previous.resetError,
                    consecutiveLaunchFailures: previous.consecutiveLaunchFailures
                )
            )
        }
    }

    /// Deletes the on-disk watchlist store (after the user confirmed),
    /// clears scheduled notifications and any buffered notification tap, and
    /// retries composition in this process. Refused unless persistence has
    /// actually failed to open.
    mutating func resetLocalData(
        removeStore: () throws -> Void = {
            try PersistentStoreReset.removeProductionStore()
        },
        clearNotifications: () -> Void = {
            // The DEBUG recovery fixture wipes only its disposable store; the
            // device's notifications may belong to the real watchlist.
            guard !RecoveryFixture.isActive else {
                AppDiagnosticsLogger.breadcrumb("recovery_fixture_notification_clear_skipped")
                return
            }
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        },
        discardBufferedNotificationTap: () -> Void = {
            NotificationRouting.discardBufferedNavigation()
        },
        makeRoot: () throws -> AppCompositionRoot = { try AppCompositionRoot() },
        failureTracker: LaunchFailureTracker = LaunchFailureTracker()
    ) {
        guard case .recovery(let previous) = self, previous.allowsPersistenceReset else {
            return
        }

        AppDiagnosticsLogger.breadcrumb("persistence_store_reset_started")
        AppDiagnosticsLogger.persistBreadcrumbsNow()

        do {
            if !UITestingConfiguration.isEnabled {
                try removeStore()
                clearNotifications()
            }
            // The wipe succeeded, so a tap buffered during recovery points at a
            // show that is no longer saved; drop it even if reopening fails below.
            discardBufferedNotificationTap()
            AppDiagnosticsLogger.breadcrumb("persistence_store_reset_succeeded")
            AppDiagnosticsLogger.persistBreadcrumbsNow()

            switch Self.attemptComposition(
                makeRoot: makeRoot,
                failureTracker: failureTracker,
                consecutiveLaunchFailures: previous.consecutiveLaunchFailures
            ) {
            case .ready(let root):
                self = .ready(root)
            case .recovery(let fresh):
                self = .recovery(
                    RecoveryContext(
                        kind: .persistenceFailureAfterReset,
                        error: fresh.error,
                        originalError: previous.originalError ?? previous.error,
                        consecutiveLaunchFailures: previous.consecutiveLaunchFailures
                    )
                )
            }
        } catch {
            AppDiagnosticsLogger.breadcrumb("persistence_store_reset_failed")
            AppDiagnosticsLogger.persistBreadcrumbsNow()
            AppDiagnosticsLogger.logger(for: .persistence).error(
                "persistence_store_reset_failed error=\(String(describing: error), privacy: .public)"
            )
            self = .recovery(
                RecoveryContext(
                    kind: previous.kind,
                    error: previous.error,
                    originalError: previous.originalError,
                    resetError: error,
                    consecutiveLaunchFailures: previous.consecutiveLaunchFailures
                )
            )
        }
    }

    /// Creates `AppCompositionRoot` in the current process. Does not record
    /// a process launch or consult the crash-loop skip.
    private static func attemptComposition(
        makeRoot: () throws -> AppCompositionRoot,
        failureTracker: LaunchFailureTracker,
        consecutiveLaunchFailures: Int
    ) -> AppLaunchState {
        do {
            let root = try makeRoot()
            if !UITestingConfiguration.isEnabled {
                failureTracker.noteCompositionSucceeded()
            }
            configureRuntime(root)
            return .ready(root)
        } catch {
            AppDiagnosticsLogger.logModelContainerInitFailure(error)
            AppDiagnosticsLogger.breadcrumb("persistence_recovery_presented")
            AppDiagnosticsLogger.persistBreadcrumbsNow()
            if !UITestingConfiguration.isEnabled {
                failureTracker.noteReachedSafePath()
            }
            return .recovery(
                RecoveryContext(
                    kind: .persistenceFailure,
                    error: error,
                    consecutiveLaunchFailures: consecutiveLaunchFailures
                )
            )
        }
    }

    private static func configureRuntime(_ root: AppCompositionRoot) {
        if !UITestingConfiguration.isEnabled {
            root.configureNonUITestRuntime()
        } else {
            #if DEBUG
                FirstRunPreferences.resetSearchResultsHintForTesting()
                FirstRunPreferences.resetFirstSearchCompletedForTesting()
                WatchlistPreferences.resetCollapsedSectionsForTesting()
            #endif
        }
    }
}
