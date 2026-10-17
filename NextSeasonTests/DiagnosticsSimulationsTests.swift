//
//  DiagnosticsSimulationsTests.swift
//  NextSeasonTests
//

import Foundation
import Testing
import UserNotifications

@testable import NextSeason

// Review finding R15: DiagnosticsView created a new simulation runner on every
// tap, so the two-step scenario never reached step 2. Runner-only tests missed
// it; these drive `DiagnosticsSimulations`, which the view's buttons call.

@MainActor
private final class CountingNotifications: NotificationManaging {
    private(set) var immediateDeliveries = 0
    private(set) var delayedDeliveries = 0

    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func needsAuthorizationPrompt() async -> Bool { false }
    func deferAuthorizationPrompt() {}
    func isDenied() async -> Bool { false }
    func canDeliverVisibleAlerts() async -> Bool { true }
    func openNotificationSettings() {}
    func enableNotificationsFromSettingsEntryPoint() async {}
    func requestAuthorizationIfNeeded() async -> Bool { true }
    func deliver(_ content: SeasonNotificationContent) async -> NotificationDeliveryOutcome {
        immediateDeliveries += 1
        return .accepted
    }
    func deliver(_ content: SeasonNotificationContent, requestIdentifier: String) async
        -> NotificationDeliveryOutcome
    { .accepted }
    func deliverAfterDelay(
        _ content: SeasonNotificationContent,
        requestIdentifier: String,
        delay: TimeInterval
    ) async -> NotificationDeliveryOutcome {
        delayedDeliveries += 1
        return .accepted
    }
}

@MainActor
struct DiagnosticsSimulationsTests {
    private let notifications: CountingNotifications
    let sut: DiagnosticsSimulations
    private let createdRunners: CreatedRunnerCount

    init() {
        let notifications = CountingNotifications()
        let createdRunners = CreatedRunnerCount()
        self.notifications = notifications
        self.createdRunners = createdRunners
        sut = DiagnosticsSimulations { template in
            createdRunners.value += 1
            return DiagnosticsSimulatedUpdateRunner(
                pipelineTemplate: template,
                notifications: notifications,
                diagnostics: BetaRefreshDiagnostics(),
                analytics: RecordingAnalyticsService()
            )
        }
    }

    @Test("Repeated taps advance step 1, then step 2, then start over at step 1")
    func tapsAdvanceThroughBothSteps() async {
        let template = Self.watchlistShow(id: 10)

        let first = await sut.runNextStep(using: template)
        let second = await sut.runNextStep(using: template)
        let third = await sut.runNextStep(using: template)

        #expect(first.hasPrefix("Step 1"), "\(first)")
        #expect(second.hasPrefix("Step 2"), "\(second)")
        #expect(notifications.immediateDeliveries == 1, "Step 2 reaches the notification branch")
        #expect(third.hasPrefix("Step 1"), "Resets after a completed step 2: \(third)")
        #expect(createdRunners.value == 1)
    }

    @Test("A refreshed copy of the same watchlist show keeps the scenario")
    func refreshedTemplateKeepsScenario() async {
        var template = Self.watchlistShow(id: 10)
        await sut.runNextStep(using: template)

        template.lastCheckedAt = template.lastCheckedAt.addingTimeInterval(3_600)
        let second = await sut.runNextStep(using: template)

        #expect(second.hasPrefix("Step 2"), "\(second)")
    }

    @Test("A different watchlist show starts a fresh scenario")
    func differentTemplateStartsOver() async {
        await sut.runNextStep(using: Self.watchlistShow(id: 10))

        let next = await sut.runNextStep(using: Self.watchlistShow(id: 11))

        #expect(next.hasPrefix("Step 1"), "\(next)")
        #expect(createdRunners.value == 2)
    }

    @Test("The delayed pipeline does not reset a two-step scenario in progress")
    func delayedPipelineLeavesStepScenario() async {
        let template = Self.watchlistShow(id: 10)
        await sut.runNextStep(using: template)

        await sut.runDelayedNewSeasonNotification(using: template)
        let second = await sut.runNextStep(using: template)

        #expect(notifications.delayedDeliveries == 1)
        #expect(second.hasPrefix("Step 2"), "\(second)")
    }

    private static func watchlistShow(id: Int) -> TrackedShow {
        TrackedShow(
            id: id,
            name: "Show \(id)",
            posterMediumURL: nil,
            status: .running,
            nextSeason: .returningNoSeasonYet,
            sourceUpdatedAt: .now,
            lastCheckedAt: .now,
            dateAdded: .now
        )
    }
}

@MainActor
private final class CreatedRunnerCount {
    var value = 0
}
