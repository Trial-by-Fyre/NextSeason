//
//  NotificationCenterDelegate.swift
//  NextSeason
//

import Foundation
import UIKit
import UserNotifications

/// Forwards notification taps to `AppNavigationCoordinator` on the main actor
/// and records production season-notification experience for the review prompt.
@MainActor
enum NotificationRouting {
    static weak var coordinator: AppNavigationCoordinator?
    static var analytics: (any AnalyticsTracking)?
    /// Attached from `AppCompositionRoot.configureNonUITestRuntime`; may be nil
    /// during background delivery.
    static weak var reviewPrompt: ReviewPromptCoordinator?
    private static var bufferedShowID: Int?
    private static var bufferedAnimated = false

    static func setCoordinator(_ coordinator: AppNavigationCoordinator) {
        self.coordinator = coordinator
        deliverBufferedNavigation()
    }

    static func setAnalytics(_ analytics: any AnalyticsTracking) {
        self.analytics = analytics
    }

    /// Wires the review coordinator once composition succeeds. The delegate is
    /// installed earlier, at launch; until then, deliveries are saved to
    /// `unattachedReviewPromptStore` instead.
    static func setReviewPrompt(_ coordinator: ReviewPromptCoordinator?) {
        reviewPrompt = coordinator
    }

    /// True for production season-change alerts. Diagnostics identifiers are
    /// excluded so TestFlight tooling does not consume the per-version request.
    static func isProductionShowNotification(
        userInfo: [AnyHashable: Any],
        requestIdentifier: String
    ) -> Bool {
        guard showID(from: userInfo) != nil else { return false }
        return !requestIdentifier.hasPrefix("debug-")
    }

    /// Records a qualifying production notification experience (successful scheduling,
    /// foreground presentation, or tap).
    ///
    /// Drives the per-version review prompt, or persists to
    /// `unattachedReviewPromptStore` when the coordinator is not attached yet
    /// (background launch).
    static func noteShowNotificationExperience(
        userInfo: [AnyHashable: Any],
        requestIdentifier: String
    ) {
        guard
            isProductionShowNotification(
                userInfo: userInfo,
                requestIdentifier: requestIdentifier
            )
        else { return }
        if let reviewPrompt {
            reviewPrompt.noteShowNotificationDelivered()
            return
        }
        // Persist even when the coordinator is not attached (for example a
        // background launch) so the next foreground can still request a review.
        unattachedReviewPromptStore.markNotificationReceived()
    }

    /// Called once from `NextSeasonApp.init`, before composition: Apple requires
    /// the delegate to be set before launch finishes, including launches that
    /// fall into persistence recovery.
    static func installDelegate(center: UNUserNotificationCenter = .current()) {
        center.delegate = NotificationCenterDelegate.shared
    }

    /// Drops a tap buffered while no coordinator was attached. Called once
    /// Reset Local Data has wiped the store (even if reopening then fails), so
    /// the app does not later open a show whose saved row and delivered
    /// notification the reset removed. Try Again keeps the buffered tap.
    static func discardBufferedNavigation() {
        guard bufferedShowID != nil else { return }
        bufferedShowID = nil
        AppDiagnosticsLogger.breadcrumb("notification_tap_discarded_after_reset")
    }

    /// If the coordinator has been set, queue the show from the notification tap.  If it has not, buffer
    /// (save) it for processing later. The buffer holds one tap (the latest) in
    /// memory for this process only.
    /// - Parameter showID: TVMaze show ID from the notification payload.
    /// - Parameter animated: `true` when the app was already foreground-active at the
    ///   time of the tap (in-app navigation), `false` for a launch/foreground tap.
    static func routeToShow(showID: Int, animated: Bool) {
        analytics?.track(.notificationTapped(showID: showID))
        if let coordinator {
            coordinator.queueShowNavigation(showID: showID, animated: animated)
        } else {
            bufferedShowID = showID
            bufferedAnimated = animated
        }
    }

    /// Queue the buffered (saved) show information from the notification tap
    private static func deliverBufferedNavigation() {
        guard let showID = bufferedShowID, let coordinator else { return }
        bufferedShowID = nil
        coordinator.queueShowNavigation(showID: showID, animated: bufferedAnimated)
    }

    static func showID(from userInfo: [AnyHashable: Any]) -> Int? {
        if let id = userInfo["showID"] as? Int { return id }
        if let number = userInfo["showID"] as? NSNumber { return number.intValue }
        return nil
    }

    #if DEBUG
        /// Isolated store used when `reviewPrompt` is unset in unit tests.
        static var unattachedReviewPromptStoreForTesting: ReviewPromptStore?

        /// Clears routing state between unit tests.
        static func resetForTesting() {
            coordinator = nil
            analytics = nil
            reviewPrompt = nil
            unattachedReviewPromptStoreForTesting = nil
            bufferedShowID = nil
        }
    #endif

    /// Fallback persistence when `reviewPrompt` is nil so a background-delivered
    /// notification still qualifies for a review on next foreground.
    private static var unattachedReviewPromptStore: ReviewPromptStore {
        #if DEBUG
            if let unattachedReviewPromptStoreForTesting {
                return unattachedReviewPromptStoreForTesting
            }
        #endif
        return ReviewPromptStore()
    }
}

/// `UNUserNotificationCenter` delegate that presents banners while foregrounded
/// and routes taps through `NotificationRouting`.
final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCenterDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let request = notification.request
        NotificationRouting.noteShowNotificationExperience(
            userInfo: request.content.userInfo,
            requestIdentifier: request.identifier
        )
        return [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let request = response.notification.request
        let userInfo = request.content.userInfo
        NotificationRouting.noteShowNotificationExperience(
            userInfo: userInfo,
            requestIdentifier: request.identifier
        )
        guard let showID = NotificationRouting.showID(from: userInfo) else { return }
        // A tap while the app is already foreground-active is an in-app navigation
        // (animate); a tap that brings the app forward from background/launch is not.
        let wasActive = UIApplication.shared.applicationState == .active
        NotificationRouting.routeToShow(showID: showID, animated: wasActive)
    }
}
