//
//  UITestingConfiguration.swift
//  NextSeason
//

import Foundation
import SwiftUI

/// Launch-argument helpers for XCUITest runs (`-UITesting`).
///
/// When enabled, composition root uses an in-memory watchlist and notification
/// helpers short-circuit system permission sheets.
enum UITestingConfiguration {
    static let launchArgument = UITestingLaunchArgument.uiTesting

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    /// Starts with one paused show and Free access (paused-row UI test).
    static var seedsPausedShow: Bool {
        isEnabled
            && ProcessInfo.processInfo.arguments.contains(UITestingLaunchArgument.seedPausedShow)
    }

    /// Sentinel search queries — see `UITestingSearchQuery` in NextSeasonShared.
    typealias SearchQuery = UITestingSearchQuery
}

extension View {
    /// VoiceOver hint for list rows that push show detail.
    func showDetailLinkAccessibility() -> some View {
        accessibilityHint(String(localized: "Opens show details"))
    }
}
