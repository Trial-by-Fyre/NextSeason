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

    /// Scans current entitlements for an active Plus subscription. Ignores revoked transactions and consumable tips.
    func hasActivePlusEntitlement() async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            guard transaction.revocationDate == nil else { continue }
            switch StoreProductID(rawValue: transaction.productID) {
            case .plusAnnual, .plusMonthly:
                return true
            case .tipTrailer, .tipPilot, .tipHitShow, .none:
                continue
            }
        }
        return false
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

    private func storeTransaction(from transaction: Transaction) -> StoreTransaction {
        StoreTransaction(id: transaction.id, productID: transaction.productID)
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
