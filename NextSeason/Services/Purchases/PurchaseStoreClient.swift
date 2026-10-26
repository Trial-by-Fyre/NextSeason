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
    /// `confirmation` presents StoreKit's sheet from the calling view; test
    /// doubles ignore it.
    func purchase(
        productID: String,
        confirmation: PurchaseConfirmation?,
        onVerified: @escaping @MainActor (StoreTransaction) async -> Void
    ) async throws -> PurchaseOutcome
    /// Whether an active, non-revoked monthly or annual subscription entitlement
    /// exists (or `.unverified` when a Plus entitlement failed verification), and
    /// when the active entitlement expires or renews.
    func plusEntitlementStatus() async -> PlusEntitlementStatus
    /// Triggers App Store sync (Restore Purchases); caller re-reads entitlements.
    func restorePurchases() async throws
    /// Long-lived listener for `Transaction.updates` (Ask to Buy, renewals, etc.).
    func observeTransactionUpdates(
        _ onVerified: @escaping @MainActor (StoreTransaction) async -> Void
    )
    /// Cancels the updates task; called from `PurchaseService.deinit`.
    func stopObservingTransactionUpdates()
}

/// Result of scanning StoreKit's current entitlements for Plus.
///
/// `.unverified` means a Plus entitlement exists but StoreKit could not verify
/// it. That is neither confirmed access nor a confirmed lapse: it never grants
/// Plus, and it never pauses saved shows.
nonisolated enum PlusEntitlementCheck: Equatable, Sendable {
    case active
    case inactive
    case unverified
}

/// One StoreKit entitlement read.
nonisolated struct PlusEntitlementStatus: Equatable, Sendable {
    let check: PlusEntitlementCheck
    /// Latest verified Plus `Transaction.expirationDate` ("expires or renews").
    /// Only present for `.active`; drives the re-check while the app stays open.
    let expirationDate: Date?

    init(check: PlusEntitlementCheck, expirationDate: Date? = nil) {
        self.check = check
        self.expirationDate = check == .active ? expirationDate : nil
    }
}

/// StoreKit-independent snapshot of a verified transaction.
nonisolated struct StoreTransaction: Equatable, Sendable {
    let id: UInt64
    let productID: String
    /// False for renewals or unknown reasons; only customer purchases complete tests.
    let isCustomerPurchase: Bool

    /// Defaults to a customer purchase for existing test doubles. The live StoreKit
    /// client always supplies the reason explicitly from the verified transaction.
    init(id: UInt64, productID: String, isCustomerPurchase: Bool = true) {
        self.id = id
        self.productID = productID
        self.isCustomerPurchase = isCustomerPurchase
    }

    /// Parsed product kind; `nil` for unknown product IDs.
    var kind: StoreProductKind? {
        StoreProductID(rawValue: productID)?.kind
    }
}
