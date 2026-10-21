//
//  StoreKitPurchaseStoreClient.swift
//  NextSeason
//

import Foundation
import StoreKit

/// Live StoreKit 2 client: product loading, purchase, entitlements, and restore.
///
/// Caches loaded `Product` values for purchase. Verified transactions are
/// delivered to the app before `finish()` so entitlement state can update first.
@MainActor
final class StoreKitPurchaseStoreClient: PurchaseStoreClient {
    private var productsByID: [String: Product] = [:]
    private var updatesTask: Task<Void, Never>?

    func loadProducts(ids: [String]) async throws -> [StoreProduct] {
        let products = try await Product.products(for: ids)
        productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        if products.isEmpty {
            AppDiagnosticsLogger.breadcrumb("storekit_products_empty")
        }
        return products.compactMap(Self.storeProduct(from:))
    }

    func purchase(
        productID: String,
        onVerified: @escaping @MainActor (StoreTransaction) async -> Void
    ) async throws -> PurchaseOutcome {
        guard let product = productsByID[productID] else {
            throw PurchaseError.productUnavailable
        }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await deliverThenFinish(transaction, onVerified: onVerified)
            return .success
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .failed(
                String(localized: "The purchase could not be completed. Please try again.")
            )
        }
    }

    /// Scans current entitlements for an active Plus subscription. Ignores revoked
    /// transactions and consumable tips.
    ///
    /// `currentEntitlements` already includes subscriptions whose auto-renew is
    /// off (until they expire) and subscriptions in a billing grace period, so no
    /// separate expiration logic is needed. A Plus entitlement that fails
    /// verification reports `.unverified` rather than `.inactive`.
    ///
    /// Reports the latest expiration among verified, non-upgraded Plus entitlements
    /// (an upgraded transaction is superseded by its replacement). Unverified
    /// entries never supply a date.
    func plusEntitlementStatus() async -> PlusEntitlementStatus {
        var sawUnverifiedPlus = false
        var isActive = false
        var latestExpiration: Date?
        for await result in Transaction.currentEntitlements {
            let transaction: Transaction
            switch result {
            case .verified(let verified):
                transaction = verified
            case .unverified(let unverified, _):
                if Self.isPlus(unverified.productID) { sawUnverifiedPlus = true }
                continue
            }
            guard transaction.revocationDate == nil, Self.isPlus(transaction.productID) else {
                continue
            }
            isActive = true
            if !transaction.isUpgraded, let expiration = transaction.expirationDate {
                latestExpiration = max(latestExpiration ?? expiration, expiration)
            }
        }
        if isActive {
            return PlusEntitlementStatus(check: .active, expirationDate: latestExpiration)
        }
        if sawUnverifiedPlus {
            AppDiagnosticsLogger.breadcrumb("storekit_plus_entitlement_unverified")
            return PlusEntitlementStatus(check: .unverified)
        }
        return PlusEntitlementStatus(check: .inactive)
    }

    private static func isPlus(_ productID: String) -> Bool {
        switch StoreProductID(rawValue: productID) {
        case .plusAnnual, .plusMonthly: true
        case .tipTrailer, .tipPilot, .tipHitShow, .none: false
        }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
    }

    func observeTransactionUpdates(
        _ onVerified: @escaping @MainActor (StoreTransaction) async -> Void
    ) {
        stopObservingTransactionUpdates()
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self, !Task.isCancelled else { return }
                if let transaction = try? self.checkVerified(result) {
                    await self.deliverThenFinish(transaction, onVerified: onVerified)
                }
            }
        }
    }

    func stopObservingTransactionUpdates() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    isolated deinit {
        stopObservingTransactionUpdates()
    }

    /// Application processing runs to completion before StoreKit is told the
    /// transaction can be finished. Always finish after a verified delivery so
    /// StoreKit does not redeliver in a loop.
    private func deliverThenFinish(
        _ transaction: Transaction,
        onVerified: @MainActor (StoreTransaction) async -> Void
    ) async {
        await onVerified(storeTransaction(from: transaction))
        await transaction.finish()
    }

    /// Returns verified StoreKit payloads; throws (typically `PurchaseError.unverified`) otherwise.
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }

    /// Preserve the verified reason: renewals have new transaction IDs too, so an
    /// ID alone cannot identify the customer purchase that should end simulation.
    private func storeTransaction(from transaction: Transaction) -> StoreTransaction {
        StoreTransaction(
            id: transaction.id, productID: transaction.productID,
            isCustomerPurchase: transaction.reason == .purchase
        )
    }

    private static func storeProduct(from product: Product) -> StoreProduct? {
        guard let id = StoreProductID(rawValue: product.id) else { return nil }
        return StoreProduct(
            productID: product.id,
            displayName: product.displayName,
            description: product.description,
            displayPrice: product.displayPrice,
            kind: id.kind
        )
    }
}
