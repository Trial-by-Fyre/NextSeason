//
//  NotificationService.swift
//  NextSeason
//

import Foundation
import UIKit
import UserNotifications

/// What happened to one delivery request (review finding R03).
///
/// Only `failed` is safe to retry: it means the request never reached the
/// system. Re-adding a request whose identifier matches an already delivered
/// notification alerts the user again, so `unknown` is never retried.
nonisolated enum NotificationDeliveryOutcome: Sendable, Equatable {
    /// The system accepted the request.
    case accepted
    /// Not attempted: alerts are not permitted, or delivery is off for this refresh.
    case suppressed
    /// The request was not scheduled: the system rejected it, or the task was
    /// cancelled before it was submitted.
    case failed
    /// The request was submitted, but whether the system accepted it is unknown.
    case unknown
}

/// Narrow delivery surface used by refresh / diagnostics so they can be tested
/// without the full permission API.
@MainActor
protocol NotificationDelivering: AnyObject {
    @discardableResult
    func deliver(_ content: SeasonNotificationContent) async -> NotificationDeliveryOutcome
}

/// Full permission + settings + delivery surface for SwiftUI and view models.
@MainActor
protocol NotificationManaging: NotificationDelivering {
    func authorizationStatus() async -> UNAuthorizationStatus
    func needsAuthorizationPrompt() async -> Bool
    func deferAuthorizationPrompt()
    func isDenied() async -> Bool
    func canDeliverVisibleAlerts() async -> Bool
    func openNotificationSettings()
    /// Shows the system permission dialog when still `.notDetermined`; otherwise opens Settings.
    func enableNotificationsFromSettingsEntryPoint() async
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool
    @discardableResult
    func deliver(_ content: SeasonNotificationContent, requestIdentifier: String) async
        -> NotificationDeliveryOutcome
    @discardableResult
    func deliverAfterDelay(
        _ content: SeasonNotificationContent,
        requestIdentifier: String,
        delay: TimeInterval
    ) async -> NotificationDeliveryOutcome
}

/// Local notification permission and delivery for season-change alerts (FR-011, FR-012).
///
/// Responsibilities:
/// - **Permission UX:** decide when to show the in-app prompt, honor "Not Now"
///   deferral (UserDefaults), call the system authorization dialog, and deep-link
///   into Settings when the user has already decided.
/// - **Delivery:** turn `SeasonNotificationContent` into a `UNNotificationRequest`
///   with `showID` in `userInfo` so `NotificationRouting` can deep-link on tap.
///   Request identifiers incorporate the status signature so duplicate states
///   replace rather than stack.
///
/// UI tests short-circuit permission helpers to avoid system sheets. Debug builds
/// can inject a fake authorization status for unit tests.
@MainActor
final class NotificationService: NotificationManaging {
    private let center: UNUserNotificationCenter
    private let userDefaults: UserDefaults
    private let analytics: any AnalyticsTracking
    #if DEBUG
        private let authorizationStatusForTesting: UNAuthorizationStatus?
        private let schedulerForTesting: SchedulerForTesting?
    #endif

    init(
        center: UNUserNotificationCenter = .current(),
        userDefaults: UserDefaults = .standard,
        analytics: any AnalyticsTracking
    ) {
        self.center = center
        self.userDefaults = userDefaults
        self.analytics = analytics
        #if DEBUG
            self.authorizationStatusForTesting = nil
            self.schedulerForTesting = nil
        #endif
    }

    #if DEBUG
        /// Test seam: fixed authorization status so unit tests never present the
        /// system permission dialog (which would block the test process).
        init(
            userDefaults: UserDefaults,
            authorizationStatusForTesting: UNAuthorizationStatus,
            analytics: any AnalyticsTracking
        ) {
            self.center = .current()
            self.userDefaults = userDefaults
            self.authorizationStatusForTesting = authorizationStatusForTesting
            self.schedulerForTesting = nil
            self.analytics = analytics
        }

        /// Stands in for the system's permission check and `add` call, which cannot
        /// be made to fail on demand, so tests can check each delivery outcome.
        struct SchedulerForTesting {
            var alertsPermitted: Bool
            var add: @MainActor (UNNotificationRequest) async throws -> Void
        }

