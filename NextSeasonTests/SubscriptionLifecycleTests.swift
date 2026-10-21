//
//  SubscriptionLifecycleTests.swift
//  NextSeasonTests
//

import Foundation
import SwiftData
import Testing
import UserNotifications

@testable import NextSeason

/// End-to-end Plus lifecycle through `PurchaseService.purchase` / `restorePurchases`
/// (not just `refreshEntitlements()`), the production SwiftData repository, and the
/// `AppCompositionRoot` reconciler wiring: buying at the free limit, resubscribing
/// or restoring after a lapse, restore failure and recovery, and relaunch.
@MainActor
struct SubscriptionLifecycleTests {
    /// Adds in these tests carry season data, so TVMaze is never contacted.
    private final class UnusedTVMazeService: TVMazeService {
        func searchShows(matching query: String) async throws -> [Show] { [] }
        func lookupShow(theTVDBID: Int) async throws -> Show { throw TVMazeError.notFound }
        func show(id: Int, bypassCache: Bool) async throws -> Show { throw TVMazeError.notFound }
        func updatedShows(since period: TVMazeUpdatePeriod) async throws -> [Int: Date] { [:] }
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "SubscriptionLifecycleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeContainer() throws -> ModelContainer {
        try NextSeasonModelContainer.make(
            configuration: ModelConfiguration(
                "subscription-lifecycle-\(UUID().uuidString)", isStoredInMemoryOnly: true))
    }

    /// A fresh context over the same store stands in for a new process at relaunch.
    private func makeRepository(
        container: ModelContainer, defaults: UserDefaults
    ) -> SwiftDataWatchlistRepository {
        SwiftDataWatchlistRepository(
            context: ModelContext(container), rowMarks: WatchlistRowMarks(userDefaults: defaults))
    }

    private func makePurchases(
        store: StubPurchaseStoreClient,
        initial: StoreEntitlementState? = nil
    ) -> PurchaseService {
        PurchaseService(
            store: store,
            entitlementStore: PlusEntitlementStore(
                userDefaults: isolatedDefaults(),
                persistence: MemoryComplimentaryPlusPersistence()),
            initialStoreEntitlement: initial ?? .resolved(isEntitled: store.isStoreEntitled),
            simulationAvailability: { false }
        )
    }

    private func makeReconciler(
        repository: any WatchlistRepository, purchases: PurchaseService,
        defaults: UserDefaults
    ) -> WatchlistAccessReconciler {
        WatchlistAccessReconciler(
            repository: repository,
            userDefaults: defaults,
            access: { purchases.confirmedWatchlistAccess },
            waitForAccess: { await purchases.waitForInitialEntitlementResolution() }
        )
    }

    private func show(_ id: Int) -> Show {
        Show(
            id: id, name: "Show \(id)", tvMazeURL: nil, summaryHTML: nil,
            posterMediumURL: nil, posterOriginalURL: nil, status: .running,
            premiered: nil, ended: nil, network: nil, genres: [], averageRuntime: nil,
            seasons: [
                Season(
                    id: id * 10 + 1, number: 1, premiereDate: TVMazeDate.dateOnly("2022-02-18"),
                    endDate: TVMazeDate.dateOnly("2022-04-08"), episodeOrder: 9)
            ],
            nextEpisode: nil, updatedAt: .now)
    }

    /// Saves shows with increasing `dateAdded`, so show 1 is the oldest.
    private func seed(_ ids: ClosedRange<Int>, into repository: SwiftDataWatchlistRepository)
        async throws
    {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        for id in ids {
            try await repository.restoreRemoved(
                TrackedShow(from: show(id), at: start.addingTimeInterval(Double(id) * 60)),
                isPaused: false)
        }
    }

    private func add(
        _ id: Int, repository: any WatchlistRepository, purchases: PurchaseService
    ) async throws -> WatchlistTracking.ToggleOutcome {
        let analytics = RecordingAnalyticsService()
        return try await WatchlistTracking.add(
            show(id),
            source: .search,
            repository: repository,
            tvMaze: UnusedTVMazeService(),
            analytics: analytics,
            notifications: NotificationService(
                userDefaults: isolatedDefaults(),
                authorizationStatusForTesting: .denied,
                analytics: analytics),
            prompt: WatchlistNotificationPromptState(),
            purchases: purchases
        )
    }

    private func pausedIDs(_ repository: any WatchlistRepository) async throws -> Set<Int> {
        Set(try await repository.all().filter(\.isPaused).map(\.id))
    }

