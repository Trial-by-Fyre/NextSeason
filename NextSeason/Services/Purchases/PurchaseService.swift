//
//  PurchaseService.swift
//  NextSeason
//

import Foundation

/// StoreKit Plus entitlement, distinct from permanent complimentary access.
///
/// `loading` means `Transaction.currentEntitlements` has not been read yet.
/// It is not the same as free: callers that need a real answer wait until
/// the state is `resolved`.
nonisolated enum StoreEntitlementState: Equatable, Sendable {
    case loading
    case resolved(isEntitled: Bool)
}

/// Product-catalog presentation for Plus and tip UIs.
///
/// Distinct from `isPurchasing`, which is a transaction-in-flight concern.
nonisolated enum StoreCatalogAvailability: Equatable, Sendable {
    case loading
    case available
    case unavailable
}

/// Observable purchasing and Plus entitlement state for the SwiftUI environment.
///
/// Unlimited watchlist access comes from an active monthly or annual subscription,
/// or permanent complimentary Plus. Tips never grant Plus.
@Observable
@MainActor
final class PurchaseService {
    /// StoreKit Plus entitlement; `.loading` until the first read completes.
    private(set) var storeEntitlement: StoreEntitlementState
    /// Annual subscription product from the last successful `loadProducts()`.
    private(set) var annualProduct: StoreProduct?
    /// Monthly subscription product from the last successful `loadProducts()`.
    private(set) var monthlyProduct: StoreProduct?
    /// Consumable tip products, sorted trailer → pilot → hit show.
    private(set) var tipProducts: [StoreProduct] = []
    /// True while `Product.products(for:)` is in flight.
    private(set) var isLoadingProducts = false
    /// True after the first product load attempt finishes (success or failure).
    /// Distinguishes "not yet loaded" from "loaded but empty."
    private(set) var hasCompletedProductLoad = false
    /// True while a purchase or restore call is in progress.
    private(set) var isPurchasing = false
    /// User-facing purchase or restore error for alerts.
    private(set) var lastErrorMessage: String?
    /// Shown once per verified tip transaction (deduped by transaction ID).
    private(set) var thankYouMessage: String?

    private let store: any PurchaseStoreClient
    private let entitlementStore: PlusEntitlementStore
    private let complimentaryGrantEligibility: @MainActor () async -> Bool
    private var didStartObserving = false
    private var entitlementWaiters: [CheckedContinuation<Void, Never>] = []
    /// Prevents duplicate thank-you toasts when StoreKit redelivers the same tip.
    private var processedTransactionIDs: Set<UInt64> = []

    /// True when StoreKit has reported an active Plus subscription.
    var isStoreEntitled: Bool {
        if case .resolved(let isEntitled) = storeEntitlement {
            return isEntitled
        }
        return false
    }

    /// True once the initial StoreKit entitlement read has finished.
    /// UI that gates on free vs Plus should wait for this (or use
    /// `waitForInitialEntitlementResolution()` for adds).
    var hasResolvedStoreEntitlement: Bool {
        if case .resolved = storeEntitlement { return true }
        return false
    }

    /// True when StoreKit Plus is active or the user has complimentary Plus.
    var isUnlimitedWatchlist: Bool {
        isStoreEntitled || entitlementStore.isComplimentary
    }

    /// Permanent complimentary access: unlimited watchlist without an active StoreKit purchase.
    var isComplimentary: Bool {
        entitlementStore.isComplimentary
    }

    /// Plus annual/monthly catalog for `PlusStoreView`.
    ///
    /// Loading wins while a fetch is in flight (or has never completed) so the
    /// paywall can overlay a spinner without treating a reload as unavailable.
    var plusCatalogAvailability: StoreCatalogAvailability {
        if isLoadingProducts || !hasCompletedProductLoad {
            return .loading
        }
        if annualProduct != nil || monthlyProduct != nil {
            return .available
        }
        return .unavailable
    }

    /// Tip catalog for `TipJarSection`.
    ///
    /// Loaded tips stay `.available` even during a later reload, matching the
    /// section's product-first rendering.
    var tipCatalogAvailability: StoreCatalogAvailability {
        if !tipProducts.isEmpty {
            return .available
        }
        if isLoadingProducts || !hasCompletedProductLoad {
            return .loading
        }
        return .unavailable
    }

