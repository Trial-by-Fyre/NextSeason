//
//  FreeTierSimulationTests.swift
//  NextSeasonTests
//

import Foundation
import StoreKit
import Testing

@testable import NextSeason

@MainActor
struct FreeTierSimulationTests {
    private func makeService(
        store: StubPurchaseStoreClient = StubPurchaseStoreClient(),
        complimentary: Bool = false,
        allowed: Bool = true
    ) -> PurchaseService {
        let defaults = UserDefaults(suiteName: "FreeTierSimulationTests.\(UUID().uuidString)")!
        defaults.set(complimentary, forKey: PlusEntitlementStore.complimentaryKey)
        return PurchaseService(
            store: store,
            entitlementStore: PlusEntitlementStore(
                userDefaults: defaults, persistence: MemoryComplimentaryPlusPersistence()),
            initialStoreEntitlement: .resolved(isEntitled: store.isStoreEntitled),
            simulationAvailability: { allowed }
        )
    }

    @Test(arguments: [false, true], [false, true])
    func simulationPreservesActualAccess(paid: Bool, complimentary: Bool) async {
        let purchases = makeService(
            store: StubPurchaseStoreClient(isStoreEntitled: paid), complimentary: complimentary)
        purchases.setFreeTierSimulation(true)
        #expect(purchases.isSimulatingFreeTier)
        #expect(purchases.isUnlimitedWatchlist == false)
        #expect(await purchases.canAddToWatchlist(currentCount: 2))
        #expect(await purchases.canAddToWatchlist(currentCount: 3) == false)
        #expect(await purchases.canAddToWatchlist(currentCount: 12) == false)
        #expect(purchases.isStoreEntitled == paid)
        #expect(purchases.isComplimentary == complimentary)
        purchases.setFreeTierSimulation(false)
        #expect(purchases.isUnlimitedWatchlist == (paid || complimentary))
    }

