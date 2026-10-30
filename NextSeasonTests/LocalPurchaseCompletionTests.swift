import Foundation
import Testing

@testable import NextSeason

/// Exercises the same local completion bridge used after StoreKit's verified
/// success result, together with the real PurchaseService simulation handling.
@MainActor
struct LocalPurchaseCompletionTests {
    private let transaction = StoreTransaction(
        id: 6, productID: StoreProductID.plusMonthly.rawValue)

    private func service(_ store: LocalCompletionStore) throws -> PurchaseService {
        let defaults = try #require(
            UserDefaults(suiteName: "LocalPurchaseCompletion.\(UUID().uuidString)"))
        return PurchaseService(
            store: store,
            entitlementStore: PlusEntitlementStore(
                userDefaults: defaults, persistence: MemoryComplimentaryPlusPersistence()),
            simulationAvailability: { true })
    }

    @Test(
        "Deferred local success returns pending without an error, then approval ends simulation",
        .timeLimit(.minutes(1)))
    func deferredSuccessCompletesSimulation() async throws {
        let sleep = CompletionGate()
        let delivery = StoreTransactionDelivery(sleep: { _ in await sleep.wait() })
        let store = LocalCompletionStore(delivery: delivery)
        store.validation = { .unverified }
        let purchases = try service(store)
        await purchases.start()
        purchases.setFreeTierSimulation(true)
        #expect(await purchases.purchase(StoreProduct(.plusMonthly)) == .pending)
        #expect(purchases.lastErrorMessage == nil)
        #expect(purchases.isSimulatingFreeTier)
        #expect(store.finishCount == 0)
        await sleep.waitForStart()
        let retry = try #require(delivery.automaticRetryTask)
        store.base.isStoreEntitled = true
        store.validation = { .active }
        sleep.resume()
        await retry.value
        #expect(purchases.isStoreEntitled)
        #expect(!purchases.isSimulatingFreeTier)
        #expect(purchases.isUnlimitedWatchlist)
        #expect(store.finishCount == 1)
    }

    @Test(
        "A purchase joining the listener's delivery succeeds and ends simulation with one finish",
        .timeLimit(.minutes(1)))
    func listenerWinsPurchaseRace() async throws {
        let gate = CompletionGate()
        let store = LocalCompletionStore()
        store.validation = {
            await gate.wait()
            return .active
        }
        let purchases = try service(store)
        await purchases.start()
        purchases.setFreeTierSimulation(true)
        store.base.isStoreEntitled = true
        let listener = Task { await store.emit(transaction) }
        await gate.waitForStart()
        let purchase = Task { await purchases.purchase(StoreProduct(.plusMonthly)) }
        await waitForJoin(store.delivery)
        gate.resume()
        await listener.value
        #expect(await purchase.value == .success)
        #expect(purchases.lastErrorMessage == nil)
        #expect(!purchases.isSimulatingFreeTier)
        #expect(purchases.isUnlimitedWatchlist)
        #expect(store.finishCount == 1)
    }

    @Test("A customer update completing before pending returns still ends the requested simulation")
    func approvalBeforePendingHandoff() async throws {
        let store = LocalCompletionStore()
        store.rawOutcome = .pending
        let purchases = try service(store)
        await purchases.start()
        purchases.setFreeTierSimulation(true)
        store.beforeReturn = {
            store.base.isStoreEntitled = true
            await store.emit(transaction)
        }
        #expect(await purchases.purchase(StoreProduct(.plusMonthly)) == .pending)
        #expect(!purchases.isSimulatingFreeTier)
        #expect(purchases.isUnlimitedWatchlist)
        #expect(purchases.lastErrorMessage == nil)
    }

    @Test(
        "Pending registration during an update's suspended refresh is recognized",
        .timeLimit(.minutes(1)))
    func pendingRegistersDuringRefresh() async throws {
        let store = LocalCompletionStore()
        store.rawOutcome = .pending
        let purchases = try service(store)
        await purchases.start()
        purchases.setFreeTierSimulation(true)
        var update: Task<Void, Never>?
        store.beforeReturn = {
            store.base.isStoreEntitled = true
            store.base.delayEntitlementResolution = true
            update = Task { await store.emit(transaction) }
            await waitForEntitlementRead(store.base)
        }
        #expect(await purchases.purchase(StoreProduct(.plusMonthly)) == .pending)
        #expect(purchases.isSimulatingFreeTier)
        store.base.releaseEntitlementResolution()
        await update?.value
        #expect(!purchases.isSimulatingFreeTier)
        #expect(purchases.isUnlimitedWatchlist)
    }

    @Test(
        "Existing access plus an unrelated update cannot complete the requested purchase",
        arguments: [false, true])
    func unrelatedCompletionKeepsSimulation(renewal: Bool) async throws {
        let store = LocalCompletionStore()
        store.base.isStoreEntitled = true
        store.rawOutcome = .pending
        let purchases = try service(store)
        await purchases.start()
        purchases.setFreeTierSimulation(true)
        store.beforeReturn = {
            await store.emit(
                StoreTransaction(
                    id: 8,
                    productID: renewal
                        ? StoreProductID.plusMonthly.rawValue : StoreProductID.plusAnnual.rawValue,
                    isCustomerPurchase: !renewal))
        }
        #expect(await purchases.purchase(StoreProduct(.plusMonthly)) == .pending)
        #expect(purchases.isSimulatingFreeTier)
        #expect(purchases.isStoreEntitled)
    }

    @Test(
        "An update from an older simulation cannot mark a new run complete",
        .timeLimit(.minutes(1)))
    func replacedSimulationDuringHandoff() async throws {
        let store = LocalCompletionStore()
        store.rawOutcome = .pending
        let purchases = try service(store)
        await purchases.start()
        purchases.setFreeTierSimulation(true)
        store.beforeReturn = {
            store.base.isStoreEntitled = true
            store.base.delayEntitlementResolution = true
            let update = Task { await store.emit(transaction) }
            await waitForEntitlementRead(store.base)
            purchases.setFreeTierSimulation(false)
            purchases.setFreeTierSimulation(true)
            store.base.releaseEntitlementResolution()
            await update.value
        }
        #expect(await purchases.purchase(StoreProduct(.plusMonthly)) == .pending)
        #expect(purchases.isSimulatingFreeTier)
    }

    @Test(
        "Cancellation after validation retains an approved candidate for independent recovery",
        .timeLimit(.minutes(1)))
    func canceledOwnerStillRecovers() async throws {
        let validation = CompletionGate()
        let sleep = CompletionGate()
        let delivery = StoreTransactionDelivery(sleep: { _ in await sleep.wait() })
        var validations = 0
        var callerCallbacks = 0
        var observerCallbacks = 0
        var finishes = 0
        delivery.observe { _ in observerCallbacks += 1 }
        let task = Task {
            try await delivery.completePurchase(
                .init(
                    transaction: transaction,
                    validate: {
                        validations += 1
                        if validations == 1 { await validation.wait() }
                        return .active
                    }, finish: { finishes += 1 }), onVerified: { _ in callerCallbacks += 1 })
        }
        await validation.waitForStart()
        task.cancel()
        validation.resume()
        switch await task.result {
        case .failure(let error): #expect(error is CancellationError)
        case .success: Issue.record("Canceled purchase reported success")
        }
        #expect(callerCallbacks == 0)
        #expect(finishes == 0)
        await sleep.waitForStart()
        let retry = try #require(delivery.automaticRetryTask)
        sleep.resume()
        await retry.value
        #expect(observerCallbacks == 1)
        #expect(finishes == 1)
    }

    @Test(
        "Canceling a joined purchase leaves the listener's flight running", .timeLimit(.minutes(1)))
    func canceledJoinerDoesNotCancelOwner() async throws {
        let delivery = StoreTransactionDelivery()
        let gate = CompletionGate()
        var callbacks = 0
        var finishes = 0
        let owner = Task {
            await delivery.deliver(
                transaction,
                validate: {
                    await gate.wait()
                    return .active
                },
                onVerified: { _ in callbacks += 1 }, finish: { finishes += 1 })
        }
        await gate.waitForStart()
        let joiner = Task {
            try await delivery.completePurchase(
                .init(transaction: transaction, validate: { .active }, finish: { finishes += 1 }),
                onVerified: { _ in Issue.record("Canceled joiner was acknowledged") })
        }
        await waitForJoin(delivery)
        joiner.cancel()
        switch await joiner.result {
        case .failure(let error): #expect(error is CancellationError)
        case .success: Issue.record("Canceled joiner reported success")
        }
        #expect(callbacks == 0)
        #expect(finishes == 0)
        #expect(delivery.waitingDeliveryCount == 0)
        gate.resume()
        #expect(await owner.value)
        #expect(callbacks == 1)
        #expect(finishes == 1)
    }

    @Test(
        "Stop releases joined purchases without stale cleanup consuming replacement flights",
        .timeLimit(.minutes(1)))
    func stopAndRestartJoinedFlight() async {
        let delivery = StoreTransactionDelivery()
        let gate = CompletionGate()
        var oldEffects = 0
        var newEffects = 0
        let owner = Task {
            await delivery.deliver(
                transaction,
                validate: {
                    await gate.wait()
                    return .active
                },
                onVerified: { _ in oldEffects += 1 }, finish: { oldEffects += 1 })
        }
        await gate.waitForStart()
        let joiner = Task {
            try await delivery.completePurchase(
                .init(transaction: transaction, validate: { .active }, finish: { oldEffects += 1 }),
                onVerified: { _ in oldEffects += 1 })
        }
        await waitForJoin(delivery)
        delivery.stop()
        switch await joiner.result {
        case .failure(let error): #expect(error is CancellationError)
        case .success: Issue.record("Stopped observation reported purchase success")
        }
        delivery.observe { _ in newEffects += 1 }
        await delivery.deliver(
            transaction, validate: { .active },
            onVerified: { _ in newEffects += 1 }, finish: { newEffects += 1 })
        gate.resume()
        #expect(await owner.value == false)
        #expect(oldEffects == 0)
        #expect(newEffects == 2)
    }

    private func waitForJoin(_ delivery: StoreTransactionDelivery) async {
        for _ in 0..<1_000 {
            if delivery.waitingDeliveryCount == 1 { return }
            await Task.yield()
        }
        Issue.record("No joined delivery")
    }

    private func waitForEntitlementRead(_ store: StubPurchaseStoreClient) async {
        for _ in 0..<1_000 {
            if store.entitlementWaiterCount > 0 { return }
            await Task.yield()
        }
        Issue.record("Entitlement refresh did not suspend")
    }
}