        /// Test seam: schedules through `scheduler` instead of the system center.
        init(scheduler: SchedulerForTesting, analytics: any AnalyticsTracking) {
            self.center = .current()
            self.userDefaults = .standard
            self.authorizationStatusForTesting = nil
            self.schedulerForTesting = scheduler
            self.analytics = analytics
        }

        func resetDeferredPromptForTesting() {
            userDefaults.removeObject(forKey: Self.deferredPromptKey)
        }
    #endif

    func authorizationStatus() async -> UNAuthorizationStatus {
        #if DEBUG
            if let authorizationStatusForTesting {
                return authorizationStatusForTesting
            }
        #endif
        return await center.notificationSettings().authorizationStatus
    }

    /// UserDefaults flag set when the user taps "Not Now" on the in-app prompt.
    /// Blocks further automatic prompts until cleared (e.g. Settings entry point).
    private static let deferredPromptKey = "notificationPromptDeferred"

    /// True when the system has never asked and the user has not deferred the in-app prompt.
    func needsAuthorizationPrompt() async -> Bool {
        guard !UITestingConfiguration.isEnabled else { return false }
        guard !userDefaults.bool(forKey: Self.deferredPromptKey) else { return false }
        return await authorizationStatus() == .notDetermined
    }

    /// Records that the user dismissed the in-app permission prompt without deciding.
    func deferAuthorizationPrompt() {
        userDefaults.set(true, forKey: Self.deferredPromptKey)
    }

    /// True when the user previously denied notification permission.
    func isDenied() async -> Bool {
        guard !UITestingConfiguration.isEnabled else { return false }
        return await authorizationStatus() == .denied
    }

    /// True when alert banners can be shown (permission granted and alerts enabled).
    func canDeliverVisibleAlerts() async -> Bool {
        guard !UITestingConfiguration.isEnabled else { return false }
        #if DEBUG
            if let authorizationStatusForTesting {
                return NotificationAuthorizationPolicy.canDeliverAlerts(
                    authorizationStatusForTesting)
            }
        #endif
        let settings = await center.notificationSettings()
        return NotificationAuthorizationPolicy.canDeliverAlerts(from: settings)
    }

    /// Opens the system Notifications settings page for this app when possible.
    func openNotificationSettings() {
        // The general app settings page does not expose the notifications toggle
        // after the user taps "Don't Allow". iOS 16+ provides a dedicated deep link.
        if let url = URL(string: UIApplication.openNotificationSettingsURLString),
            UIApplication.shared.canOpenURL(url)
        {
            UIApplication.shared.open(url)
            return
        }
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Entry point for Watchlist banner, About, and post-deny alerts.
    ///
    /// - Still `.notDetermined` (including after "Not Now"): clear deferral and
    ///   show the system permission dialog.
    /// - Any other status: open Settings so the user can change the toggle.
    func enableNotificationsFromSettingsEntryPoint() async {
        guard !UITestingConfiguration.isEnabled else { return }
        let status = await authorizationStatus()
        switch status {
        case .notDetermined:
            // Clear a prior "Not Now" deferral so the system prompt can appear.
            userDefaults.removeObject(forKey: Self.deferredPromptKey)
            _ = await requestAuthorizationIfNeeded()
        case .denied, .authorized, .provisional, .ephemeral:
            openNotificationSettings()
        @unknown default:
            openNotificationSettings()
        }
    }

    /// Requests system permission when still undecided; returns whether alerts are allowed.
    ///
    /// No-ops when the user previously dismissed the in-app prompt with "Not Now"
    /// (see `deferAuthorizationPrompt`). If already authorized, returns `true`
    /// without prompting again. If denied, returns `false` (Settings is the only path).
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        guard !userDefaults.bool(forKey: Self.deferredPromptKey) else { return false }
        let status = await authorizationStatus()
        if NotificationAuthorizationPolicy.canDeliverAlerts(status) { return true }
        switch status {
        case .denied:
            return false
        case .notDetermined:
            #if DEBUG
                // When tests inject authorization status, never present the system
                // permission dialog — it blocks the unit-test process until dismissed.
                if authorizationStatusForTesting != nil {
                    return false
                }
            #endif
            do {
                let granted = try await center.requestAuthorization(options: [
                    .alert, .sound, .badge,
                ])
                analytics.track(
                    .notificationPermission(result: granted ? .granted : .denied)
                )
                return granted
            } catch {
                analytics.track(.notificationPermission(result: .denied))
                analytics.trackNonFatalError(error, context: "notification_authorization")
                return false
            }
        default:
            return false
        }
    }

