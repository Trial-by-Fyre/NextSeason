//
//  AppAboutPresentationModifier.swift
//  NextSeason
//

import SwiftUI

/// Presents About (always) and Diagnostics (Debug / TestFlight only).
///
/// About is the Restore Purchases and tip-jar surface, so it ships in
/// production. The footer and sheets are omitted during UI tests so layout
/// and existing XCUITests stay stable.
@MainActor
struct AppAboutPresentationModifier: ViewModifier {
    @Environment(PurchaseService.self) private var purchases
    @State private var activeSheet: AppInfoSheet?
    @State private var betaBuildAvailability = BetaBuildAvailability.shared
    /// The add that opened the paywall; finished on dismissal if Plus unlocked.
    @State private var onPlusUnlocked: (@MainActor () -> Void)?

    func body(content: Content) -> some View {
        if UITestingConfiguration.isEnabled {
            content
        } else {
            content
                .environment(\.openAppAbout) {
                    activeSheet = .about
                }
                .environment(\.presentPlusStore) { onUnlocked in
                    AppDiagnosticsLogger.breadcrumb(
                        "paywall_present source=root current=\(activeSheet?.id ?? "none")")
                    onPlusUnlocked = onUnlocked
                    activeSheet = .plusStore
                }
                .environment(\.openDiagnostics) {
                    guard betaBuildAvailability.isAvailable else { return }
                    activeSheet = .diagnostics
                }
                .sheet(item: $activeSheet, onDismiss: finishPlusUnlockIfNeeded) { sheet in
                    switch sheet {
                    case .about:
                        AppAboutView {
                            activeSheet = .diagnostics
                        }
                        .environment(purchases)
                    case .diagnostics:
                        DiagnosticsView()
                    case .plusStore:
                        PlusStoreView()
                            .environment(purchases)
                    }
                }
                .task {
                    await betaBuildAvailability.refresh()
                }
        }
    }

    /// Runs after the sheet is gone, so any alert the add raises (such as the
    /// notification prompt) can present. Cancelling or a pending purchase leaves
    /// the watchlist limited, and the add is dropped.
    private func finishPlusUnlockIfNeeded() {
        AppDiagnosticsLogger.breadcrumb("root_sheet_dismissed pendingAdd=\(onPlusUnlocked != nil)")
        guard let action = onPlusUnlocked else { return }
        onPlusUnlocked = nil
        if purchases.isUnlimitedWatchlist {
            action()
        }
    }
}

/// Mutually exclusive sheets wired from environment callbacks (`openAppAbout`,
/// `openDiagnostics`, `presentPlusStore`). About can hand off to Diagnostics
/// without dismissing the sheet stack first.
private enum AppInfoSheet: Identifiable {
    case about
    case diagnostics
    case plusStore

    var id: String {
        switch self {
        case .about:
            return "about"
        case .diagnostics:
            return "diagnostics"
        case .plusStore:
            return "plusStore"
        }
    }
}
