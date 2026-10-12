//
//  PlusAccountPresentation.swift
//  NextSeason
//

import Foundation

/// About's Plus status, footer, and upgrade-button decisions, derived from
/// `PurchaseService` so `PlusAccountSection` and tests share one source.
///
/// Presentation only: entitlement handling, watchlist limits, and pause/resume
/// continue to read `PurchaseService` directly.
nonisolated enum PlusAccountPresentation: Equatable, Sendable {
    /// Simulate Free Tier is active. Carries whether StoreKit has finished its
    /// first read, which has always gated the upgrade button during simulation.
    case simulatedFree(hasResolvedStoreEntitlement: Bool)
    /// StoreKit has reported an active Plus subscription.
    case paidPlus
    /// Permanent complimentary Plus without an active subscription.
    case complimentaryPlus
    /// The first StoreKit entitlement read has not finished.
    case checking
    /// The first read found a Plus entitlement StoreKit could not verify. This is
    /// not a confirmed lapse (saved shows stay as they are), so About must not
    /// present it as the ordinary free tier or offer an upgrade.
    case unableToVerify
    /// StoreKit confirmed there is no active Plus subscription.
    case free

    /// Order matters: simulation masks actual access, paid Plus wins over
    /// complimentary, and complimentary access is definitive even while StoreKit
    /// is loading or unverified.
    @MainActor
    init(_ purchases: PurchaseService) {
        if purchases.isSimulatingFreeTier {
            self = .simulatedFree(
                hasResolvedStoreEntitlement: purchases.hasResolvedStoreEntitlement)
        } else if purchases.isStoreEntitled {
            self = .paidPlus
        } else if purchases.isComplimentary {
            self = .complimentaryPlus
        } else {
            switch purchases.storeEntitlement {
            case .loading: self = .checking
            case .unverified: self = .unableToVerify
            case .resolved: self = .free
            }
        }
    }

    /// Watchlist capacity label shown in the About row.
    var statusValue: String {
        switch self {
        case .simulatedFree:
            String(localized: "Up to \(WatchlistLimitPolicy.freeShowLimit) shows (simulated)")
        case .paidPlus, .complimentaryPlus:
            String(localized: "Unlimited")
        case .checking:
            String(localized: "Checking…")
        case .unableToVerify:
            String(localized: "Unable to Verify Plus")
        case .free:
            String(localized: "Up to \(WatchlistLimitPolicy.freeShowLimit) shows")
        }
    }

    /// Footer copy explaining simulation, Plus, complimentary access, a pending
    /// or failed verification, or what Plus offers.
    var footerText: String {
        switch self {
        case .simulatedFree:
            String(
                localized:
                    "Free tier simulation is active. Your shows and actual access are preserved. Turn it off in Diagnostics to restore access."
            )
        case .paidPlus:
            String(localized: "You have NextSeason Plus.")
        case .complimentaryPlus:
            String(
                localized:
                    "You have permanent complimentary NextSeason Plus. Thank you for beta testing."
            )
        case .checking:
            String(localized: "Confirming your NextSeason Plus status.")
        case .unableToVerify:
            String(
                localized:
                    "NextSeason couldn't verify your subscription status. Your saved shows are preserved. Check your connection and try Restore Purchases."
            )
        case .free:
            String(localized: "NextSeason Plus removes the watchlist limit.")
        }
    }

    /// The upgrade button appears only when the user is known to be limited.
    /// Restore Purchases is always available and is not decided here.
    var showsUpgradeButton: Bool {
        switch self {
        case .simulatedFree(let hasResolvedStoreEntitlement): hasResolvedStoreEntitlement
        case .free: true
        case .paidPlus, .complimentaryPlus, .checking, .unableToVerify: false
        }
    }
}