    init(
        store: any PurchaseStoreClient,
        entitlementStore: PlusEntitlementStore = PlusEntitlementStore(),
        initialStoreEntitlement: StoreEntitlementState = .loading,
        complimentaryGrantEligibility: @escaping @MainActor () async -> Bool = { false }
    ) {
        self.complimentaryGrantEligibility = complimentaryGrantEligibility
        self.store = store
        self.entitlementStore = entitlementStore
        self.storeEntitlement = initialStoreEntitlement
    }

    isolated deinit {
        store.stopObservingTransactionUpdates()
    }

    /// Production StoreKit-backed service.
    convenience init() {
        self.init(
            store: StoreKitPurchaseStoreClient(),
            complimentaryGrantEligibility: { await TemporaryBetaPlusGrant.isEligible() }
        )
    }

    /// Loads products, resolves complimentary access, and starts listening
    /// for StoreKit transaction updates.
    ///
    /// `Transaction.updates` is observed before the first entitlement read so
    /// unfinished or delayed transactions are not missed during startup.
    func start(watchlistCount: Int) async {
        startObservingTransactionsIfNeeded()
        await refreshComplimentaryEntitlement()
        await refreshEntitlements()
        await loadProducts()
    }

    private func refreshComplimentaryEntitlement() async {
        entitlementStore.reconcile()
        if !entitlementStore.isComplimentary, await complimentaryGrantEligibility() {
            entitlementStore.grantComplimentaryPlus()
        }
        if entitlementStore.isComplimentary { resumeEntitlementWaiters() }
    }

    /// Re-reads StoreKit entitlements when the scene becomes active.
    ///
    /// Subscription expiration is not guaranteed to arrive through
    /// `Transaction.updates`. Skips while the initial `start()` refresh is
    /// still in flight so launch does not issue two entitlement queries
    /// back-to-back.
    func handleSceneBecameActive() async {
        await refreshComplimentaryEntitlement()
        guard hasResolvedStoreEntitlement else { return }
        await refreshEntitlements()
    }

    /// Waits until the first StoreKit entitlement read has completed.
    ///
    /// Watchlist adds use this so a Plus customer is not treated as free
    /// during cold launch. Pre-resolved stubs (tests, previews, UI tests)
    /// return immediately.
    func waitForInitialEntitlementResolution() async {
        if case .resolved = storeEntitlement { return }
        if entitlementStore.isComplimentary { return }
        await withCheckedContinuation { continuation in
            if case .resolved = storeEntitlement {
                continuation.resume()
            } else if entitlementStore.isComplimentary {
                continuation.resume()
            } else {
                entitlementWaiters.append(continuation)
            }
        }
    }

    /// Whether another show may be added after entitlement resolution.
    /// Complimentary and paid Plus users are always allowed; free users hit the cap.
    func canAddToWatchlist(currentCount: Int) async -> Bool {
        await waitForInitialEntitlementResolution()
        return WatchlistLimitPolicy.canAddShow(
            currentCount: currentCount,
            isUnlimited: isUnlimitedWatchlist
        )
    }

    /// Loads Plus and tip products from StoreKit and partitions them by kind.
    func loadProducts() async {
        isLoadingProducts = true
        lastErrorMessage = nil
        defer { isLoadingProducts = false }

        do {
            let products = try await store.loadProducts(ids: StoreProductID.allIDs)
            annualProduct = products.first { $0.kind == .plusAnnual }
            monthlyProduct = products.first { $0.kind == .plusMonthly }
            tipProducts =
                products
                .filter { $0.kind == .tip }
                .sorted { lhs, rhs in
                    tipSortIndex(lhs.productID) < tipSortIndex(rhs.productID)
                }
            hasCompletedProductLoad = true
            if annualProduct == nil && monthlyProduct == nil {
                AppDiagnosticsLogger.breadcrumb("purchase_products_empty")
            }
        } catch is CancellationError {
            return
        } catch {
            hasCompletedProductLoad = true
            lastErrorMessage = String(
                localized: "Couldn't load purchase options. Please try again."
            )
            AppDiagnosticsLogger.breadcrumb("purchase_products_load_failed")
        }
    }

