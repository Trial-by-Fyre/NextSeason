//
//  NotificationDeliveryOutcomeTests.swift
//  NextSeasonTests
//

import Foundation
import Testing
import UserNotifications

@testable import NextSeason

// Review finding R03: `NotificationService` reports what happened to each
// request. Scenario numbers refer to the R03 section of
// Documentation/Reviews/2026-10-12-r03-r13-behavior-matrix.md (revision 4).

/// A scheduler `add` that records requests and can fail or suspend.
@MainActor
private final class FakeAdd {
    var error: (any Error)?
    /// When true, `add` waits until `release()`.
    var suspends = false
    private(set) var requests: [UNNotificationRequest] = []
    private var suspended: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func add(_ request: UNNotificationRequest) async throws {
        requests.append(request)
        if suspends {
            await withCheckedContinuation { continuation in
                suspended = continuation
                started?.resume()
                started = nil
            }
        }
        if let error { throw error }
    }

    func waitUntilSuspended() async {
        if suspended != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func release() {
        suspended?.resume()
        suspended = nil
    }
}

private let content = SeasonNotificationContent(
    showID: 7, showName: "Show 7", status: .airing(season: 2))

@MainActor
private func makeService(
    _ fake: FakeAdd, alertsPermitted: Bool = true,
    analytics: RecordingAnalyticsService = RecordingAnalyticsService()
) -> NotificationService {
    NotificationService(
        scheduler: .init(alertsPermitted: alertsPermitted, add: { try await fake.add($0) }),
        analytics: analytics)
}

@MainActor
struct NotificationDeliveryOutcomeTests {
    @Test("Accepted when alerts are permitted and the system accepts the request")
    func acceptedMapping() async {
        let fake = FakeAdd()

        let outcome = await makeService(fake).deliver(content)

        #expect(outcome == .accepted, "Scenario 21")
        #expect(fake.requests.map(\.identifier) == ["show-7-airing:2"])
    }

    @Test("Suppressed without submitting when alerts are not permitted")
    func suppressedMapping() async {
        let fake = FakeAdd()

        let outcome = await makeService(fake, alertsPermitted: false).deliver(content)

        #expect(outcome == .suppressed, "Scenario 21")
        #expect(fake.requests.isEmpty)
    }

    /// Would also crash here if the old DEBUG `assertionFailure` were still in place.
    @Test("Failed when the system rejects the request, recorded in analytics")
    func failedMapping() async {
        let fake = FakeAdd()
        fake.error = NSError(
            domain: UNErrorDomain, code: UNError.Code.notificationsNotAllowed.rawValue)
        let analytics = RecordingAnalyticsService()

        let outcome = await makeService(fake, analytics: analytics).deliver(content)

        #expect(outcome == .failed, "Scenarios 15.3 and 21")
        #expect(scheduleFailures(analytics) == 1)
    }

    @Test("Every delivery variant reports the outcome")
    func variantsReportOutcome() async {
        let fake = FakeAdd()
        fake.error = URLError(.unknown)
        let service = makeService(fake)

        #expect(await service.deliver(content, requestIdentifier: "a") == .failed)
        #expect(
            await service.deliverAfterDelay(content, requestIdentifier: "b", delay: 5) == .failed)
        fake.error = nil
        #expect(
            await service.deliverAfterDelay(content, requestIdentifier: "c", delay: 5) == .accepted)
    }

    @Test("Cancellation before submission is a failure, so the alert is retried")
    func cancelledBeforeSubmission() async {
        let fake = FakeAdd()
        let service = makeService(fake)

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await service.deliver(content)
        }

        #expect(await task.value == .failed, "Scenario 15.1")
        #expect(fake.requests.isEmpty, "Never submitted")
    }

    @Test("A task cancelled while the system is adding the request still reports acceptance")
    func cancelledDuringAddThenAccepted() async {
        let fake = FakeAdd()
        fake.suspends = true
        let service = makeService(fake)

        let task = Task { await service.deliver(content) }
        await fake.waitUntilSuspended()
        task.cancel()
        fake.release()

        #expect(await task.value == .accepted, "Scenario 15.2: the real result is awaited")
    }

    @Test("A submitted request whose result is lost to cancellation is unknown")
    func cancelledDuringAddUnknown() async {
        let fake = FakeAdd()
        fake.error = CancellationError()
        let analytics = RecordingAnalyticsService()

        let outcome = await makeService(fake, analytics: analytics).deliver(content)

        #expect(outcome == .unknown, "Scenario 15.4")
        #expect(fake.requests.count == 1)
        #expect(scheduleFailures(analytics) == 0, "Not counted as a scheduling failure")
    }
}

@MainActor
private func scheduleFailures(_ analytics: RecordingAnalyticsService) -> Int {
    analytics.events.filter {
        if case .nonFatalError(_, let context) = $0 { return context == "notification_schedule" }
        return false
    }.count
}