@MainActor
private final class LocalCompletionStore: PurchaseStoreClient {
    let base = StubPurchaseStoreClient()
    let delivery: StoreTransactionDelivery
    var validation: @MainActor () async -> PlusEntitlementCheck = { .active }
    var rawOutcome: PurchaseOutcome?
    var beforeReturn: (@MainActor () async -> Void)?
    private(set) var finishCount = 0

    init(delivery: StoreTransactionDelivery = StoreTransactionDelivery()) {
        self.delivery = delivery
    }

    func loadProducts(ids: [String]) async throws -> [StoreProduct] {
        try await base.loadProducts(ids: ids)
    }
    func plusEntitlementStatus() async -> PlusEntitlementStatus {
        await base.plusEntitlementStatus()
    }
    func restorePurchases() async throws { try await base.restorePurchases() }
    func retryDeferredTransactions() async { await delivery.retryDeferredTransactions() }

    func observeTransactionUpdates(
        _ onVerified: @escaping @MainActor (StoreTransaction) async -> Void
    ) {
        base.observeTransactionUpdates(onVerified)
        delivery.observe { [base] in await base.emitVerifiedTransaction($0) }
    }

    func stopObservingTransactionUpdates() {
        delivery.stop()
        base.stopObservingTransactionUpdates()
    }

