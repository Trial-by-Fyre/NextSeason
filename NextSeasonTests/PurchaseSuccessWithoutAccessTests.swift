//
//  PurchaseSuccessWithoutAccessTests.swift
//  NextSeasonTests
//

import Foundation
import Testing

@testable import NextSeason

/// StoreKit reporting `.success` without a purchase sheet or an active entitlement
/// (TestFlight sandbox, 2026-10-23). The paywall closes only on `.success`, so these
/// outcomes must not be reported as success.
@MainActor
struct PurchaseSuccessWithoutAccessTests {
    private func makeService(
        store: StubPurchaseStoreClient,
        complimentary: Bool = false
    ) -> PurchaseService {
        let defaults = UserDefaults(
            suiteName: "PurchaseSuccessWithoutAccessTests.\(UUID().uuidString)")!
        defaults.set(complimentary, forKey: PlusEntitlementStore.complimentaryKey)
        return PurchaseService(
            store: store,
            entitlementStore: PlusEntitlementStore(
                userDefaults: defaults, persistence: MemoryComplimentaryPlusPersistence()),
            initialStoreEntitlement: .resolved(isEntitled: false),
            simulationAvailability: { true }
        )
    }

    @Test(
        "A Plus success that leaves Plus inactive is reported as a failure",
        arguments: [StoreProductID.plusMonthly, .plusAnnual])
    func staleSuccessIsFailure(_ id: StoreProductID) async {
        let store = StubPurchaseStoreClient()
        store.reportsStaleSuccess = true
        let purchases = makeService(store: store)
        await purchases.start()

        let outcome = await purchases.purchase(StoreProduct(id))

        guard case .failed = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
        #expect(purchases.lastErrorMessage != nil)
        #expect(purchases.isUnlimitedWatchlist == false)
    }

    @Test("Retrying after a stale success completes a real purchase")
    func retryAfterStaleSuccessSucceeds() async {
        let store = StubPurchaseStoreClient()
        store.reportsStaleSuccess = true
        let purchases = makeService(store: store)
        await purchases.start()
        _ = await purchases.purchase(StoreProduct(.plusMonthly))

        store.reportsStaleSuccess = false
        let outcome = await purchases.purchase(StoreProduct(.plusMonthly))

        #expect(outcome == .success)
        #expect(purchases.isUnlimitedWatchlist)
        #expect(purchases.lastErrorMessage == nil)
    }

    /// The reported configuration: stored complimentary Plus hidden by the override.
    @Test("A stale success while ignoring complimentary Plus is a failure")
    func staleSuccessWhileIgnoringComplimentaryPlus() async {
        let store = StubPurchaseStoreClient()
        store.reportsStaleSuccess = true
        let purchases = makeService(store: store, complimentary: true)
        await purchases.start()
        purchases.setIgnoreComplimentaryPlus(true)
        #expect(purchases.isUnlimitedWatchlist == false)

        let outcome = await purchases.purchase(StoreProduct(.plusMonthly))

        #expect(outcome != .success)
        #expect(purchases.isUnlimitedWatchlist == false)
        #expect(purchases.hasStoredComplimentaryPlus)
    }
}
