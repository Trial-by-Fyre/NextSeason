//
//  PlusAccountSection.swift
//  NextSeason
//

import SwiftUI

/// About-screen Plus status, upgrade CTA, and Restore Purchases.
///
/// Distinguishes StoreKit entitlement (including unresolved "Checking…" and
/// "Unable to Verify Plus"), complimentary Plus, and the free-tier cap. The
/// decisions live in `PlusAccountPresentation`; the upgrade button appears only
/// when the user is known to be limited.
struct PlusAccountSection: View {
    @Environment(PurchaseService.self) private var purchases
    /// Bound to the parent sheet that presents `PlusStoreView`.
    @Binding var isShowingPlusStore: Bool
    /// Restore feedback for restores started here (the Plus sheet has its own).
    @State private var restoreNotice: String?

    var body: some View {
        let presentation = PlusAccountPresentation(purchases)
        Section {
            LabeledContent {
                Text(presentation.statusValue)
            } label: {
                Label("Watchlist", systemImage: "star")
            }

            // Testing override reminder, so StoreKit-only access is not mistaken
            // for a lost complimentary grant.
            if purchases.isIgnoringComplimentaryPlus {
                Label("Complimentary Plus ignored (Diagnostics)", systemImage: "testtube.2")
                    .foregroundStyle(.orange)
            }

            if presentation.showsUpgradeButton {
                Button {
                    isShowingPlusStore = true
                } label: {
                    Label("Unlock NextSeason Plus", systemImage: "lock.open")
                }
                .accessibilityIdentifier(AccessibilityID.Store.plusUnlock)
            }

            Button {
                Task {
                    if await purchases.restorePurchases() == .success {
                        restoreNotice = purchases.restoreNotice
                    }
                }
            } label: {
                Label("Restore Purchases", systemImage: "arrow.clockwise")
            }
            .accessibilityIdentifier(AccessibilityID.Store.restore)
            .disabled(purchases.isPurchasing)
        } header: {
            Text("NextSeason Plus")
        } footer: {
            Text(presentation.footerText)
        }
        .alert(
            "Restore Purchases",
            isPresented: Binding(
                get: { restoreNotice != nil },
                set: { if !$0 { restoreNotice = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreNotice ?? "")
        }
    }
}