    func purchase(
        productID: String, confirmation: PurchaseConfirmation?,
        onVerified: @escaping @MainActor (StoreTransaction) async -> Void
    ) async throws -> PurchaseOutcome {
        let result: PurchaseOutcome
        if let rawOutcome {
            result = rawOutcome
        } else {
            result = try await delivery.completePurchase(
                .init(
                    transaction: StoreTransaction(id: 6, productID: productID),
                    validate: { [weak self] in await self?.validation() ?? .unverified },
                    finish: { [weak self] in self?.finishCount += 1 }),
                onVerified: onVerified)
        }
        let action = beforeReturn
        beforeReturn = nil
        await action?()
        return result
    }

    func emit(_ transaction: StoreTransaction) async {
        await delivery.deliver(
            transaction, validate: { [weak self] in await self?.validation() ?? .unverified },
            onVerified: { [base] in await base.emitVerifiedTransaction($0) },
            finish: { [weak self] in self?.finishCount += 1 })
    }
}

@MainActor
private final class CompletionGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func resume() {
        guard let continuation else {
            Issue.record("No suspended operation")
            return
        }
        self.continuation = nil
        continuation.resume()
    }
    func waitForStart() async {
        for _ in 0..<1_000 {
            if continuation != nil { return }
            await Task.yield()
        }
        Issue.record("Operation did not suspend")
    }
}
