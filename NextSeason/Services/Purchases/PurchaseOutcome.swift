//
//  PurchaseOutcome.swift
//  NextSeason
//

import Foundation

/// Result of a StoreKit purchase or restore attempt, mapped for UI handling.
///
/// `.pending` covers Ask to Buy and other deferred completions, including local
/// StoreKit processing that still needs a resolved subscription status. `.failed`
/// carries a localized message suitable for alerts.
nonisolated enum PurchaseOutcome: Equatable, Sendable {
    case success
    case cancelled
    case pending
    case failed(String)
}

/// Errors thrown before or during StoreKit verification.
///
/// Mapped to user-facing copy via `LocalizedError`; surfaced by
/// `PurchaseService` as `.failed` outcomes or thrown from store clients.
nonisolated enum PurchaseError: LocalizedError, Equatable {
    case productUnavailable
    case unverified

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            String(localized: "That purchase option is not available right now.")
        case .unverified:
            String(localized: "NextSeason couldn't verify this purchase. Please try again.")
        }
    }
}