    /// Purchases a product; verified transactions refresh entitlements or
    /// set `thankYouMessage` for tips before the store client finishes them.
    func purchase(_ product: StoreProduct) async -> PurchaseOutcome {
        guard !isPurchasing else { return .pending }
        isPurchasing = true
        lastErrorMessage = nil
        thankYouMessage = nil
        defer { isPurchasing = false }

        do {
            let outcome = try await store.purchase(productID: product.productID) {
                [weak self] transaction in
                await self?.handleVerifiedTransaction(transaction)
            }
            switch outcome {
            case .success, .cancelled, .pending:
                break
            case .failed(let message):
                lastErrorMessage = message
            }
            return outcome
        } catch is CancellationError {
            return .cancelled
        } catch {
            let message = error.localizedDescription
            lastErrorMessage = message
            return .failed(message)
        }
    }

    /// Syncs with App Store (restore) then re-reads Plus entitlements.
    func restorePurchases() async -> PurchaseOutcome {
        guard !isPurchasing else { return .pending }
        isPurchasing = true
        lastErrorMessage = nil
        defer { isPurchasing = false }

        do {
            try await store.restorePurchases()
            await refreshEntitlements()
            return .success
        } catch is CancellationError {
            return .cancelled
        } catch {
            let message = String(
                localized: "Couldn't restore purchases. Please try again."
            )
            lastErrorMessage = message
            return .failed(message)
        }
    }

    /// Re-reads `Transaction.currentEntitlements` and updates `storeEntitlement`.
    func refreshEntitlements() async {
        let entitled = await store.hasActivePlusEntitlement()
        if Task.isCancelled { return }
        storeEntitlement = .resolved(isEntitled: entitled)
        resumeEntitlementWaiters()
    }

    /// Clears user-visible purchase feedback (errors and tip thank-you).
    func clearMessages() {
        lastErrorMessage = nil
        thankYouMessage = nil
    }

    /// Starts the StoreKit transaction observer once for this service instance.
    /// `deinit` stops it; the live client also cancels its task on deallocation.
    private func startObservingTransactionsIfNeeded() {
        guard !didStartObserving else { return }
        didStartObserving = true
        store.observeTransactionUpdates { [weak self] transaction in
            await self?.handleVerifiedTransaction(transaction)
        }
    }

    /// Incorporates a verified StoreKit transaction, then the client finishes it.
    private func handleVerifiedTransaction(_ transaction: StoreTransaction) async {
        let isNew = processedTransactionIDs.insert(transaction.id).inserted
        switch transaction.kind {
        case .plusAnnual, .plusMonthly:
            await refreshEntitlements()
        case .tip:
            if isNew {
                thankYouMessage = String(localized: "Thank you for supporting NextSeason.")
            }
        case nil:
            break
        }
    }

    private func resumeEntitlementWaiters() {
        let waiters = entitlementWaiters
        entitlementWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    /// Stable tip ordering independent of StoreKit's product array order.
    private func tipSortIndex(_ productID: String) -> Int {
        switch StoreProductID(rawValue: productID) {
        case .tipTrailer: 0
        case .tipPilot: 1
        case .tipHitShow: 2
        default: 99
        }
    }
}

extension PurchaseService {
    /// Tests, previews, and UI tests. Does not contact StoreKit.
    static func stub(
        isStoreEntitled: Bool = false,
        userDefaults: UserDefaults? = nil,
        products: [StoreProduct] = StoreProductID.allCases.map { StoreProduct($0) },
        purchaseOutcome: PurchaseOutcome = .success
    ) -> PurchaseService {
        let defaults: UserDefaults
        if let userDefaults {
            defaults = userDefaults
        } else {
            let suiteName = "PurchaseService.stub.\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: suiteName) ?? .standard
            defaults.removePersistentDomain(forName: suiteName)
        }
        return PurchaseService(
            store: StubPurchaseStoreClient(
                products: products,
                isStoreEntitled: isStoreEntitled,
                purchaseOutcome: purchaseOutcome
            ),
            entitlementStore: PlusEntitlementStore(
                userDefaults: defaults, persistence: PreviewComplimentaryPlusPersistence()),
            initialStoreEntitlement: .resolved(isEntitled: isStoreEntitled)
        )
    }

    /// Preview catalog with fallback prices; not entitled.
    static var preview: PurchaseService {
        stub()
    }
}

@MainActor
private struct PreviewComplimentaryPlusPersistence: ComplimentaryPlusPersistence {
    func hasEntitlement() -> Bool { false }
    func saveEntitlement() -> Bool { true }
}
