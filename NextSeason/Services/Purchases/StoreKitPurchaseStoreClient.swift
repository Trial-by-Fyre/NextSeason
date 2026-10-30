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
    private let delivery = StoreTransactionDelivery()
    private var hasXcodePlusTransactions = false

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
        confirmation: PurchaseConfirmation?,
        onVerified: @escaping @MainActor (StoreTransaction) async -> Void
    ) async throws -> PurchaseOutcome {
        guard let product = productsByID[productID] else {
            throw PurchaseError.productUnavailable
        }

        let result: Product.PurchaseResult
        if let confirmation {
            result = try await confirmation.purchase(product)
        } else {
            // Every purchase button supplies its view's action; this fallback lets
            // StoreKit choose the scene and is logged so a missed caller is visible.
            AppDiagnosticsLogger.breadcrumb("purchase_without_confirmation_context")
            result = try await product.purchase()
        }
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            AppDiagnosticsLogger.breadcrumb(
                Self.purchaseSuccessDiagnostics(transaction, requestedProductID: productID))
            if transaction.environment == .xcode, Self.isPlus(transaction.productID) {
                hasXcodePlusTransactions = true
                return try await delivery.completePurchase(
                    .init(
                        transaction: storeTransaction(from: transaction),
                        validate: { await Self.subscriptionCheck(for: transaction) },
                        finish: { await Self.finishXcodeTransaction(transaction) }),
                    onVerified: onVerified)
            }
            _ = await deliverThenFinish(transaction, onVerified: onVerified)
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
    /// verification reports `.unverified` rather than `.inactive`. Local Xcode
    /// transactions additionally require a resolved subscription state, because
    /// its entitlement sequence can include an unapproved Ask to Buy purchase.
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
                if verified.environment == .xcode, Self.isPlus(verified.productID) {
                    hasXcodePlusTransactions = true
                }
                #if DEBUG
                    if Self.pendingDiagnosticsEnabled, Self.isPlus(verified.productID) {
                        AppDiagnosticsLogger.breadcrumb(
                            "storekit_entitlement " + Self.transactionDiagnostics(verified))
                    }
                #endif
            case .unverified(let unverified, _):
                if Self.isPlus(unverified.productID) { sawUnverifiedPlus = true }
                continue
            }
            guard transaction.revocationDate == nil, Self.isPlus(transaction.productID) else {
                continue
            }
            switch await Self.subscriptionCheck(for: transaction) {
            case .unverified:
                sawUnverifiedPlus = true
                continue
            case .inactive:
                continue
            case .active:
                break
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

    /// Describes the transaction behind a `.success` result. StoreKit has reported
    /// success without showing its sheet (TestFlight sandbox, 2026-10-23); these
    /// fields show which earlier transaction it returned.
    private static func purchaseSuccessDiagnostics(
        _ transaction: Transaction, requestedProductID: String
    ) -> String {
        "storekit_purchase_success requested=\(requestedProductID) "
            + transactionDiagnostics(transaction)
    }

    private static func transactionDiagnostics(_ transaction: Transaction) -> String {
        func date(_ value: Date?) -> String { value?.formatted(.iso8601) ?? "nil" }
        return "product=\(transaction.productID) id=\(transaction.id) "
            + "originalID=\(transaction.originalID) reason=\(transaction.reason.rawValue) "
            + "purchased=\(date(transaction.purchaseDate)) signed=\(date(transaction.signedDate)) "
            + "expires=\(date(transaction.expirationDate)) revoked=\(date(transaction.revocationDate)) "
            + "upgraded=\(transaction.isUpgraded) env=\(transaction.environment.rawValue) "
            + "ownership=\(transaction.ownershipType.rawValue)"
    }

    #if DEBUG
        private static var pendingDiagnosticsEnabled: Bool {
            ProcessInfo.processInfo.arguments.contains("-StoreKitPendingDiagnostics")
        }
    #endif

    private static func subscriptionCheck(for transaction: Transaction) async
        -> PlusEntitlementCheck
    {
        guard isPlus(transaction.productID) else { return .active }
        return await XcodeSubscriptionValidation.check(
            isXcode: transaction.environment == .xcode,
            transactionID: transaction.id, originalID: transaction.originalID,
            purchaseDate: transaction.purchaseDate
        ) {
            guard let groupID = transaction.subscriptionGroupID else { return [] }
            do {
                let statuses = try await Product.SubscriptionInfo.status(for: groupID)
                #if DEBUG
                    if pendingDiagnosticsEnabled {
                        AppDiagnosticsLogger.breadcrumb(
                            "storekit_status queriedID=\(transaction.id) count=\(statuses.count)")
                        for status in statuses {
                            switch status.transaction {
                            case .verified(let value):
                                AppDiagnosticsLogger.breadcrumb(
                                    "storekit_status queriedID=\(transaction.id) state=\(status.state.rawValue) verified=true "
                                        + transactionDiagnostics(value))
                            case .unverified(let value, _):
                                AppDiagnosticsLogger.breadcrumb(
                                    "storekit_status queriedID=\(transaction.id) state=\(status.state.rawValue) verified=false id=\(value.id)"
                                )
                            }
                        }
                    }
                #endif
                return statuses.compactMap { status in
                    let value = status.transaction.unsafePayloadValue
                    guard isPlus(value.productID) else { return nil }
                    let isVerified: Bool
                    if case .verified = status.transaction,
                        case .verified(let renewal) = status.renewalInfo,
                        renewal.originalTransactionID == value.originalID
                    {
                        isVerified = true
                    } else {
                        isVerified = false
                    }
                    return XcodeSubscriptionValidation.Status(
                        id: value.id, originalID: value.originalID,
                        purchaseDate: value.purchaseDate,
                        state: status.state, isVerified: isVerified)
                }
            } catch {
                let error = error as NSError
                AppDiagnosticsLogger.breadcrumb(
                    "storekit_status_error queriedID=\(transaction.id) domain=\(error.domain) code=\(error.code)"
                )
                throw error
            }
        }
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
        delivery.observe(onVerified)
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self, !Task.isCancelled else { return }
                if let transaction = try? self.checkVerified(result) {
                    #if DEBUG
                        if Self.pendingDiagnosticsEnabled, Self.isPlus(transaction.productID) {
                            AppDiagnosticsLogger.breadcrumb(
                                "storekit_update_before_finish "
                                    + Self.transactionDiagnostics(transaction))
                        }
                    #endif
                    _ = await self.deliverThenFinish(transaction, onVerified: onVerified)
                }
            }
        }
    }

    func stopObservingTransactionUpdates() {
        updatesTask?.cancel()
        updatesTask = nil
        delivery.stop()
        hasXcodePlusTransactions = false
    }

    func retryDeferredTransactions() async {
        // Keep the extra recovery read local to demonstrated Xcode transactions.
        // Production/sandbox still use the original updates/entitlement paths.
        guard hasXcodePlusTransactions else { return }
        await delivery.recoverUnfinishedTransactions {
            var candidates: [StoreTransactionDelivery.Candidate] = []
            var resultCount = 0
            for await result in Transaction.unfinished {
                resultCount += 1
                guard !Task.isCancelled else { return [] }
                guard case .verified(let transaction) = result,
                    transaction.environment == .xcode, Self.isPlus(transaction.productID)
                else { continue }
                #if DEBUG
                    if Self.pendingDiagnosticsEnabled {
                        AppDiagnosticsLogger.breadcrumb(
                            "storekit_unfinished_recovery "
                                + Self.transactionDiagnostics(transaction))
                    }
                #endif
                candidates.append(
                    .init(
                        transaction: storeTransaction(from: transaction),
                        validate: { await Self.subscriptionCheck(for: transaction) },
                        finish: { await Self.finishXcodeTransaction(transaction) }))
            }
            #if DEBUG
                if Self.pendingDiagnosticsEnabled {
                    AppDiagnosticsLogger.breadcrumb(
                        "storekit_unfinished_scan total=\(resultCount) candidates=\(candidates.count)"
                    )
                }
            #endif
            return candidates
        }
    }

    isolated deinit {
        stopObservingTransactionUpdates()
    }

    /// Application processing runs to completion before StoreKit is told the
    /// transaction can be finished. Unknown local Xcode subscription states stay
    /// unfinished and unprocessed, including through relaunch, until resolved.
    private func deliverThenFinish(
        _ transaction: Transaction,
        onVerified: @MainActor (StoreTransaction) async -> Void
    ) async -> Bool {
        let snapshot = storeTransaction(from: transaction)
        guard transaction.environment == .xcode, Self.isPlus(transaction.productID) else {
            await onVerified(snapshot)
            await transaction.finish()
            return true
        }
        hasXcodePlusTransactions = true
        return await delivery.deliver(
            snapshot, validate: { await Self.subscriptionCheck(for: transaction) },
            onVerified: onVerified, finish: { await Self.finishXcodeTransaction(transaction) })
    }

    private static func finishXcodeTransaction(_ transaction: Transaction) async {
        #if DEBUG
            if pendingDiagnosticsEnabled {
                AppDiagnosticsLogger.breadcrumb("storekit_finish_requested id=\(transaction.id)")
            }
        #endif
        await transaction.finish()
        #if DEBUG
            if pendingDiagnosticsEnabled {
                AppDiagnosticsLogger.breadcrumb("storekit_finish_returned id=\(transaction.id)")
                var stillUnfinished = false
                for await result in Transaction.unfinished {
                    if result.unsafePayloadValue.id == transaction.id {
                        stillUnfinished = true
                        break
                    }
                }
                AppDiagnosticsLogger.breadcrumb(
                    "storekit_finish_snapshot id=\(transaction.id) unfinished=\(stillUnfinished)")
            }
        #endif
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
