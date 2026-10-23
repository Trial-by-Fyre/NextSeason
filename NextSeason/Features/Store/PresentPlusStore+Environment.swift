//
//  PresentPlusStore+Environment.swift
//  NextSeason
//

import SwiftUI

/// Presents the Plus sheet. The argument runs once after the sheet closes, only
/// if the watchlist is then unlimited (purchase or restore), so the add that
/// opened the paywall can finish.
typealias PresentPlusStoreAction = (_ onUnlocked: @escaping @MainActor () -> Void) -> Void

private struct PresentPlusStoreKey: EnvironmentKey {
    static let defaultValue: PresentPlusStoreAction? = nil
}

extension EnvironmentValues {
    /// Presents the NextSeason Plus purchase sheet from Search, Show Detail, or About.
    ///
    /// Set by the root tab host; `nil` means presentation is unavailable
    /// (previews or tests that omit the wiring).
    var presentPlusStore: PresentPlusStoreAction? {
        get { self[PresentPlusStoreKey.self] }
        set { self[PresentPlusStoreKey.self] = newValue }
    }
}
