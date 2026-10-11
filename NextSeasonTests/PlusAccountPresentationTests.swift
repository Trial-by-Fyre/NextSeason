//
//  PlusAccountPresentationTests.swift
//  NextSeasonTests
//

import Foundation
import Testing

@testable import NextSeason

/// About's Plus status, footer, and upgrade-button decisions across loading,
/// unverified, confirmed free, paid, complimentary, and simulated states.
@MainActor
struct PlusAccountPresentationTests {
    /// Isolated entitlement storage and an in-memory StoreKit client.
    private func makePurchases(
        store: StubPurchaseStoreClient,
        initial: StoreEntitlementState,
        complimentary: Bool = false
    ) -> PurchaseService {
        let defaults = UserDefaults(
            suiteName: "PlusAccountPresentationTests.\(UUID().uuidString)")!
        defaults.set(complimentary, forKey: PlusEntitlementStore.complimentaryKey)
        return PurchaseService(
            store: store,
            entitlementStore: PlusEntitlementStore(
                userDefaults: defaults, persistence: MemoryComplimentaryPlusPersistence()),
            initialStoreEntitlement: initial,
            simulationAvailability: { true }
        )
    }

    /// A service whose first StoreKit read could not verify a Plus entitlement.
    private func makeUnverifiedPurchases(
        store: StubPurchaseStoreClient = StubPurchaseStoreClient(isStoreEntitled: false),
        complimentary: Bool = false
    ) async -> PurchaseService {
        store.reportsUnverifiedEntitlement = true
        let purchases = makePurchases(store: store, initial: .loading, complimentary: complimentary)
        await purchases.refreshEntitlements()
        return purchases
    }

    @Test("Loading keeps Checking… and hides the upgrade button")
    func loadingShowsChecking() {
        let purchases = makePurchases(store: StubPurchaseStoreClient(), initial: .loading)
        let presentation = PlusAccountPresentation(purchases)

        #expect(presentation == .checking)
        #expect(presentation.statusValue == "Checking…")
        #expect(presentation.footerText == "Confirming your NextSeason Plus status.")
        #expect(presentation.showsUpgradeButton == false)
    }

