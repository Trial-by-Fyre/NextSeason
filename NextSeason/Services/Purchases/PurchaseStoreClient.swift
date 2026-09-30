//
//  PurchaseStoreClient.swift
//  NextSeason
//

import Foundation

/// StoreKit (or a test double) behind `PurchaseService`.
///
/// Verified transactions are delivered to the application through `onVerified`
/// (or the observer) *before* the client finishes them, so entitlement and tip
/// acknowledgement can be applied first.
@MainActor
protocol PurchaseStoreClient: AnyObject {
    func loadProducts(ids: [String]) async throws -> [StoreProduct]
    /// Runs the StoreKit purchase flow. Calls `onVerified` with a checked
    /// transaction before finishing it so entitlements can update first.
    func purchase(
        productID: String,
        onVerified: @escaping @MainActor (StoreTransaction) async -> Void
    ) async throws -> PurchaseOutcome
    /// True when an active, non-revoked monthly or annual subscription entitlement exists.
    func hasActivePlusEntitlement() async -> Bool
    /// Triggers App Store sync (Restore Purchases); caller re-reads entitlements.
    func restorePurchases() async throws
    /// Long-lived listener for `Transaction.updates` (Ask to Buy, renewals, etc.).
    func observeTransactionUpdates(
        _ onVerified: @escaping @MainActor (StoreTransaction) async -> Void
    )
    /// Cancels the updates task; called from `PurchaseService.deinit`.
    func stopObservingTransactionUpdates()
}

/// StoreKit-independent snapshot of a verified transaction.
nonisolated struct StoreTransaction: Equatable, Sendable {
    let id: UInt64
    let productID: String

    /// Parsed product kind; `nil` for unknown product IDs.
    var kind: StoreProductKind? {
        StoreProductID(rawValue: productID)?.kind
    }
}
