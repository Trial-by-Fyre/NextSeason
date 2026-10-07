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
final class MutableComplimentaryPlusEligibility {
    var isEligible = false
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
        "Unavailable transaction uses only the sandbox receipt fallback", arguments: [false, true])
    func unavailableTransactionFallback(hasReceipt: Bool) async {
        var events: [String] = []
        let eligible = await TemporaryBetaPlusGrant.evaluateEligibility(
            enabled: true,
            verifiedEnvironment: { throw NSError(domain: "GrantTest", code: 7) },
            hasSandboxReceipt: { hasReceipt },
            record: { events.append($0) }
        )
        #expect(eligible == hasReceipt)
        #expect(
            events.contains("complimentary_plus_transaction_unavailable domain=GrantTest code=7"))
        #expect(events.contains("complimentary_plus_receipt_fallback eligible=\(hasReceipt)"))
    }

    @Test(
        "Verified transaction decides eligibility without consulting the receipt",
        arguments: [AppStore.Environment.production, .xcode, .sandbox])
    func verifiedTransactionTakesPrecedence(environment: AppStore.Environment) async {
        var events: [String] = []
        let eligible = await TemporaryBetaPlusGrant.evaluateEligibility(
            enabled: true,
            verifiedEnvironment: { environment },
            hasSandboxReceipt: {
                Issue.record("A verified transaction must not use receipt fallback")
                return true
            },
            record: { events.append($0) }
        )
        #expect(eligible == (environment == .sandbox))
        #expect(
            events.contains(
                "complimentary_plus_verified_environment=\(environment) eligible=\(eligible)"))
    }

    @Test("Unverified transactions do not use receipt fallback")
    func unverifiedTransactionRejectsReceipt() async {
        var events: [String] = []
        let eligible = await TemporaryBetaPlusGrant.evaluateEligibility(
            enabled: true,
            verifiedEnvironment: { nil },
            hasSandboxReceipt: {
                Issue.record("Failed verification must not use receipt fallback")
                return true
            },
            record: { events.append($0) }
        )
        #expect(eligible == false)
        #expect(events == ["complimentary_plus_grant_rejected_unverified"])
    }

    @Test("Disabled granting never queries StoreKit or uses a sandbox receipt")
    func disabledGrantSkipsDetection() async {
        var events: [String] = []
        let eligible = await TemporaryBetaPlusGrant.evaluateEligibility(
            enabled: false,
            verifiedEnvironment: {
                Issue.record("Disabled granting must not query StoreKit")
                throw NSError(domain: "GrantTest", code: 7)
            },
            hasSandboxReceipt: {
                Issue.record("Disabled granting must not inspect the receipt")
                return true
            },
            record: { events.append($0) }
        )
        #expect(eligible == false)
        #expect(events == ["complimentary_plus_grant_disabled"])
    }

    @Test("Cancellation does not trigger receipt fallback")
    func cancellationRejectsFallback() async {
        var events: [String] = []
        let eligible = await TemporaryBetaPlusGrant.evaluateEligibility(
            enabled: true,
            verifiedEnvironment: { throw CancellationError() },
            hasSandboxReceipt: {
                Issue.record("Cancellation must not grant access through fallback")
                return true
            },
            record: { events.append($0) }
        )
        #expect(eligible == false)
        #expect(events == ["complimentary_plus_grant_cancelled"])
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

    @Test("Receipt fallback grants durable Plus recognized by a normal build")
    func receiptFallbackPersistsAccess() async {
        let local = defaults()
        let persistence = MemoryComplimentaryPlusPersistence()
        let beta = PurchaseService(
            store: StubPurchaseStoreClient(),
            entitlementStore: PlusEntitlementStore(userDefaults: local, persistence: persistence),
            complimentaryGrantEligibility: {
                await TemporaryBetaPlusGrant.evaluateEligibility(
                    enabled: true,
                    verifiedEnvironment: { throw NSError(domain: "GrantTest", code: 7) },
                    hasSandboxReceipt: { true },
                    record: { _ in }
                )
            }
        )
        await beta.start(watchlistCount: 0)
        #expect(beta.isComplimentary)
        #expect(beta.isStoreEntitled == false)
        #expect(persistence.entitled)
        #expect(local.bool(forKey: PlusEntitlementStore.complimentaryKey))

        let normal = PurchaseService(
            store: StubPurchaseStoreClient(),
            entitlementStore: PlusEntitlementStore(
                userDefaults: defaults(), persistence: persistence)
        )
        await normal.start(watchlistCount: 0)
        #expect(normal.isComplimentary)
        #expect(normal.isStoreEntitled == false)
        #expect(await normal.canAddToWatchlist(currentCount: 100))
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
        let eligibility = MutableComplimentaryPlusEligibility()
        let purchases = PurchaseService(
            store: StubPurchaseStoreClient(),
            entitlementStore: PlusEntitlementStore(
                userDefaults: defaults(), persistence: MemoryComplimentaryPlusPersistence()),
            complimentaryGrantEligibility: { eligibility.isEligible }
        )
        await purchases.start(watchlistCount: 0)
        #expect(purchases.isComplimentary == false)
        eligibility.isEligible = true
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