    @Test("Unverified entitlement explains the uncertainty instead of showing the free tier")
    func unverifiedShowsUnableToVerify() async {
        let purchases = await makeUnverifiedPurchases()
        let presentation = PlusAccountPresentation(purchases)

        #expect(purchases.storeEntitlement == .unverified)
        #expect(presentation == .unableToVerify)
        #expect(presentation.statusValue == "Unable to Verify Plus")
        #expect(
            presentation.footerText
                == "NextSeason couldn't verify your subscription status. Your saved shows are preserved. Check your connection and try Restore Purchases."
        )
        #expect(presentation.showsUpgradeButton == false)
    }

    @Test("Confirmed free keeps the three-show capacity and upgrade button")
    func confirmedFreeShowsCapacityAndUpgrade() {
        let purchases = makePurchases(
            store: StubPurchaseStoreClient(), initial: .resolved(isEntitled: false))
        let presentation = PlusAccountPresentation(purchases)

        #expect(presentation == .free)
        #expect(presentation.statusValue == "Up to 3 shows")
        #expect(presentation.footerText == "NextSeason Plus removes the watchlist limit.")
        #expect(presentation.showsUpgradeButton)
    }

    @Test("Paid Plus shows Unlimited without an upgrade button")
    func paidPlusShowsUnlimited() {
        let purchases = makePurchases(
            store: StubPurchaseStoreClient(isStoreEntitled: true),
            initial: .resolved(isEntitled: true))
        let presentation = PlusAccountPresentation(purchases)

        #expect(presentation == .paidPlus)
        #expect(presentation.statusValue == "Unlimited")
        #expect(presentation.footerText == "You have NextSeason Plus.")
        #expect(presentation.showsUpgradeButton == false)
    }

    @Test(
        "Complimentary Plus shows Unlimited regardless of StoreKit state",
        arguments: [StoreEntitlementState.loading, .unverified, .resolved(isEntitled: false)])
    func complimentaryShowsUnlimited(_ storeState: StoreEntitlementState) {
        let purchases = makePurchases(
            store: StubPurchaseStoreClient(), initial: storeState, complimentary: true)
        let presentation = PlusAccountPresentation(purchases)

        #expect(presentation == .complimentaryPlus)
        #expect(presentation.statusValue == "Unlimited")
        #expect(
            presentation.footerText
                == "You have permanent complimentary NextSeason Plus. Thank you for beta testing.")
        #expect(presentation.showsUpgradeButton == false)
    }

    @Test(
        "Simulate Free Tier keeps its simulated presentation over every actual state",
        arguments: [
            StoreEntitlementState.unverified, .resolved(isEntitled: false),
            .resolved(isEntitled: true),
        ])
    func simulationKeepsSimulatedPresentation(_ storeState: StoreEntitlementState) {
        let purchases = makePurchases(store: StubPurchaseStoreClient(), initial: storeState)
        purchases.setFreeTierSimulation(true)
        let presentation = PlusAccountPresentation(purchases)

        #expect(presentation == .simulatedFree(hasResolvedStoreEntitlement: true))
        #expect(presentation.statusValue == "Up to 3 shows (simulated)")
        #expect(presentation.footerText.hasPrefix("Free tier simulation is active."))
        #expect(presentation.showsUpgradeButton)
    }

    @Test("Simulate Free Tier still hides the upgrade button while StoreKit is loading")
    func simulationWhileLoadingHidesUpgrade() {
        let purchases = makePurchases(store: StubPurchaseStoreClient(), initial: .loading)
        purchases.setFreeTierSimulation(true)
        let presentation = PlusAccountPresentation(purchases)

        #expect(presentation == .simulatedFree(hasResolvedStoreEntitlement: false))
        #expect(presentation.statusValue == "Up to 3 shows (simulated)")
        #expect(presentation.showsUpgradeButton == false)
    }

    @Test("Unverified becomes confirmed free after a verified refresh")
    func unverifiedToConfirmedFree() async {
        let store = StubPurchaseStoreClient(isStoreEntitled: false)
        let purchases = await makeUnverifiedPurchases(store: store)
        #expect(PlusAccountPresentation(purchases) == .unableToVerify)

        store.reportsUnverifiedEntitlement = false
        await purchases.refreshEntitlements()
        let presentation = PlusAccountPresentation(purchases)

        #expect(presentation == .free)
        #expect(presentation.statusValue == "Up to 3 shows")
        #expect(presentation.showsUpgradeButton)
    }

    @Test("Restore Purchases moves unverified to paid Plus once StoreKit verifies it")
    func unverifiedToPaidThroughRestore() async {
        let store = StubPurchaseStoreClient(isStoreEntitled: true)
        let purchases = await makeUnverifiedPurchases(store: store)
        #expect(PlusAccountPresentation(purchases) == .unableToVerify)
        #expect(PlusAccountPresentation(purchases).showsUpgradeButton == false)

        store.reportsUnverifiedEntitlement = false
        #expect(await purchases.restorePurchases() == .success)
        let presentation = PlusAccountPresentation(purchases)

        #expect(presentation == .paidPlus)
        #expect(presentation.statusValue == "Unlimited")
        #expect(presentation.showsUpgradeButton == false)
    }

    @Test("A still-unverified Restore Purchases keeps the unable-to-verify presentation")
    func unverifiedRestoreStaysUnverified() async {
        let purchases = await makeUnverifiedPurchases()

        #expect(await purchases.restorePurchases() == .success)
        #expect(PlusAccountPresentation(purchases) == .unableToVerify)
        #expect(PlusAccountPresentation(purchases).showsUpgradeButton == false)
    }
}