    /// Schedules an immediate local notification (nil trigger → deliver ASAP).
    @discardableResult
    func deliver(_ content: SeasonNotificationContent) async -> NotificationDeliveryOutcome {
        await scheduleNotification(content, requestIdentifier: nil, trigger: nil)
    }

    @discardableResult
    func deliver(_ content: SeasonNotificationContent, requestIdentifier: String) async
        -> NotificationDeliveryOutcome
    {
        await scheduleNotification(content, requestIdentifier: requestIdentifier, trigger: nil)
    }

    /// Beta diagnostics helper: schedules delivery with the system so the
    /// notification can arrive after the app is backgrounded or terminated.
    @discardableResult
    func deliverAfterDelay(
        _ content: SeasonNotificationContent,
        requestIdentifier: String,
        delay interval: TimeInterval
    ) async -> NotificationDeliveryOutcome {
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, interval),
            repeats: false
        )
        return await scheduleNotification(
            content, requestIdentifier: requestIdentifier, trigger: trigger)
    }

    /// Builds and adds a `UNNotificationRequest` when alerts are allowed.
    ///
    /// - `userInfo["showID"]` is what `NotificationRouting` reads on tap.
    /// - Default identifier embeds show ID + status signature so re-scheduling
    ///   the same next-season state replaces the prior pending request.
    ///
    /// Cancellation alone never makes the outcome `unknown` (R03 scenario 15):
    /// before submission it is `failed`, which is safe to retry; once submitted,
    /// `add`'s own result is awaited and used.
    private func scheduleNotification(
        _ content: SeasonNotificationContent,
        requestIdentifier: String?,
        trigger: UNNotificationTrigger?
    ) async -> NotificationDeliveryOutcome {
        guard await alertsPermitted() else { return .suppressed }
        guard !Task.isCancelled else { return .failed }

        let notification = UNMutableNotificationContent()
        let title = content.title
        let body = content.body
        notification.title = title
        notification.body = body
        notification.sound = .default
        notification.userInfo = ["showID": content.showID]

        let identifier =
            requestIdentifier
            ?? "show-\(content.showID)-\(StatusChangeDetector.signature(for: content.status))"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: notification,
            trigger: trigger
        )

        do {
            try await add(request)
        } catch is CancellationError {
            // Submitted, but cancelled before the system answered; the request may
            // still have been accepted, so it must not be retried.
            analytics.trackNonFatalError(
                CancellationError(), context: "notification_schedule_unknown")
            return .unknown
        } catch {
            // Expected and recoverable now that the refresh retries a failed
            // delivery, so no DEBUG assertion here.
            analytics.trackNonFatalError(error, context: "notification_schedule")
            return .failed
        }
        analytics.track(.notificationReminderScheduled)
        // Background delivery never hits `willPresent` / `didReceive` unless
        // the user taps. Record eligibility here so the next foreground can
        // request a review after the system accepted the notification.
        NotificationRouting.noteShowNotificationExperience(
            userInfo: notification.userInfo,
            requestIdentifier: identifier
        )
        return .accepted
    }

    private func alertsPermitted() async -> Bool {
        #if DEBUG
            if let schedulerForTesting { return schedulerForTesting.alertsPermitted }
        #endif
        let settings = await center.notificationSettings()
        return NotificationAuthorizationPolicy.canDeliverAlerts(from: settings)
    }

    private func add(_ request: UNNotificationRequest) async throws {
        #if DEBUG
            if let schedulerForTesting {
                try await schedulerForTesting.add(request)
                return
            }
        #endif
        try await center.add(request)
    }
}
