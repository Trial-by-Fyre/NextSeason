//
//  StubPurchaseStoreClient.swift
//  NextSeason
//

import Foundation

/// Per-call entitlement read script for ordering and failure tests.
struct EntitlementCheckScript: Sendable {
    var delayed = false
    var result: PlusEntitlementCheck?
}

/// In-memory StoreKit double for tests, previews, and UI tests.
@MainActor
final class StubPurchaseStoreClient: PurchaseStoreClient {
    /// Catalog returned by `loadProducts(ids:)`.
    var products: [StoreProduct]
    /// Entitlement state returned by `plusEntitlementCheck()`.
    var isStoreEntitled: Bool
    /// When true, `plusEntitlementCheck()` reports `.unverified` (verification failure).
    var reportsUnverifiedEntitlement = false
    /// Outcome returned from `purchase`; `.success` still delivers a transaction when applicable.
    var purchaseOutcome: PurchaseOutcome
    /// When set, `restorePurchases()` throws this error.
    var restoreError: (any Error)?
    /// When set, `loadProducts(ids:)` throws this error.
    var loadError: (any Error)?

    /// When true, `plusEntitlementCheck()` suspends until
    /// `releaseEntitlementResolution()` (when no script entry supplies `delayed`).
    var delayEntitlementResolution = false
    /// When non-empty, each entitlement read consumes the next script entry so
    /// overlapping reads can return different answers in a fixed order.
    var entitlementCheckScripts: [EntitlementCheckScript] = []

    /// Invoked after a verified transaction has been delivered to the app and
    /// immediately before the stub records it as finished.
    var onFinish: (@MainActor () -> Void)?

    /// Transaction IDs passed through verify → onVerified → finish in order.
    private(set) var finishedTransactionIDs: [UInt64] = []
    /// Last transaction created by a successful stub purchase.
    private(set) var lastPurchasedTransaction: StoreTransaction?
    /// Number of continuations blocked in `plusEntitlementCheck()` when delayed.
    private(set) var entitlementWaiterCount = 0
    /// Entitlement reads that have entered `plusEntitlementCheck()` (including suspended).
    private(set) var startedEntitlementCheckCount = 0
    private(set) var observeTransactionUpdatesCallCount = 0
    private(set) var stopObservingTransactionUpdatesCallCount = 0
    /// Ordered record of entitlement and observer calls for test assertions.
    private(set) var recordedCalls: [RecordedCall] = []

    /// Recorded side effects for test assertions.
    enum RecordedCall: Equatable, Sendable {
        case observeTransactionUpdates
        case plusEntitlementCheck
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

    func plusEntitlementCheck() async -> PlusEntitlementCheck {
        startedEntitlementCheckCount += 1
        recordedCalls.append(.plusEntitlementCheck)
        let script = entitlementCheckScripts.isEmpty ? nil : entitlementCheckScripts.removeFirst()
        let shouldDelay = script?.delayed ?? delayEntitlementResolution
        if shouldDelay {
            await withCheckedContinuation { continuation in
                entitlementWaiters.append(continuation)
                entitlementWaiterCount = entitlementWaiters.count
            }
        }
        if let result = script?.result { return result }
        if reportsUnverifiedEntitlement { return .unverified }
        return isStoreEntitled ? .active : .inactive
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

    /// Completes the next suspended entitlement read, if any.
    func releaseNextEntitlementResolution() {
        guard !entitlementWaiters.isEmpty else { return }
        let waiter = entitlementWaiters.removeFirst()
        entitlementWaiterCount = entitlementWaiters.count
        waiter.resume()
    }

    /// Completes the most recently suspended entitlement read, if any, leaving
    /// older reads held (models a stalled earlier scan).
    func releaseNewestEntitlementResolution() {
        guard let waiter = entitlementWaiters.popLast() else { return }
        entitlementWaiterCount = entitlementWaiters.count
        waiter.resume()
    }

    /// Completes any in-flight entitlement reads.
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
