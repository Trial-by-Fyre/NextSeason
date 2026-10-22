//
//  IgnoreComplimentaryPlusTests.swift
//  NextSeasonTests
//

import Foundation
import Testing

@testable import NextSeason

/// Ignore Complimentary Plus: StoreKit alone decides effective access while the
/// stored grant stays intact. Scenario numbers refer to
/// Documentation/Reviews/IgnoreComplimentaryPlus-2026-10-21.md.
@MainActor
struct IgnoreComplimentaryPlusTests {
    private let defaults: UserDefaults
    private let persistence = MemoryComplimentaryPlusPersistence()

    init() {
        let suiteName = "IgnoreComplimentaryPlusTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// Complimentary grant stored by default; StoreKit pre-resolved unless `initial` says otherwise.
    private func makeService(
        store: StubPurchaseStoreClient = StubPurchaseStoreClient(),
        complimentary: Bool = true,
        initial: StoreEntitlementState? = nil,
        allowed: @escaping @MainActor () -> Bool = { true }
    ) -> PurchaseService {
        defaults.set(complimentary, forKey: PlusEntitlementStore.complimentaryKey)
        return PurchaseService(
            store: store,
            entitlementStore: PlusEntitlementStore(
                userDefaults: defaults, persistence: persistence),
            initialStoreEntitlement: initial ?? .resolved(isEntitled: store.isStoreEntitled),
            simulationAvailability: allowed
        )
    }

    private func show(_ id: Int) -> Show {
        Show(
            id: id, name: "Show \(id)", tvMazeURL: nil, summaryHTML: nil,
            posterMediumURL: nil, posterOriginalURL: nil, status: .running,
            premiered: nil, ended: nil, network: nil, genres: [], averageRuntime: nil,
            seasons: [], nextEpisode: nil, updatedAt: .now)
    }

    /// Five saved shows (1 oldest) and a reconciler wired like `AppCompositionRoot`.
    private func makeWatchlist(
        _ purchases: PurchaseService
    ) async throws -> (InMemoryWatchlistRepository, WatchlistAccessReconciler) {
        let repository = InMemoryWatchlistRepository()
        for id in 1...5 { try await repository.add(show(id)) }
        let reconciler = WatchlistAccessReconciler(
            repository: repository,
            userDefaults: defaults,
            access: { purchases.confirmedWatchlistAccess }
        )
        return (repository, reconciler)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    private var grantIsIntact: Bool {
        defaults.bool(forKey: PlusEntitlementStore.complimentaryKey) && persistence.entitled
    }

    // MARK: - Switch off / on

    @Test("Switch off: complimentary Plus behaves exactly as before")  // 1
    func switchOffKeepsComplimentaryAccess() {
        let purchases = makeService()
        #expect(purchases.isIgnoringComplimentaryPlus == false)
        #expect(purchases.isComplimentary)
        #expect(purchases.isUnlimitedWatchlist)
        #expect(purchases.confirmedWatchlistAccess == true)
        #expect(purchases.restoreNotice == nil)
        #expect(PlusAccountPresentation(purchases) == .complimentaryPlus)
    }

    @Test("Switch on: StoreKit alone decides access", arguments: [false, true])  // 2, 3
    func switchOnUsesStoreKitOnly(paid: Bool) async {
        let purchases = makeService(store: StubPurchaseStoreClient(isStoreEntitled: paid))
        purchases.setIgnoreComplimentaryPlus(true)

        #expect(purchases.isIgnoringComplimentaryPlus)
        #expect(purchases.isComplimentary == false)
        #expect(purchases.hasStoredComplimentaryPlus)
        #expect(purchases.isUnlimitedWatchlist == paid)
        #expect(purchases.confirmedWatchlistAccess == paid)
        #expect(await purchases.canAddToWatchlist(currentCount: 3) == paid)
        #expect((purchases.restoreNotice == nil) == paid)
        #expect(PlusAccountPresentation(purchases) == (paid ? .paidPlus : .free))
    }

    @Test("Toggling never writes the stored grant, and turning off restores it")  // 14
    func grantStaysIntact() async throws {
        let purchases = makeService()
        let (repository, reconciler) = try await makeWatchlist(purchases)

        purchases.setIgnoreComplimentaryPlus(true)
        #expect(await reconciler.reconcile() == .paused([4, 5]))
        #expect(grantIsIntact)

        purchases.setIgnoreComplimentaryPlus(false)
        #expect(purchases.isComplimentary)
        #expect(await reconciler.reconcile() == .resumed([4, 5]))
        #expect(try await repository.activeShowIDs() == [1, 2, 3, 4, 5])
        #expect(grantIsIntact)
    }

    // MARK: - Real StoreKit lifecycle

    @Test("Expiration pauses and resubscribing resumes while ignoring complimentary")  // 4, 5
    func expirationAndResubscribe() async throws {
        let store = StubPurchaseStoreClient(isStoreEntitled: true)
        let purchases = makeService(store: store)
        let (_, reconciler) = try await makeWatchlist(purchases)
        purchases.setIgnoreComplimentaryPlus(true)
        #expect(await reconciler.reconcile() == .unchanged)

        store.isStoreEntitled = false
        await purchases.refreshEntitlements()
        #expect(purchases.confirmedWatchlistAccess == false)
        #expect(await reconciler.reconcile() == .paused([4, 5]))

        #expect(await purchases.purchase(StoreProduct(.plusMonthly)) == .success)
        #expect(purchases.confirmedWatchlistAccess == true)
        #expect(await reconciler.reconcile() == .resumed([4, 5]))
        #expect(purchases.isIgnoringComplimentaryPlus)
    }

    @Test("Restore that finds a subscription grants access")  // 6
    func restoreFindsSubscription() async {
        let store = StubPurchaseStoreClient()
        let purchases = makeService(store: store)
        purchases.setIgnoreComplimentaryPlus(true)
        store.isStoreEntitled = true
        #expect(await purchases.restorePurchases() == .success)
        #expect(purchases.isUnlimitedWatchlist)
        #expect(purchases.restoreNotice == nil)
    }

    @Test("Unverified StoreKit read pauses nothing and reports verification")  // 7
    func unverifiedRead() async {
        let store = StubPurchaseStoreClient()
        store.reportsUnverifiedEntitlement = true
        let purchases = makeService(store: store, initial: .loading)
        purchases.setIgnoreComplimentaryPlus(true)
        await purchases.start()

        #expect(purchases.confirmedWatchlistAccess == nil)
        #expect(purchases.isUnlimitedWatchlist == false)
        #expect(await purchases.canAddToWatchlist(currentCount: 3) == false)
        #expect(purchases.restoreNotice?.contains("couldn't verify") == true)
        #expect(PlusAccountPresentation(purchases) == .unableToVerify)
    }

    @Test("Adds wait for StoreKit, even across a foreground return")  // 8
    func addWaitsForStoreKit() async {
        let store = StubPurchaseStoreClient()
        store.delayEntitlementResolution = true
        let purchases = makeService(store: store, initial: .loading)
        purchases.setIgnoreComplimentaryPlus(true)
        let start = Task { await purchases.start() }
        await waitUntil { store.entitlementWaiterCount == 1 }
        #expect(purchases.confirmedWatchlistAccess == nil)

        var finished = false
        let add = Task {
            let allowed = await purchases.canAddToWatchlist(currentCount: 3)
            finished = true
            return allowed
        }
        // Foreground return re-reconciles the grant; it must not release the add.
        await purchases.handleSceneBecameActive()
        for _ in 0..<20 { await Task.yield() }
        #expect(finished == false)

        store.releaseEntitlementResolution()
        #expect(await add.value == false)
        await start.value
    }

    @Test("Turning the switch off releases an add waiting for StoreKit")  // 9
    func switchOffReleasesWaitingAdd() async {
        let store = StubPurchaseStoreClient()
        store.delayEntitlementResolution = true
        let purchases = makeService(store: store, initial: .loading)
        purchases.setIgnoreComplimentaryPlus(true)
        let add = Task { await purchases.canAddToWatchlist(currentCount: 3) }
        for _ in 0..<20 { await Task.yield() }

        purchases.setIgnoreComplimentaryPlus(false)
        #expect(await add.value)
    }

    @Test("Purchase and restore failures leave access and the switch unchanged")  // 10
    func failuresKeepState() async {
        let store = StubPurchaseStoreClient(purchaseOutcome: .failed("Declined"))
        store.restoreError = URLError(.notConnectedToInternet)
        let purchases = makeService(store: store)
        purchases.setIgnoreComplimentaryPlus(true)

        #expect(await purchases.purchase(StoreProduct(.plusAnnual)) == .failed("Declined"))
        #expect(purchases.lastErrorMessage == "Declined")
        if case .failed = await purchases.restorePurchases() {
        } else {
            Issue.record("Restore should fail")
        }
        #expect(purchases.isIgnoringComplimentaryPlus)
        #expect(purchases.isUnlimitedWatchlist == false)
        #expect(grantIsIntact)
    }

    // MARK: - Simulate Free Tier interaction

    @Test(
        "Simulation wins while both are on; each switch is independent", arguments: [false, true])  // 11
    func bothSwitches(paid: Bool) {
        let purchases = makeService(store: StubPurchaseStoreClient(isStoreEntitled: paid))
        purchases.setIgnoreComplimentaryPlus(true)
        purchases.setFreeTierSimulation(true)
        #expect(purchases.isUnlimitedWatchlist == false)
        #expect(purchases.confirmedWatchlistAccess == false)

        purchases.setFreeTierSimulation(false)
        #expect(purchases.isIgnoringComplimentaryPlus)
        #expect(purchases.isUnlimitedWatchlist == paid)

        purchases.setFreeTierSimulation(true)
        purchases.setIgnoreComplimentaryPlus(false)
        #expect(purchases.isSimulatingFreeTier)
        #expect(purchases.isUnlimitedWatchlist == false)
    }

    @Test("A verified purchase ends simulation but leaves the override on")  // 12
    func purchaseEndsSimulationOnly() async {
        let purchases = makeService()
        await purchases.start()
        purchases.setIgnoreComplimentaryPlus(true)
        purchases.setFreeTierSimulation(true)

        #expect(await purchases.purchase(StoreProduct(.plusAnnual)) == .success)
        #expect(purchases.isSimulatingFreeTier == false)
        #expect(purchases.isIgnoringComplimentaryPlus)
        #expect(purchases.isUnlimitedWatchlist)
        #expect(PlusAccountPresentation(purchases) == .paidPlus)
    }

    // MARK: - Availability

    @Test("Without the beta gate the override cannot change access")  // 13
    func unavailableGate() {
        var allowed = false
        let purchases = makeService(allowed: { allowed })
        purchases.setIgnoreComplimentaryPlus(true)
        #expect(purchases.isIgnoringComplimentaryPlus == false)
        #expect(purchases.isUnlimitedWatchlist)

        // An earlier request no longer applies once eligibility is gone.
        allowed = true
        purchases.setIgnoreComplimentaryPlus(true)
        allowed = false
        #expect(purchases.isIgnoringComplimentaryPlus == false)
        #expect(purchases.isComplimentary)
        #expect(purchases.confirmedWatchlistAccess == true)
    }

    @Test("Diagnostics shows the raw StoreKit read and expiration")
    func rawStoreKitStatus() async {
        let store = StubPurchaseStoreClient(isStoreEntitled: true)
        let expiration = Date.now.addingTimeInterval(3600)
        store.plusExpirationDate = expiration
        let purchases = makeService(store: store, initial: .loading)
        #expect(purchases.lastCommittedCheck == nil)
        await purchases.refreshEntitlements()
        #expect(purchases.lastCommittedCheck == .active)
        #expect(purchases.lastCommittedExpirationDate == expiration)
        #expect(purchases.lastCommittedCheckDate != nil)
        // Complimentary access never shows up as StoreKit status.
        store.isStoreEntitled = false
        await purchases.refreshEntitlements()
        #expect(purchases.lastCommittedCheck == .inactive)
        #expect(purchases.lastCommittedExpirationDate == nil)
        #expect(purchases.isUnlimitedWatchlist)
    }
}
