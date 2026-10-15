//
//  NotificationStatusModelTests.swift
//  NextSeasonTests
//

import Foundation
import Testing
import UserNotifications

@testable import NextSeason

@MainActor
struct NotificationStatusModelTests {
    private final class StubNotificationManaging: NotificationManaging {
        var status: UNAuthorizationStatus = .notDetermined
        var canDeliver = false
        private(set) var enablementCallCount = 0

        func authorizationStatus() async -> UNAuthorizationStatus { status }
        func needsAuthorizationPrompt() async -> Bool { status == .notDetermined }
        func deferAuthorizationPrompt() {}
        func isDenied() async -> Bool { status == .denied }
        func canDeliverVisibleAlerts() async -> Bool { canDeliver }
        func openNotificationSettings() {}

        func enableNotificationsFromSettingsEntryPoint() async {
            enablementCallCount += 1
            status = .authorized
            canDeliver = true
        }

        func requestAuthorizationIfNeeded() async -> Bool { canDeliver }
        func deliver(_ content: SeasonNotificationContent) async -> NotificationDeliveryOutcome {
            .accepted
        }
        func deliver(_ content: SeasonNotificationContent, requestIdentifier: String) async
            -> NotificationDeliveryOutcome
        { .accepted }
        func deliverAfterDelay(
            _ content: SeasonNotificationContent,
            requestIdentifier: String,
            delay: TimeInterval
        ) async -> NotificationDeliveryOutcome { .accepted }
    }

    @Test("Refreshing after an enablement action updates the presentation model")
    func refreshAfterEnablementUpdatesModel() async {
        let service = StubNotificationManaging()
        let model = NotificationStatusModel()

        await model.refresh(using: service)
        #expect(model.showsDisabledBanner)
        #expect(model.canDeliverVisibleAlerts == false)

        await service.enableNotificationsFromSettingsEntryPoint()
        await model.refresh(using: service)

        #expect(service.enablementCallCount == 1)
        #expect(model.canDeliverVisibleAlerts)
        #expect(model.showsDisabledBanner == false)
        #expect(model.statusLabel == "Enabled")
    }

    @Test("A slower older refresh cannot overwrite a newer result")
    func slowerOlderRefreshDoesNotOverwriteNewerResult() async {
        let service = ReentrantNotificationManaging()
        let model = NotificationStatusModel()
        service.model = model

        await model.refresh(using: service)

        #expect(model.canDeliverVisibleAlerts)
        #expect(model.showsDisabledBanner == false)
        #expect(service.canDeliverCallCount == 2)
    }
}

/// On the first delivery-status read, flips to authorized and re-enters `refresh`
/// before returning the original disabled snapshot — exercising generation discard.
@MainActor
private final class ReentrantNotificationManaging: NotificationManaging {
    weak var model: NotificationStatusModel?
    private(set) var canDeliverCallCount = 0
    private var didReenter = false
    private var canDeliver = false
    private var status: UNAuthorizationStatus = .notDetermined

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func canDeliverVisibleAlerts() async -> Bool {
        canDeliverCallCount += 1
        if !didReenter, let model {
            didReenter = true
            canDeliver = true
            status = .authorized
            await model.refresh(using: self)
            // Outer load still reports the pre-reentry (stale) values.
            canDeliver = false
            status = .notDetermined
        }
        return canDeliver
    }

    func needsAuthorizationPrompt() async -> Bool { status == .notDetermined }
    func deferAuthorizationPrompt() {}
    func isDenied() async -> Bool { status == .denied }
    func openNotificationSettings() {}
    func enableNotificationsFromSettingsEntryPoint() async {}
    func requestAuthorizationIfNeeded() async -> Bool { canDeliver }
    func deliver(_ content: SeasonNotificationContent) async -> NotificationDeliveryOutcome {
        .accepted
    }
    func deliver(_ content: SeasonNotificationContent, requestIdentifier: String) async
        -> NotificationDeliveryOutcome
    { .accepted }
    func deliverAfterDelay(
        _ content: SeasonNotificationContent,
        requestIdentifier: String,
        delay: TimeInterval
    ) async -> NotificationDeliveryOutcome { .accepted }
}
