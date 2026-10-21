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
///
/// `unverified` means the first read found a Plus entitlement StoreKit could not
/// verify. Adds treat it as free (no unverified access), but it is not a
/// confirmed lapse, so saved shows are never paused because of it.
nonisolated enum StoreEntitlementState: Equatable, Sendable {
    case loading
    case resolved(isEntitled: Bool)
    case unverified
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

    /// Session-only override; actual StoreKit and complimentary state stay intact.
    private var freeTierSimulationRequested = false
    /// Identifies one simulation run so purchases suspended across `await` cannot
    /// disable a later run after the tester turns simulation off and back on.
    private var simulationSessionID: UUID?
    /// Only a pending Plus purchase started in this run may complete through updates.
    /// Cleared whenever simulation is toggled; never persisted across launches.
    private var pendingSimulationProductID: String?
    private let simulationAvailability: @MainActor () -> Bool

    /// Developer/TestFlight eligibility shared by the control and the access override.
    var canSimulateFreeTier: Bool { simulationAvailability() }

    /// Re-check eligibility when reading effective state, rather than relying only
    /// on the UI hiding the control or the initial request being allowed.
    var isSimulatingFreeTier: Bool {
        canSimulateFreeTier && freeTierSimulationRequested
    }

    /// Starts a fresh simulation run or restores actual access without changing
    /// saved shows, complimentary persistence, or StoreKit entitlement state.
    func setFreeTierSimulation(_ enabled: Bool) {
        freeTierSimulationRequested = enabled && canSimulateFreeTier
        simulationSessionID = freeTierSimulationRequested ? UUID() : nil
        pendingSimulationProductID = nil
        // Simulation already determines the access decision, so an add waiting for
        // the initial StoreKit read can proceed using the normal free-tier cap.
        if isSimulatingFreeTier { resumeEntitlementWaiters() }
    }

    private let store: any PurchaseStoreClient
    private let entitlementStore: PlusEntitlementStore
    private let complimentaryGrantEligibility: @MainActor () async -> Bool
    private var didStartObserving = false
    private var entitlementWaiters: [CheckedContinuation<Void, Never>] = []
    /// Incremented on every `refreshEntitlements()` request; only the read for the
    /// current value may commit to `storeEntitlement`. Exposed for ordering tests.
    private(set) var entitlementRefreshEpoch: UInt = 0
    /// `refreshEntitlements()` callers waiting for a read at or after their request
    /// to commit. Separate from `entitlementWaiters`, which complimentary access and
    /// simulation may resume before StoreKit has answered.
    private var entitlementCommitWaiters: [CheckedContinuation<Void, Never>] = []
    /// Prevents duplicate tip thank-you toasts and replayed subscription updates
    /// completing a simulation when StoreKit redelivers a transaction.
    private var processedTransactionIDs: Set<UInt64> = []
    /// Raw result of the last committed read. `.unverified` does not change a
    /// resolved `storeEntitlement`, so restore feedback needs the raw answer.
    private(set) var lastCommittedCheck: PlusEntitlementCheck?

    /// How long after an active subscription's expiration to re-read entitlements
    /// while the app stays open. The App Store renews slightly before expiration;
    /// the margin gives a renewal time to reach the device so a renewing
    /// subscriber is not paused (product owner decision, 2026-10-21).
    static let expirationRecheckMargin: Duration = .seconds(5 * 60)
    private let now: @MainActor () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    /// The single pending expiration re-check; replaced by every committed
    /// active/inactive read.
    private var expirationRecheckTask: Task<Void, Never>?

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
        storeEntitlement != .loading
    }

    /// Effective Unlimited access only when it is actually known; `nil` while
    /// StoreKit is loading or could not verify a Plus entitlement.
    ///
    /// Drives pausing and resuming saved shows (`WatchlistAccessReconciler`), so a
    /// failed or pending check never pauses anything. Simulation and complimentary
    /// access are definitive on their own, so they answer even while loading.
    var confirmedWatchlistAccess: Bool? {
        if isSimulatingFreeTier { return false }
        if entitlementStore.isComplimentary { return true }
        switch storeEntitlement {
        case .resolved(let isEntitled): return isEntitled
        case .loading, .unverified: return nil
        }
    }

    /// Effective access for watchlist limits and paywall presentation. Simulation
    /// masks both sources of Unlimited while their actual entitlement state stays intact.
    var isUnlimitedWatchlist: Bool {
        !isSimulatingFreeTier && (isStoreEntitled || entitlementStore.isComplimentary)
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
        complimentaryGrantEligibility: @escaping @MainActor () async -> Bool = { false },
        simulationAvailability: @escaping @MainActor () -> Bool = {
            BetaBuildAvailability.shared.allowsFreeTierSimulation
        },
        now: @escaping @MainActor () -> Date = { Date() },
        // `ContinuousClock` (the default) keeps counting while the device sleeps,
        // so a deadline passed during suspension fires on resume.
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        // Test injection is available only in developer builds. Release always uses
        // verified app provenance, regardless of caller-supplied availability.
        #if DEBUG
            self.simulationAvailability = simulationAvailability
        #else
            self.simulationAvailability = { BetaBuildAvailability.shared.allowsFreeTierSimulation }
        #endif
        self.complimentaryGrantEligibility = complimentaryGrantEligibility
        self.store = store
        self.entitlementStore = entitlementStore
        self.storeEntitlement = initialStoreEntitlement
        self.now = now
        self.sleep = sleep
    }

    isolated deinit {
        store.stopObservingTransactionUpdates()
        expirationRecheckTask?.cancel()
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
    func start() async {
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
    /// return immediately. Active simulation also returns immediately because its
    /// free-tier decision does not depend on StoreKit's answer.
    func waitForInitialEntitlementResolution() async {
        if isSimulatingFreeTier { return }
        if hasResolvedStoreEntitlement { return }
        if entitlementStore.isComplimentary { return }
        await withCheckedContinuation { continuation in
            if hasResolvedStoreEntitlement {
                continuation.resume()
            } else if entitlementStore.isComplimentary {
                continuation.resume()
            } else {
                entitlementWaiters.append(continuation)
            }
        }
    }

    /// Whether another show may be added after entitlement resolution.
    /// Effective Unlimited access bypasses the cap; free users and simulated free
    /// users use the same policy. This only gates additions, never existing shows.
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
    /// Simulation ends only after a successful verified Plus purchase, or later
    /// when a pending purchase completes through a matching transaction update.
    func purchase(_ product: StoreProduct) async -> PurchaseOutcome {
        guard !isPurchasing else { return .pending }
        isPurchasing = true
        lastErrorMessage = nil
        thankYouMessage = nil
        defer { isPurchasing = false }

        // Capture the run before StoreKit can suspend; a purchase started outside
        // this simulation (or in an earlier run) must not turn it off.
        let simulationSession = isSimulatingFreeTier ? simulationSessionID : nil
        var verifiedSubscriptionPurchase = false
        do {
            let outcome = try await store.purchase(productID: product.productID) {
                [weak self] transaction in
                if transaction.productID == product.productID,
                    transaction.isCustomerPurchase,
                    transaction.kind == .plusAnnual || transaction.kind == .plusMonthly
                {
                    verifiedSubscriptionPurchase = true
                }
                await self?.handleVerifiedTransaction(transaction)
            }
            switch outcome {
            case .success:
                // The callback refreshes actual access before finish(). Wait for the
                // purchase outcome too, so verification alone does not end simulation.
                if verifiedSubscriptionPurchase, isStoreEntitled, !Task.isCancelled,
                    let simulationSession, simulationSessionID == simulationSession
                {
                    setFreeTierSimulation(false)
                }
            case .pending:
                // Remember only the subscription the tester requested. Background
                // renewals and unrelated purchases still refresh access but cannot unlock.
                if product.kind == .plusAnnual || product.kind == .plusMonthly,
                    let simulationSession, simulationSessionID == simulationSession
                {
                    pendingSimulationProductID = product.productID
                }
            case .cancelled:
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

    /// Feedback for a successful Restore Purchases that found no actual Plus, read
    /// by the view that started the restore right after it returns `.success`.
    /// `nil` when StoreKit or complimentary Plus is active.
    var restoreNotice: String? {
        if isStoreEntitled || isComplimentary { return nil }
        if lastCommittedCheck == .unverified {
            return String(
                localized:
                    "NextSeason found a Plus purchase but couldn't verify it. Please try again later."
            )
        }
        return String(
            localized: "No active NextSeason Plus subscription was found for this Apple Account."
        )
    }

    /// True while a re-check is scheduled for an active subscription's expiration.
    var hasPendingExpirationRecheck: Bool { expirationRecheckTask != nil }

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
    ///
    /// Only a verified answer changes a confirmed state. A verification failure
    /// keeps the last confirmed answer (so it cannot revoke Plus or pause shows),
    /// and on first read becomes `.unverified`.
    ///
    /// Overlapping requests each start their own read, and only the newest
    /// requested read may commit, so a stale answer can never overwrite a newer
    /// one. Callers return once a read at or after their request commits, not when
    /// their own read finishes: purchase and restore callers then see current
    /// access before finishing transactions or ending simulation, and a stalled
    /// older read cannot block them. If the newest read stalls, its callers (and
    /// any older superseded callers) wait until a later refresh commits.
    func refreshEntitlements() async {
        entitlementRefreshEpoch &+= 1
        let generation = entitlementRefreshEpoch
        let store = store
        // Unstructured so cancelling a caller never abandons the commit (which
        // would strand `waitForInitialEntitlementResolution()` waiters).
        Task { [weak self] in
            let status = await store.plusEntitlementStatus()
            self?.applyEntitlementCheck(status, generation: generation)
        }
        // Parking is synchronous on the main actor after launching the read, so
        // the read cannot commit before this caller is registered.
        await withCheckedContinuation { continuation in
            entitlementCommitWaiters.append(continuation)
        }
    }

    /// Commits one StoreKit entitlement read when `generation` is still the newest
    /// request; superseded results are discarded.
    private func applyEntitlementCheck(_ status: PlusEntitlementStatus, generation: UInt) {
        guard generation == entitlementRefreshEpoch else { return }
        lastCommittedCheck = status.check
        switch status.check {
        case .active:
            storeEntitlement = .resolved(isEntitled: true)
        case .inactive:
            storeEntitlement = .resolved(isEntitled: false)
        case .unverified:
            if case .resolved = storeEntitlement { break }
            storeEntitlement = .unverified
        }
        scheduleExpirationRecheck(for: status)
        // State is updated before resuming anyone. The newest request is the
        // highest generation, so every parked caller is now satisfied.
        resumeEntitlementWaiters()
        let commitWaiters = entitlementCommitWaiters
        entitlementCommitWaiters.removeAll()
        for waiter in commitWaiters {
            waiter.resume()
        }
    }

    /// Re-reads entitlements shortly after the active subscription expires, so a
    /// lapse while the app stays open is applied without waiting for the next
    /// foreground return. Goes through `refreshEntitlements()`, so ordering,
    /// unverified handling, and reconciliation are unchanged.
    private func scheduleExpirationRecheck(for status: PlusEntitlementStatus) {
        // Unverified keeps the prior confirmed state, so its re-check still applies.
        guard status.check != .unverified else { return }
        expirationRecheckTask?.cancel()
        expirationRecheckTask = nil
        guard status.check == .active, let expiration = status.expirationDate else { return }
        let remaining = expiration.timeIntervalSince(now())
        // Active with a past date (billing grace period): StoreKit still entitles
        // the user, and re-checking now would loop. Foreground return re-reads.
        guard remaining > 0 else { return }
        let delay = Duration.seconds(remaining) + Self.expirationRecheckMargin
        let sleep = sleep
        expirationRecheckTask = Task { [weak self] in
            do { try await sleep(delay) } catch { return }
            guard !Task.isCancelled, let self else { return }
            // Cleared before the read, so the read's own commit can schedule the next
            // re-check (or leave none, e.g. after an unverified answer).
            self.expirationRecheckTask = nil
            AppDiagnosticsLogger.breadcrumb("storekit_expiration_recheck")
            await self.refreshEntitlements()
        }
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
            await self?.handleVerifiedTransaction(transaction, fromTransactionUpdate: true)
        }
    }

    /// Incorporates a verified StoreKit transaction, then the client finishes it.
    /// Direct purchase callbacks leave simulation completion to `purchase()`;
    /// observer updates may complete only a pending purchase from the current run.
    private func handleVerifiedTransaction(
        _ transaction: StoreTransaction, fromTransactionUpdate: Bool = false
    ) async {
        let isNew = processedTransactionIDs.insert(transaction.id).inserted
        switch transaction.kind {
        case .plusAnnual, .plusMonthly:
            let simulationSession = simulationSessionID
            let completesPendingSimulation =
                fromTransactionUpdate && isNew
                && transaction.isCustomerPurchase
                && pendingSimulationProductID == transaction.productID
            await refreshEntitlements()
            // Renewals never complete a test purchase, even for the pending product.
            // Re-check the session after awaiting so an old completion cannot disable
            // a simulation the tester restarted while StoreKit was resolving access.
            if completesPendingSimulation, isStoreEntitled, !Task.isCancelled,
                let simulationSession, simulationSessionID == simulationSession
            {
                setFreeTierSimulation(false)
            }
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
