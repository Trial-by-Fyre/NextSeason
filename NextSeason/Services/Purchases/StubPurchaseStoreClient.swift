//
//  StubPurchaseStoreClient.swift
//  NextSeason
//

import Foundation

/// In-memory StoreKit double for tests, previews, and UI tests.
@MainActor
final class StubPurchaseStoreClient: PurchaseStoreClient {
    /// Catalog returned by `loadProducts(ids:)`.
    var products: [StoreProduct]
    /// Entitlement state returned by `hasActivePlusEntitlement()`.
    var isStoreEntitled: Bool
    /// Outcome returned from `purchase`; `.success` still delivers a transaction when applicable.
    var purchaseOutcome: PurchaseOutcome
    /// When set, `restorePurchases()` throws this error.
    var restoreError: (any Error)?
    /// When set, `loadProducts(ids:)` throws this error.
    var loadError: (any Error)?

    /// When true, `hasActivePlusEntitlement()` suspends until
    /// `releaseEntitlementResolution()`.
    var delayEntitlementResolution = false

    /// Invoked after a verified transaction has been delivered to the app and
    /// immediately before the stub records it as finished.
    var onFinish: (@MainActor () -> Void)?

    /// Transaction IDs passed through verify → onVerified → finish in order.
    private(set) var finishedTransactionIDs: [UInt64] = []
    /// Last transaction created by a successful stub purchase.
    private(set) var lastPurchasedTransaction: StoreTransaction?
    /// Number of continuations blocked in `hasActivePlusEntitlement()` when delayed.
    private(set) var entitlementWaiterCount = 0
    private(set) var observeTransactionUpdatesCallCount = 0
    private(set) var stopObservingTransactionUpdatesCallCount = 0
    /// Ordered record of entitlement and observer calls for test assertions.
    private(set) var recordedCalls: [RecordedCall] = []

    /// Recorded side effects for test assertions.
    enum RecordedCall: Equatable, Sendable {
        case observeTransactionUpdates
        case hasActivePlusEntitlement
        case stopObservingTransactionUpdates
    }

    private var nextTransactionID: UInt64 = 1
    private var entitlementWaiters: [CheckedContinuation<Void, Never>] = []
    private var transactionObserver: (@MainActor (StoreTransaction) async -> Void)?

    init(
        products: [StoreProduct] = StoreProductID.allCases.map { StoreProduct($0) },
        isStoreEntitled: Bool = false,
        purchaseOutcome: PurchaseOutcome = .success
    ) {
        self.products = products
        self.isStoreEntitled = isStoreEntitled
        self.purchaseOutcome = purchaseOutcome
    }

    func loadProducts(ids: [String]) async throws -> [StoreProduct] {
        if let loadError { throw loadError }
        let requested = Set(ids)
        return products.filter { requested.contains($0.productID) }
    }

    func purchase(
        productID: String,
        onVerified: @escaping @MainActor (StoreTransaction) async -> Void
    ) async throws -> PurchaseOutcome {
        guard products.contains(where: { $0.productID == productID }) else {
            throw PurchaseError.productUnavailable
        }
        if purchaseOutcome == .success {
            let transaction = StoreTransaction(id: nextTransactionID, productID: productID)
            nextTransactionID += 1
            lastPurchasedTransaction = transaction
            if let id = StoreProductID(rawValue: productID) {
                switch id {
                case .plusAnnual, .plusMonthly:
                    isStoreEntitled = true
                case .tipTrailer, .tipPilot, .tipHitShow:
                    break
                }
            }
            await deliverThenFinish(transaction, onVerified: onVerified)
        }
        return purchaseOutcome
    }

    func hasActivePlusEntitlement() async -> Bool {
        recordedCalls.append(.hasActivePlusEntitlement)
        if delayEntitlementResolution {
            await withCheckedContinuation { continuation in
                entitlementWaiters.append(continuation)
                entitlementWaiterCount = entitlementWaiters.count
            }
        }
        return isStoreEntitled
    }

    func restorePurchases() async throws {
        if let restoreError { throw restoreError }
    }

    func observeTransactionUpdates(
        _ onVerified: @escaping @MainActor (StoreTransaction) async -> Void
    ) {
        observeTransactionUpdatesCallCount += 1
        recordedCalls.append(.observeTransactionUpdates)
        transactionObserver = onVerified
    }

    func stopObservingTransactionUpdates() {
        stopObservingTransactionUpdatesCallCount += 1
        recordedCalls.append(.stopObservingTransactionUpdates)
        transactionObserver = nil
    }

    /// Whether a transaction-update observer is currently registered.
    var isObservingTransactionUpdates: Bool {
        transactionObserver != nil
    }

    /// Completes any in-flight `hasActivePlusEntitlement()` waits.
    func releaseEntitlementResolution() {
        delayEntitlementResolution = false
        let waiters = entitlementWaiters
        entitlementWaiters.removeAll()
        entitlementWaiterCount = 0
        for waiter in waiters {
            waiter.resume()
        }
    }

    /// Delivers a later StoreKit update (Ask to Buy, restore, entitlement change).
    func emitVerifiedTransaction(_ transaction: StoreTransaction) async {
        guard let transactionObserver else { return }
        await deliverThenFinish(transaction, onVerified: transactionObserver)
    }

    private func deliverThenFinish(
        _ transaction: StoreTransaction,
        onVerified: @MainActor (StoreTransaction) async -> Void
    ) async {
        await onVerified(transaction)
        onFinish?()
        finishedTransactionIDs.append(transaction.id)
    }
}
