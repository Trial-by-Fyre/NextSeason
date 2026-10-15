//
//  DiagnosticsDelayedNotificationDelivering.swift
//  NextSeason
//

import Foundation

/// Routes pipeline notifications through `deliverAfterDelay` so testers can
/// background the app before the alert arrives.
@MainActor
final class DiagnosticsDelayedNotificationDelivering: NotificationDelivering {
    private let service: any NotificationManaging
    private let delay: TimeInterval

    init(service: any NotificationManaging, delay: TimeInterval) {
        self.service = service
        self.delay = delay
    }

    /// Passes the real outcome on, so simulated runs follow the same retry rules.
    @discardableResult
    func deliver(_ content: SeasonNotificationContent) async -> NotificationDeliveryOutcome {
        let identifier = "debug-pipeline-\(content.showID)-\(UUID().uuidString)"
        return await service.deliverAfterDelay(
            content, requestIdentifier: identifier, delay: delay)
    }
}
