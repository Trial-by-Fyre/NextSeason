//
//  PlusAccountSection.swift
//  NextSeason
//

import SwiftUI

/// About-screen Plus status, upgrade CTA, and Restore Purchases.
///
/// Distinguishes StoreKit entitlement (including unresolved "Checking…"),
/// complimentary Plus, and the free-tier cap. The upgrade button appears
/// only after StoreKit resolves and the user is still limited.
struct PlusAccountSection: View {
    @Environment(PurchaseService.self) private var purchases
    /// Bound to the parent sheet that presents `PlusStoreView`.
    @Binding var isShowingPlusStore: Bool

    var body: some View {
        Section {
            LabeledContent {
                Text(statusValue)
            } label: {
                Label("Watchlist", systemImage: "star")
            }

            if purchases.hasResolvedStoreEntitlement && !purchases.isUnlimitedWatchlist {
                Button {
                    isShowingPlusStore = true
                } label: {
                    Label("Unlock NextSeason Plus", systemImage: "lock.open")
                }
                .accessibilityIdentifier(AccessibilityID.Store.plusUnlock)
            }

            Button {
                Task { _ = await purchases.restorePurchases() }
            } label: {
                Label("Restore Purchases", systemImage: "arrow.clockwise")
            }
            .accessibilityIdentifier(AccessibilityID.Store.restore)
            .disabled(purchases.isPurchasing)
        } header: {
            Text("NextSeason Plus")
        } footer: {
            Text(footerText)
        }
    }

    /// Watchlist capacity label: unlimited (Plus or complimentary),
    /// "Checking…" while StoreKit entitlements are unresolved, or the free cap.
    private var statusValue: String {
        if purchases.isStoreEntitled || purchases.isComplimentary {
            return String(localized: "Unlimited")
        }
        if !purchases.hasResolvedStoreEntitlement {
            return String(localized: "Checking…")
        }
        return String(
            localized: "Up to \(WatchlistLimitPolicy.freeShowLimit) shows"
        )
    }

    /// Footer copy explaining Plus, complimentary access, or entitlement confirmation.
    private var footerText: String {
        if purchases.isStoreEntitled {
            return String(localized: "You have NextSeason Plus.")
        }
        if purchases.isComplimentary {
            return String(
                localized:
                    "You have permanent complimentary NextSeason Plus. Thank you for beta testing."
            )
        }
        if !purchases.hasResolvedStoreEntitlement {
            return String(localized: "Confirming your NextSeason Plus status.")
        }
        return String(
            localized: "NextSeason Plus removes the watchlist limit."
        )
    }
}
