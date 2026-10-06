import Foundation
import StoreKit
import Testing

@testable import NextSeason

@MainActor
final class MemoryComplimentaryPlusPersistence: ComplimentaryPlusPersistence {
    var entitled = false
    var unavailable = false
    var writes = 0
    func hasEntitlement() -> Bool { !unavailable && entitled }
    func saveEntitlement() -> Bool {
        writes += 1
        guard !unavailable else { return false }
        entitled = true
        return true
    }
}

@MainActor
struct PlusEntitlementStoreTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "ComplimentaryPlusTests.\(UUID().uuidString)")!
    }

    @Test("Legacy entitlement migrates even after old evaluation", arguments: [false, true])
    func migration(evaluated: Bool) {
        let defaults = defaults()
        defaults.set(evaluated, forKey: "plusGrandfatheringEvaluated")
        defaults.set(true, forKey: "plusGrandfathered")
        let persistence = MemoryComplimentaryPlusPersistence()
        let store = PlusEntitlementStore(userDefaults: defaults, persistence: persistence)
        #expect(store.isComplimentary)
        #expect(persistence.entitled)
        #expect(defaults.bool(forKey: PlusEntitlementStore.complimentaryKey))
    }

    @Test("Old evaluated non-entitled users remain free")
    func evaluationIsNotEntitlement() {
        let defaults = defaults()
        defaults.set(true, forKey: "plusGrandfatheringEvaluated")
        let persistence = MemoryComplimentaryPlusPersistence()
        let store = PlusEntitlementStore(userDefaults: defaults, persistence: persistence)
        #expect(store.isComplimentary == false)
        #expect(persistence.writes == 0)
    }

    @Test("Grant survives relaunch and replacement of app defaults")
    func persistenceRecovery() {
        let persistence = MemoryComplimentaryPlusPersistence()
        let original = defaults()
        PlusEntitlementStore(userDefaults: original, persistence: persistence)
            .grantComplimentaryPlus()
        #expect(
            PlusEntitlementStore(userDefaults: original, persistence: persistence).isComplimentary)
        let replacement = defaults()
        #expect(
            PlusEntitlementStore(userDefaults: replacement, persistence: persistence)
                .isComplimentary)
        #expect(replacement.bool(forKey: PlusEntitlementStore.complimentaryKey))
    }

    @Test("Unavailable persistence retains access and retries; delayed sync restores access")
    func unavailablePersistence() {
        let persistence = MemoryComplimentaryPlusPersistence()
        persistence.unavailable = true
        let local = defaults()
        let store = PlusEntitlementStore(userDefaults: local, persistence: persistence)
        store.grantComplimentaryPlus()
        #expect(store.isComplimentary)
        #expect(PlusEntitlementStore(userDefaults: local, persistence: persistence).isComplimentary)
        let replacement = PlusEntitlementStore(userDefaults: defaults(), persistence: persistence)
        #expect(replacement.isComplimentary == false)
        persistence.unavailable = false
        store.reconcile()
        replacement.reconcile()
        #expect(persistence.entitled)
        #expect(replacement.isComplimentary)
        persistence.unavailable = true
        replacement.reconcile()
        #expect(replacement.isComplimentary)
    }

    #if !COMPLIMENTARY_PLUS_BETA_GRANT
        @Test("Removing the temporary build condition disables the live grant")
        func removedGrantIsDisabled() async {
            #expect(await TemporaryBetaPlusGrant.isEligible() == false)
        }
    #endif

    @Test("Only enabled verified sandbox grants")
    func eligibility() {
        #expect(TemporaryBetaPlusGrant.allowsGrant(enabled: true, verifiedEnvironment: .sandbox))
        let environments: [AppStore.Environment?] = [.production, .xcode, nil, .sandbox]
        for environment in environments {
            #expect(
                TemporaryBetaPlusGrant.allowsGrant(enabled: false, verifiedEnvironment: environment)
                    == false)
            if environment != .sandbox {
                #expect(
                    TemporaryBetaPlusGrant.allowsGrant(
                        enabled: true, verifiedEnvironment: environment) == false)
            }
        }
    }

    @Test(
        "Beta grants regardless of watchlist or prior evaluation; StoreKit cannot revoke it",
        arguments: [0, 3, 10])
    func betaGrant(count: Int) async {
        let defaults = defaults()
        defaults.set(true, forKey: "plusGrandfatheringEvaluated")
        let persistence = MemoryComplimentaryPlusPersistence()
        let client = StubPurchaseStoreClient(isStoreEntitled: false)
        let purchases = PurchaseService(
            store: client,
            entitlementStore: PlusEntitlementStore(
                userDefaults: defaults, persistence: persistence),
            complimentaryGrantEligibility: { true }
        )
        await purchases.start(watchlistCount: count)
        #expect(purchases.isComplimentary)
        #expect(purchases.isStoreEntitled == false)
        #expect(await purchases.canAddToWatchlist(currentCount: 100))
        _ = await purchases.restorePurchases()
        _ = await purchases.purchase(StoreProduct(.tipTrailer))
        client.isStoreEntitled = true
        await purchases.refreshEntitlements()
        client.isStoreEntitled = false
        await purchases.refreshEntitlements()
        #expect(purchases.isUnlimitedWatchlist)
        #expect(purchases.isComplimentary)
        #expect(purchases.isStoreEntitled == false)
    }

    @Test("Complimentary access works while StoreKit is suspended")
    func complimentaryDoesNotWaitForStoreKit() async {
        let client = StubPurchaseStoreClient()
        client.delayEntitlementResolution = true
        let purchases = PurchaseService(
            store: client,
            entitlementStore: PlusEntitlementStore(
                userDefaults: defaults(), persistence: MemoryComplimentaryPlusPersistence()),
            complimentaryGrantEligibility: { true }
        )
        let startTask = Task { await purchases.start(watchlistCount: 0) }
        for _ in 0..<200 {
            if client.entitlementWaiterCount > 0 { break }
            await Task.yield()
        }
        #expect(client.entitlementWaiterCount > 0)
        #expect(purchases.hasResolvedStoreEntitlement == false)
        #expect(purchases.isComplimentary)
        #expect(await purchases.canAddToWatchlist(currentCount: 100))
        client.releaseEntitlementResolution()
        await startTask.value
    }

    @Test("Temporary eligibility failure retries on activation")
    func retryEligibility() async {
        var eligible = false
        let purchases = PurchaseService(
            store: StubPurchaseStoreClient(),
            entitlementStore: PlusEntitlementStore(
                userDefaults: defaults(), persistence: MemoryComplimentaryPlusPersistence()),
            complimentaryGrantEligibility: { eligible }
        )
        await purchases.start(watchlistCount: 0)
        #expect(purchases.isComplimentary == false)
        eligible = true
        await purchases.handleSceneBecameActive()
        #expect(purchases.isComplimentary)
    }

    @Test("Production honors migration before StoreKit resolves")
    func productionMigration() async {
        let defaults = defaults()
        defaults.set(true, forKey: "plusGrandfathered")
        let purchases = PurchaseService(
            store: StubPurchaseStoreClient(),
            entitlementStore: PlusEntitlementStore(
                userDefaults: defaults, persistence: MemoryComplimentaryPlusPersistence())
        )
        #expect(purchases.hasResolvedStoreEntitlement == false)
        #expect(await purchases.canAddToWatchlist(currentCount: 100))
    }
}