    @Test func releaseGateRequiresVerifiedSandboxApp() {
        #expect(
            BetaBuildAvailability.releaseAllowsFreeTierSimulation(
                environment: .sandbox, isVerified: true))
        for environment in [AppStore.Environment.production, .xcode, nil] {
            #expect(
                BetaBuildAvailability.releaseAllowsFreeTierSimulation(
                    environment: environment, isVerified: true) == false)
        }
        #expect(
            BetaBuildAvailability.releaseAllowsFreeTierSimulation(
                environment: .sandbox, isVerified: false) == false)
    }

    @Test func unavailableOverrideCannotChangeAccess() {
        let purchases = makeService(complimentary: true, allowed: false)
        purchases.setFreeTierSimulation(true)
        #expect(purchases.isSimulatingFreeTier == false)
        #expect(purchases.isUnlimitedWatchlist)
    }

    @Test(arguments: [StoreProductID.plusMonthly, .plusAnnual])
    func verifiedSuccessfulPurchaseEndsSimulation(_ id: StoreProductID) async {
        let store = StubPurchaseStoreClient()
        let purchases = makeService(store: store, complimentary: true)
        await purchases.start(watchlistCount: 12)
        purchases.setFreeTierSimulation(true)
        #expect(await purchases.purchase(StoreProduct(id)) == .success)
        #expect(purchases.isSimulatingFreeTier == false)
        #expect(purchases.isUnlimitedWatchlist)
        #expect(purchases.isComplimentary)
    }

    @Test(arguments: [PurchaseOutcome.cancelled, .pending, .failed("Unverified")])
    func unsuccessfulPurchaseKeepsSimulation(_ outcome: PurchaseOutcome) async {
        let purchases = makeService(store: StubPurchaseStoreClient(purchaseOutcome: outcome))
        purchases.setFreeTierSimulation(true)
        #expect(await purchases.purchase(StoreProduct(.plusAnnual)) == outcome)
        #expect(purchases.isSimulatingFreeTier)
    }

    @Test func tipsRefreshAndRestoreKeepSimulation() async {
        let purchases = makeService(store: StubPurchaseStoreClient(isStoreEntitled: true))
        purchases.setFreeTierSimulation(true)
        await purchases.refreshEntitlements()
        #expect(await purchases.restorePurchases() == .success)
        #expect(await purchases.purchase(StoreProduct(.tipPilot)) == .success)
        #expect(purchases.isSimulatingFreeTier)
    }

    @Test(arguments: [StoreProductID.plusMonthly, .plusAnnual])
    func renewalsAndUnrequestedPurchasesKeepSimulation(_ id: StoreProductID) async {
        let store = StubPurchaseStoreClient(isStoreEntitled: true)
        let purchases = makeService(store: store)
        await purchases.start(watchlistCount: 3)
        purchases.setFreeTierSimulation(true)

        await store.emitVerifiedTransaction(
            StoreTransaction(id: 30, productID: id.rawValue, isCustomerPurchase: false))
        #expect(purchases.isSimulatingFreeTier)
        #expect(purchases.isStoreEntitled)
        await store.emitVerifiedTransaction(StoreTransaction(id: 31, productID: id.rawValue))
        #expect(purchases.isSimulatingFreeTier)
    }

    @Test func pendingPurchaseIgnoresRenewalAndDifferentProduct() async {
        let store = StubPurchaseStoreClient(isStoreEntitled: true, purchaseOutcome: .pending)
        let purchases = makeService(store: store)
        await purchases.start(watchlistCount: 3)
        purchases.setFreeTierSimulation(true)
        #expect(await purchases.purchase(StoreProduct(.plusMonthly)) == .pending)

        await store.emitVerifiedTransaction(
            StoreTransaction(
                id: 32, productID: StoreProductID.plusMonthly.rawValue, isCustomerPurchase: false))
        #expect(purchases.isSimulatingFreeTier)
        await store.emitVerifiedTransaction(
            StoreTransaction(
                id: 33, productID: StoreProductID.plusAnnual.rawValue))
        #expect(purchases.isSimulatingFreeTier)
        await store.emitVerifiedTransaction(
            StoreTransaction(
                id: 34, productID: StoreProductID.plusMonthly.rawValue))
        #expect(purchases.isSimulatingFreeTier == false)
    }

    @Test func togglingClearsPendingPurchaseTracking() async {
        let store = StubPurchaseStoreClient(purchaseOutcome: .pending)
        let purchases = makeService(store: store)
        await purchases.start(watchlistCount: 3)
        purchases.setFreeTierSimulation(true)
        #expect(await purchases.purchase(StoreProduct(.plusMonthly)) == .pending)
        purchases.setFreeTierSimulation(false)
        purchases.setFreeTierSimulation(true)
        store.isStoreEntitled = true
        await store.emitVerifiedTransaction(
            StoreTransaction(
                id: 35, productID: StoreProductID.plusMonthly.rawValue))
        #expect(purchases.isSimulatingFreeTier)
    }

    @Test func pendingCompletionCannotDisableRestartedSimulationAfterAwait() async {
        let store = StubPurchaseStoreClient(purchaseOutcome: .pending)
        let purchases = makeService(store: store)
        await purchases.start(watchlistCount: 3)
        purchases.setFreeTierSimulation(true)
        #expect(await purchases.purchase(StoreProduct(.plusMonthly)) == .pending)
        store.isStoreEntitled = true
        store.delayEntitlementResolution = true
        let completion = Task {
            await store.emitVerifiedTransaction(
                StoreTransaction(
                    id: 36, productID: StoreProductID.plusMonthly.rawValue))
        }
        for _ in 0..<200 {
            if store.entitlementWaiterCount > 0 { break }
            await Task.yield()
        }
        #expect(store.entitlementWaiterCount == 1)
        purchases.setFreeTierSimulation(false)
        purchases.setFreeTierSimulation(true)
        store.releaseEntitlementResolution()
        await completion.value
        #expect(purchases.isSimulatingFreeTier)
    }

    @Test func delayedVerifiedSubscriptionRequiresActiveEntitlement() async {
        let store = StubPurchaseStoreClient(purchaseOutcome: .pending)
        let purchases = makeService(store: store)
        await purchases.start(watchlistCount: 3)
        purchases.setFreeTierSimulation(true)
        #expect(await purchases.purchase(StoreProduct(.plusMonthly)) == .pending)
        await store.emitVerifiedTransaction(
            StoreTransaction(id: 40, productID: StoreProductID.plusMonthly.rawValue))
        #expect(purchases.isSimulatingFreeTier)
        store.isStoreEntitled = true
        await store.emitVerifiedTransaction(
            StoreTransaction(id: 41, productID: StoreProductID.plusMonthly.rawValue))
        #expect(purchases.isSimulatingFreeTier == false)
        #expect(purchases.isUnlimitedWatchlist)
        purchases.setFreeTierSimulation(true)
        await store.emitVerifiedTransaction(
            StoreTransaction(id: 41, productID: StoreProductID.plusMonthly.rawValue))
        #expect(purchases.isSimulatingFreeTier)
    }
}
