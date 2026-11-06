//
//  LaunchRegistrationRecoveryTests.swift
//  NextSeasonTests
//

import Foundation
import Testing

@testable import NextSeason

/// Automated rows of `Documentation/Reviews/LaunchRegistrationRecovery-2026-11-05.md`:
/// one-time background-task registration, a background task delivered with no
/// configured handler, and a notification tap buffered during recovery.
/// Successful recovery itself is verified on device.
///
/// Serialized because `NotificationRouting` holds process-wide state.
@MainActor
@Suite(.serialized)
struct LaunchRegistrationRecoveryTests {
    // MARK: Registration (rows 6–8)

    @Test("A second registration call does not register again")
    func repeatRegistrationIsIgnored() {
        var calls = 0
        let registration = BackgroundTaskRegistration {
            calls += 1
            return true
        }

        registration.registerIfNeeded()
        registration.registerIfNeeded()

        #expect(calls == 1)
        #expect(registration.didRegister)
    }

    @Test("A failed registration is recorded once and not retried")
    func failedRegistrationIsNotRetried() {
        var calls = 0
        let registration = BackgroundTaskRegistration {
            calls += 1
            return false
        }

        registration.registerIfNeeded()
        registration.registerIfNeeded()

        #expect(calls == 1)
        #expect(registration.hasAttempted)
        #expect(registration.didRegister == false)
    }

    @Test("The built app permits the refresh task identifier and background fetch")
    func infoPlistPermitsRefreshTask() throws {
        let identifiers = try #require(
            Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers")
                as? [String])
        #expect(identifiers.contains(RefreshScheduler.taskIdentifier))
        let modes = try #require(
            Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])
        #expect(modes.contains("fetch"))
    }

    // MARK: Background task with no handler (rows 9–10)

    @Test("With no handler, the task fails once, does no work, and is not rescheduled")
    func unconfiguredTaskFailsWithoutRescheduling() async {
        var outcomes: [Bool] = []
        var schedules = 0
        let completion = BackgroundRefreshCompletion { outcomes.append($0) }

        let work = RefreshScheduler.startRefresh(
            handler: nil, completion: completion, scheduleNext: { schedules += 1 })

        #expect(work == nil, "No refresh work started")
        #expect(outcomes == [false])
        #expect(schedules == 0)

        // A later expiration must not complete the task a second time.
        RefreshScheduler.handleExpiredAppRefresh(work: work, completion: completion)
        await Task { @MainActor in }.value
        #expect(outcomes == [false])
    }

    @Test("With a handler, the next request is scheduled first and the result is reported")
    func configuredTaskSchedulesThenRuns() async throws {
        var events: [String] = []
        var outcomes: [Bool] = []
        let completion = BackgroundRefreshCompletion { outcomes.append($0) }

        let work = RefreshScheduler.startRefresh(
            handler: {
                events.append("handler")
                return true
            },
            completion: completion,
            scheduleNext: { events.append("schedule") }
        )
        try await #require(work).value

        #expect(events == ["schedule", "handler"])
        #expect(outcomes == [true])
    }

    // MARK: Buffered notification tap (rows 13–16)

    @Test("Only the latest buffered tap is kept until the coordinator attaches")
    func bufferKeepsLatestTap() {
        NotificationRouting.resetForTesting()
        defer { NotificationRouting.resetForTesting() }

        NotificationRouting.routeToShow(showID: 1, animated: false)
        NotificationRouting.routeToShow(showID: 2, animated: false)
        let coordinator = AppNavigationCoordinator()
        NotificationRouting.setCoordinator(coordinator)

        #expect(coordinator.pendingShowID == 2)
    }

    @Test("A wipe that succeeds drops the buffered tap, even when reopening fails")
    func successfulWipeDropsBufferedTap() {
        NotificationRouting.resetForTesting()
        defer { NotificationRouting.resetForTesting() }
        var state = persistenceRecovery()
        NotificationRouting.routeToShow(showID: 82, animated: false)
        var steps: [String] = []

        state.resetLocalData(
            removeStore: { steps.append("removeStore") },
            clearNotifications: { steps.append("clearNotifications") },
            discardBufferedNotificationTap: {
                steps.append("discardTap")
                NotificationRouting.discardBufferedNavigation()
            },
            makeRoot: {
                steps.append("makeRoot")
                throw StubError()
            },
            failureTracker: makeTracker()
        )

        #expect(steps == ["removeStore", "clearNotifications", "discardTap", "makeRoot"])
        guard case .recovery(let context) = state else {
            Issue.record("Expected recovery when reopening fails")
            return
        }
        #expect(context.kind == .persistenceFailureAfterReset)
        let coordinator = AppNavigationCoordinator()
        NotificationRouting.setCoordinator(coordinator)
        #expect(coordinator.pendingShowID == nil, "Tap dropped after the wipe")
    }

    @Test("A failed wipe keeps the buffered tap")
    func failedWipeKeepsBufferedTap() {
        NotificationRouting.resetForTesting()
        defer { NotificationRouting.resetForTesting() }
        var state = persistenceRecovery()
        NotificationRouting.routeToShow(showID: 82, animated: false)
        var discarded = false

        state.resetLocalData(
            removeStore: { throw StubError() },
            clearNotifications: {},
            discardBufferedNotificationTap: { discarded = true },
            makeRoot: { throw StubError() },
            failureTracker: makeTracker()
        )

        #expect(discarded == false)
        let coordinator = AppNavigationCoordinator()
        NotificationRouting.setCoordinator(coordinator)
        #expect(coordinator.pendingShowID == 82)
    }

    @Test("A failed Try Again keeps the buffered tap")
    func failedRetryKeepsBufferedTap() {
        NotificationRouting.resetForTesting()
        defer { NotificationRouting.resetForTesting() }
        let tracker = makeTracker()
        _ = tracker.beginLaunchAttempt()
        _ = tracker.beginLaunchAttempt()
        var state = AppLaunchState.bootstrap(
            makeRoot: { throw StubError() }, failureTracker: tracker)
        NotificationRouting.routeToShow(showID: 82, animated: false)

        state.retryLaunch(makeRoot: { throw StubError() }, failureTracker: tracker)

        let coordinator = AppNavigationCoordinator()
        NotificationRouting.setCoordinator(coordinator)
        #expect(coordinator.pendingShowID == 82)
    }

    // MARK: Helpers

    /// Launch state after an initial store-open failure (Reset offered).
    private func persistenceRecovery() -> AppLaunchState {
        AppLaunchState.bootstrap(makeRoot: { throw StubError() }, failureTracker: makeTracker())
    }

    private func makeTracker() -> LaunchFailureTracker {
        let suiteName = "LaunchRegistrationRecoveryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return LaunchFailureTracker(
            defaults: defaults,
            buildIdentifier: "test-build",
            countsPreviousUnexpectedTermination: true
        )
    }
}

private struct StubError: Error {}