    /// Plus subscriber with shows 1…6 whose subscription has expired: 1–3 active, 4–6 paused.
    private func lapsedFixture() async throws -> (
        SwiftDataWatchlistRepository, StubPurchaseStoreClient, PurchaseService,
        WatchlistAccessReconciler
    ) {
        let defaults = isolatedDefaults()
        let repository = makeRepository(container: try makeContainer(), defaults: defaults)
        try await seed(1...6, into: repository)
        let store = StubPurchaseStoreClient(isStoreEntitled: true)
        let purchases = makePurchases(store: store)
        await purchases.start()
        let reconciler = makeReconciler(
            repository: repository, purchases: purchases, defaults: defaults)
        #expect(await reconciler.reconcile() == .unchanged)

        store.isStoreEntitled = false
        await purchases.handleSceneBecameActive()
        #expect(await reconciler.reconcile() == .paused([4, 5, 6]))
        #expect(reconciler.isPausedAlertPending)
        return (repository, store, purchases, reconciler)
    }

    // MARK: - Purchasing at the free limit

    @Test(
        "Buying Plus at the free limit allows the next add immediately",
        arguments: [StoreProductID.plusMonthly, .plusAnnual])
    func purchaseAtLimitUnlocksNextAdd(_ productID: StoreProductID) async throws {
        let defaults = isolatedDefaults()
        let repository = makeRepository(container: try makeContainer(), defaults: defaults)
        let purchases = makePurchases(store: StubPurchaseStoreClient(isStoreEntitled: false))
        await purchases.start()
        let reconciler = makeReconciler(
            repository: repository, purchases: purchases, defaults: defaults)
        for id in 1...3 {
            #expect(try await add(id, repository: repository, purchases: purchases) == .added)
        }
        #expect(try await add(4, repository: repository, purchases: purchases) == .paywallRequired)

        #expect(await purchases.purchase(StoreProduct(productID)) == .success)
        #expect(purchases.confirmedWatchlistAccess == true)

        #expect(
            try await add(4, repository: repository, purchases: purchases) == .added,
            "No Restore or relaunch needed after a verified purchase")
        #expect(try await add(5, repository: repository, purchases: purchases) == .added)
        #expect(await reconciler.reconcile() == .unchanged)
        #expect(try await repository.activeShowIDs() == [1, 2, 3, 4, 5])
    }

    @Test(
        "A cancelled or failed purchase leaves a lapsed user's paused shows unchanged",
        arguments: [PurchaseOutcome.cancelled, .failed("Declined")])
    func unsuccessfulPurchaseKeepsPausedShows(_ outcome: PurchaseOutcome) async throws {
        let (repository, store, purchases, reconciler) = try await lapsedFixture()
        store.purchaseOutcome = outcome

        #expect(await purchases.purchase(StoreProduct(.plusMonthly)) == outcome)
        #expect(purchases.isPurchasing == false)
        #expect(purchases.confirmedWatchlistAccess == false)
        #expect(await reconciler.reconcile() == .unchanged)
        #expect(try await pausedIDs(repository) == [4, 5, 6])
        #expect(try await repository.all().count == 6)
    }

    // MARK: - Recovering access after a lapse

    @Test(
        "Resubscribing after a lapse resumes every paused show",
        arguments: [StoreProductID.plusMonthly, .plusAnnual])
    func resubscribeResumesAllPausedShows(_ productID: StoreProductID) async throws {
        let (repository, _, purchases, reconciler) = try await lapsedFixture()

        #expect(await purchases.purchase(StoreProduct(productID)) == .success)
        #expect(await reconciler.reconcile() == .resumed([4, 5, 6]))
        #expect(try await repository.activeShowIDs() == [1, 2, 3, 4, 5, 6])
        #expect(try await repository.all().count == 6, "No duplicates or lost rows")
        #expect(reconciler.isPausedAlertPending == false)
        #expect(try await add(7, repository: repository, purchases: purchases) == .added)
    }

    @Test("Restore Purchases after a lapse resumes every paused show when Plus is valid")
    func restoreAfterLapseResumesAll() async throws {
        let (repository, store, purchases, reconciler) = try await lapsedFixture()

        // e.g. the subscription was renewed on another device.
        store.isStoreEntitled = true
        #expect(await purchases.restorePurchases() == .success)
        #expect(await reconciler.reconcile() == .resumed([4, 5, 6]))
        #expect(try await pausedIDs(repository).isEmpty)
    }

    @Test("A failed restore changes nothing and a retry can still restore Plus")
    func restoreFailureThenRecovery() async throws {
        let (repository, store, purchases, reconciler) = try await lapsedFixture()
        store.restoreError = URLError(.notConnectedToInternet)
        store.isStoreEntitled = true  // Valid on the server, but sync fails first.

        let failed = await purchases.restorePurchases()
        #expect(failed == .failed(try #require(purchases.lastErrorMessage)))
        #expect(purchases.isPurchasing == false, "Controls are usable after a failure")
        #expect(purchases.confirmedWatchlistAccess == false, "Failure is not a grant")
        #expect(await reconciler.reconcile() == .unchanged)
        #expect(try await pausedIDs(repository) == [4, 5, 6])

        purchases.clearMessages()
        store.restoreError = nil
        #expect(await purchases.restorePurchases() == .success)
        #expect(purchases.lastErrorMessage == nil)
        #expect(await reconciler.reconcile() == .resumed([4, 5, 6]))
    }

    @Test("Restore Purchases with nothing to restore keeps a free user at the limit")
    func restoreWithoutPurchasesStaysFree() async throws {
        let defaults = isolatedDefaults()
        let repository = makeRepository(container: try makeContainer(), defaults: defaults)
        try await seed(1...3, into: repository)
        let purchases = makePurchases(store: StubPurchaseStoreClient(isStoreEntitled: false))
        await purchases.start()
        let reconciler = makeReconciler(
            repository: repository, purchases: purchases, defaults: defaults)

        #expect(await purchases.restorePurchases() == .success)
        #expect(purchases.isUnlimitedWatchlist == false)
        #expect(await reconciler.reconcile() == .unchanged)
        #expect(try await add(4, repository: repository, purchases: purchases) == .paywallRequired)
        #expect(try await repository.activeShowIDs() == [1, 2, 3])
    }

    // MARK: - Termination and relaunch

    @Test("Plus survives relaunch: nothing pauses while StoreKit loads, and adds wait for it")
    func plusSurvivesRelaunch() async throws {
        let container = try makeContainer()
        let defaults = isolatedDefaults()
        let firstLaunch = makeRepository(container: container, defaults: defaults)
        try await seed(1...5, into: firstLaunch)

        // New process: same store, StoreKit has not answered yet.
        let repository = makeRepository(container: container, defaults: defaults)
        let store = StubPurchaseStoreClient(isStoreEntitled: true)
        store.delayEntitlementResolution = true
        let purchases = makePurchases(store: store, initial: .loading)
        let reconciler = makeReconciler(
            repository: repository, purchases: purchases, defaults: defaults)

        let start = Task { await purchases.start() }
        let pendingAdd = Task { try await add(6, repository: repository, purchases: purchases) }
        #expect(await reconciler.reconcile() == .unchanged, "Loading is not a lapse")
        #expect(try await pausedIDs(repository).isEmpty)

        while store.entitlementWaiterCount == 0 { await Task.yield() }
        store.releaseEntitlementResolution()
        await start.value
        #expect(try await pendingAdd.value == .added, "Not treated as free during launch")
        #expect(await reconciler.reconcileWhenAccessKnown() == .unchanged)
        #expect(try await repository.activeShowIDs() == [1, 2, 3, 4, 5, 6])
    }

    @Test(
        "A lapse survives relaunch: paused shows stay saved and paused, then resume on resubscribe")
    func lapseSurvivesRelaunch() async throws {
        let container = try makeContainer()
        let defaults = isolatedDefaults()
        let firstRepository = makeRepository(container: container, defaults: defaults)
        try await seed(1...6, into: firstRepository)
        let firstPurchases = makePurchases(store: StubPurchaseStoreClient(isStoreEntitled: false))
        let firstReconciler = makeReconciler(
            repository: firstRepository, purchases: firstPurchases, defaults: defaults)
        #expect(await firstReconciler.reconcile() == .paused([4, 5, 6]))

        // New process, still lapsed.
        let repository = makeRepository(container: container, defaults: defaults)
        let store = StubPurchaseStoreClient(isStoreEntitled: false)
        let purchases = makePurchases(store: store, initial: .loading)
        let reconciler = makeReconciler(
            repository: repository, purchases: purchases, defaults: defaults)
        #expect(reconciler.shouldPresentPausedAlert == false, "Not before StoreKit answers")

        await purchases.start()
        #expect(await reconciler.reconcileWhenAccessKnown() == .unchanged)
        #expect(try await pausedIDs(repository) == [4, 5, 6])
        #expect(try await repository.all().count == 6)
        #expect(reconciler.shouldPresentPausedAlert, "The unacknowledged alert survives")

        #expect(await purchases.purchase(StoreProduct(.plusAnnual)) == .success)
        #expect(await reconciler.reconcile() == .resumed([4, 5, 6]))
    }
}
