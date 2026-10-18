//
//  SubscriptionDowngradeTests.swift
//  NextSeasonTests
//

import Foundation
import SwiftData
import SwiftUI
import Testing
import UserNotifications

@testable import NextSeason

/// Plus lapse → pause shows beyond the free limit; Plus restored → resume all.
///
/// Uses the same `WatchlistAccessReconciler` + `PurchaseService.confirmedWatchlistAccess`
/// wiring as `AppCompositionRoot`, with an in-memory repository and stub StoreKit.
@MainActor
struct SubscriptionDowngradeTests {
    // MARK: - Fixtures

    private final class MockTVMazeService: TVMazeService, @unchecked Sendable {
        var showByID: [Int: Show] = [:]
        var failsUpdates = false
        private(set) var fetchedShowIDs: [Int] = []

        func searchShows(matching query: String) async throws -> [Show] { [] }

        func lookupShow(theTVDBID: Int) async throws -> Show {
            throw TVMazeError.notFound
        }

        func show(id: Int, bypassCache: Bool) async throws -> Show {
            fetchedShowIDs.append(id)
            guard let show = showByID[id] else { throw URLError(.notConnectedToInternet) }
            return show
        }

        func updatedShows(since period: TVMazeUpdatePeriod) async throws -> [Int: Date] {
            if failsUpdates { throw URLError(.notConnectedToInternet) }
            return [:]
        }
    }

    private final class RecordingNotifications: NotificationDelivering {
        private(set) var delivered: [SeasonNotificationContent] = []
        func deliver(_ content: SeasonNotificationContent) async -> NotificationDeliveryOutcome {
            delivered.append(content)
            return .accepted
        }
    }

    /// Show with season data so `WatchlistTracking.add` does not need a TVMaze fetch.
    private func show(_ id: Int, nextSeasonPremiere: Date? = nil) -> Show {
        var seasons = [
            Season(
                id: id * 10 + 1, number: 1, premiereDate: TVMazeDate.dateOnly("2022-02-18"),
                endDate: TVMazeDate.dateOnly("2022-04-08"), episodeOrder: 9)
        ]
        if let nextSeasonPremiere {
            seasons.append(
                Season(
                    id: id * 10 + 2, number: 2, premiereDate: nextSeasonPremiere, endDate: nil,
                    episodeOrder: nil))
        }
        return Show(
            id: id, name: "Show \(id)", tvMazeURL: nil, summaryHTML: nil,
            posterMediumURL: nil, posterOriginalURL: nil, status: .running,
            premiered: nil, ended: nil, network: nil, genres: [], averageRuntime: nil,
            seasons: seasons, nextEpisode: nil, updatedAt: .now)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "SubscriptionDowngradeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makePurchases(
        store: StubPurchaseStoreClient,
        initial: StoreEntitlementState? = nil,
        defaults: UserDefaults? = nil
    ) -> PurchaseService {
        PurchaseService(
            store: store,
            entitlementStore: PlusEntitlementStore(
                userDefaults: defaults ?? isolatedDefaults(),
                persistence: MemoryComplimentaryPlusPersistence()),
            initialStoreEntitlement: initial ?? .resolved(isEntitled: store.isStoreEntitled),
            simulationAvailability: { true }
        )
    }

    private func makeReconciler(
        repository: any WatchlistRepository,
        purchases: PurchaseService,
        defaults: UserDefaults? = nil,
        refreshAfterResume: @escaping @MainActor (Set<Int>) async -> Void = { _ in }
    ) -> WatchlistAccessReconciler {
        WatchlistAccessReconciler(
            repository: repository,
            userDefaults: defaults ?? isolatedDefaults(),
            access: { purchases.confirmedWatchlistAccess },
            refreshAfterResume: refreshAfterResume
        )
    }

    /// Adds shows in ID order so `dateAdded` order matches ID order.
    private func seed(_ ids: [Int], into repository: InMemoryWatchlistRepository) async throws {
        for id in ids { try await repository.add(show(id)) }
    }

    private func pausedIDs(_ repository: any WatchlistRepository) async throws -> Set<Int> {
        Set(try await repository.all().filter(\.isPaused).map(\.id))
    }

    private func add(
        _ show: Show,
        repository: any WatchlistRepository,
        purchases: PurchaseService
    ) async throws -> WatchlistTracking.ToggleOutcome {
        let analytics = RecordingAnalyticsService()
        return try await WatchlistTracking.add(
            show,
            source: .search,
            repository: repository,
            tvMaze: MockTVMazeService(),
            analytics: analytics,
            notifications: NotificationService(
                userDefaults: isolatedDefaults(),
                authorizationStatusForTesting: .denied,
                analytics: analytics),
            prompt: WatchlistNotificationPromptState(),
            purchases: purchases
        )
    }

    /// Plus user with shows 1…5 (1 oldest) who then loses Plus.
    private func lapsedFixture() async throws -> (
        InMemoryWatchlistRepository, StubPurchaseStoreClient, PurchaseService,
        WatchlistAccessReconciler
    ) {
        let repository = InMemoryWatchlistRepository()
        try await seed([1, 2, 3, 4, 5], into: repository)
        let store = StubPurchaseStoreClient(isStoreEntitled: true)
        let purchases = makePurchases(store: store)
        let reconciler = makeReconciler(repository: repository, purchases: purchases)
        #expect(await reconciler.reconcile() == .unchanged)

        store.isStoreEntitled = false
        await purchases.refreshEntitlements()
        #expect(await reconciler.reconcile() == .paused([4, 5]))
        return (repository, store, purchases, reconciler)
    }

    // MARK: - Losing Plus

    @Test("Losing Plus keeps the three oldest shows active and pauses the rest")
    func lapseKeepsFirstThree() async throws {
        let (repository, _, _, reconciler) = try await lapsedFixture()

        #expect(try await repository.all().count == 5)
        #expect(try await repository.activeShowIDs() == [1, 2, 3])
        #expect(try await pausedIDs(repository) == [4, 5])
        #expect(try await repository.contains(showID: 4), "Paused shows are still saved")
        #expect(reconciler.isPausedAlertPending)
    }

    @Test("Reconciling again after a lapse changes nothing")
    func reconcileIsIdempotent() async throws {
        let (repository, _, _, reconciler) = try await lapsedFixture()
        #expect(await reconciler.reconcile() == .unchanged)
        #expect(try await pausedIDs(repository) == [4, 5])
    }

    @Test("A free user at or under the limit is never paused")
    func freeUserUnderLimitUnaffected() async throws {
        let repository = InMemoryWatchlistRepository()
        try await seed([1, 2, 3], into: repository)
        let purchases = makePurchases(store: StubPurchaseStoreClient(isStoreEntitled: false))
        let reconciler = makeReconciler(repository: repository, purchases: purchases)

        #expect(await reconciler.reconcile() == .unchanged)
        #expect(reconciler.isPausedAlertPending == false)
    }

    // MARK: - Entitlement certainty

    /// Canceling auto-renew keeps the subscription in `Transaction.currentEntitlements`
    /// until it expires (as does a billing grace period), so StoreKit still reports
    /// Plus as active and nothing is paused.
    @Test("Canceling renewal while still entitled does not pause shows")
    func cancelledRenewalStillEntitled() async throws {
        let repository = InMemoryWatchlistRepository()
        try await seed([1, 2, 3, 4, 5], into: repository)
        let store = StubPurchaseStoreClient(isStoreEntitled: true)
        let purchases = makePurchases(store: store)
        let reconciler = makeReconciler(repository: repository, purchases: purchases)

        await purchases.refreshEntitlements()
        #expect(await reconciler.reconcile() == .unchanged)
        #expect(try await repository.activeShowIDs().count == 5)
    }

    @Test("Shows are not paused while StoreKit is still loading")
    func loadingEntitlementDoesNotPause() async throws {
        let repository = InMemoryWatchlistRepository()
        try await seed([1, 2, 3, 4, 5], into: repository)
        let purchases = makePurchases(
            store: StubPurchaseStoreClient(isStoreEntitled: false), initial: .loading)
        let reconciler = makeReconciler(repository: repository, purchases: purchases)

        #expect(purchases.confirmedWatchlistAccess == nil)
        #expect(await reconciler.reconcile() == .unchanged)
        #expect(try await pausedIDs(repository).isEmpty)
    }

    @Test("An unverified entitlement on first read does not pause shows")
    func unverifiedFirstReadDoesNotPause() async throws {
        let repository = InMemoryWatchlistRepository()
        try await seed([1, 2, 3, 4, 5], into: repository)
        let store = StubPurchaseStoreClient(isStoreEntitled: false)
        store.reportsUnverifiedEntitlement = true
        let purchases = makePurchases(store: store, initial: .loading)
        let reconciler = makeReconciler(repository: repository, purchases: purchases)

        await purchases.refreshEntitlements()
        #expect(purchases.storeEntitlement == .unverified)
        #expect(purchases.hasResolvedStoreEntitlement, "Adds must not wait forever")
        #expect(purchases.isUnlimitedWatchlist == false, "Unverified never grants Plus")
        #expect(purchases.confirmedWatchlistAccess == nil)
        #expect(await reconciler.reconcile() == .unchanged)
        #expect(try await pausedIDs(repository).isEmpty)
    }

    @Test("A verification failure after confirmed Plus keeps Plus and pauses nothing")
    func unverifiedAfterEntitledKeepsPlus() async throws {
        let repository = InMemoryWatchlistRepository()
        try await seed([1, 2, 3, 4, 5], into: repository)
        let store = StubPurchaseStoreClient(isStoreEntitled: true)
        let purchases = makePurchases(store: store)
        let reconciler = makeReconciler(repository: repository, purchases: purchases)

        store.reportsUnverifiedEntitlement = true
        await purchases.refreshEntitlements()
        #expect(purchases.storeEntitlement == .resolved(isEntitled: true))
        #expect(await reconciler.reconcile() == .unchanged)
        #expect(try await pausedIDs(repository).isEmpty)
    }

    // MARK: - Free-tier slots

    @Test("Deleting an active show frees a slot without activating a paused show")
    func deleteFreesSlotWithoutAutoActivation() async throws {
        let (repository, _, _, reconciler) = try await lapsedFixture()

        try await repository.remove(showID: 2)
        #expect(await reconciler.reconcile() == .unchanged)
        #expect(try await repository.activeShowIDs() == [1, 3])
        #expect(try await pausedIDs(repository) == [4, 5])
    }

    @Test("Adding a new show fills the free slot")
    func addNewShowFillsSlot() async throws {
        let (repository, _, purchases, reconciler) = try await lapsedFixture()
        try await repository.remove(showID: 2)

        #expect(try await add(show(6), repository: repository, purchases: purchases) == .added)
        #expect(try await repository.activeShowIDs() == [1, 3, 6])
        #expect(await reconciler.reconcile() == .unchanged)
    }

    @Test("Adding a paused show reactivates the saved row without a duplicate")
    func addPausedShowReactivates() async throws {
        let (repository, _, purchases, _) = try await lapsedFixture()
        let originalDateAdded = try #require(try await repository.trackedShow(showID: 5))
            .dateAdded
        try await repository.remove(showID: 2)

        #expect(try await add(show(5), repository: repository, purchases: purchases) == .added)
        #expect(try await repository.all().count == 4)
        let reactivated = try #require(try await repository.trackedShow(showID: 5))
        #expect(reactivated.isPaused == false)
        #expect(reactivated.dateAdded == originalDateAdded)
        #expect(try await repository.activeShowIDs() == [1, 3, 5])
        #expect(try await pausedIDs(repository) == [4])
    }

    @Test("A fourth active show requires the paywall, including for paused shows")
    func fourthActiveShowRequiresPaywall() async throws {
        let (repository, _, purchases, _) = try await lapsedFixture()

        #expect(
            try await add(show(6), repository: repository, purchases: purchases)
                == .paywallRequired)
        #expect(
            try await add(show(4), repository: repository, purchases: purchases)
                == .paywallRequired)
        #expect(try await repository.contains(showID: 6) == false)
        #expect(try await pausedIDs(repository) == [4, 5])
    }

    @Test("Search and Detail treat paused shows as not tracked")
    func pausedShowsAreNotTrackedForStars() async throws {
        let (repository, _, _, _) = try await lapsedFixture()
        let tracked = try await WatchlistTrackingState.trackedIDs(
            repository: repository, removalCoordinator: nil)
        #expect(tracked == [1, 2, 3])
        #expect(
            try await WatchlistTrackingState.isTracked(
                showID: 4, repository: repository, removalCoordinator: nil) == false)
    }

    // MARK: - Restoring Plus

    @Test("Restoring Plus reactivates every saved show")
    func restoringPlusResumesAll() async throws {
        let (repository, store, purchases, reconciler) = try await lapsedFixture()

        store.isStoreEntitled = true
        await purchases.refreshEntitlements()
        #expect(await reconciler.reconcile() == .resumed([4, 5]))
        #expect(try await repository.activeShowIDs() == [1, 2, 3, 4, 5])
        #expect(reconciler.isPausedAlertPending == false)
    }

    @Test("Reactivation is persisted before, and independent of, the follow-up refresh")
    func reactivationDoesNotDependOnRefresh() async throws {
        let repository = InMemoryWatchlistRepository()
        try await seed([1, 2, 3, 4, 5], into: repository)
        let store = StubPurchaseStoreClient(isStoreEntitled: false)
        let purchases = makePurchases(store: store)
        let tvMaze = MockTVMazeService()
        tvMaze.failsUpdates = true  // Every show fetch fails too (no stubbed shows).
        let refreshService = WatchlistRefreshService(
            tvMaze: tvMaze, repository: repository, notifications: RecordingNotifications(),
            analytics: RecordingAnalyticsService())
        var activeCountWhenRefreshStarted: Int?
        let reconciler = makeReconciler(repository: repository, purchases: purchases) { ids in
            activeCountWhenRefreshStarted = try? await repository.activeShowIDs().count
            await refreshService.refreshAll(
                force: true, deliverNotifications: false, onlyShowIDs: ids)
        }
        _ = await reconciler.reconcile()
        #expect(try await pausedIDs(repository) == [4, 5])

        store.isStoreEntitled = true
        await purchases.refreshEntitlements()
        #expect(await reconciler.reconcile() == .resumed([4, 5]))
        #expect(try await repository.activeShowIDs().count == 5)

        // Wait for the unawaited catch-up; its failures must not undo reactivation.
        await reconciler.catchUpTask?.value
        #expect(activeCountWhenRefreshStarted == 5)
        #expect(try await repository.activeShowIDs().count == 5)
    }

    // MARK: - Simulate Free Tier

    @Test("Simulation pauses through the same reconciliation and turning it off resumes")
    func simulationPausesAndResumes() async throws {
        let repository = InMemoryWatchlistRepository()
        try await seed([1, 2, 3, 4, 5], into: repository)
        let purchases = makePurchases(store: StubPurchaseStoreClient(isStoreEntitled: true))
        let reconciler = makeReconciler(repository: repository, purchases: purchases)

        purchases.setFreeTierSimulation(true)
        #expect(await reconciler.reconcile() == .paused([4, 5]))

        purchases.setFreeTierSimulation(false)
        #expect(await reconciler.reconcile() == .resumed([4, 5]))
        #expect(try await pausedIDs(repository).isEmpty)
    }

    @Test("After a restart that ends simulation, valid Plus resumes paused shows")
    func simulationEndedByRestartResumes() async throws {
        let repository = InMemoryWatchlistRepository()
        try await seed([1, 2, 3, 4, 5], into: repository)
        let defaults = isolatedDefaults()
        let firstLaunch = makePurchases(store: StubPurchaseStoreClient(isStoreEntitled: true))
        firstLaunch.setFreeTierSimulation(true)
        _ = await makeReconciler(
            repository: repository, purchases: firstLaunch, defaults: defaults
        ).reconcile()
        #expect(try await pausedIDs(repository) == [4, 5])

        // New process: simulation is session-only; StoreKit starts loading.
        let store = StubPurchaseStoreClient(isStoreEntitled: true)
        let secondLaunch = makePurchases(store: store, initial: .loading)
        let reconciler = makeReconciler(
            repository: repository, purchases: secondLaunch, defaults: defaults)
        #expect(await reconciler.reconcile() == .unchanged, "Waits for StoreKit")

        await secondLaunch.refreshEntitlements()
        #expect(await reconciler.reconcile() == .resumed([4, 5]))
    }

    // MARK: - Repeated lapses

    /// Documents the rule in `WatchlistLimitPolicy.showIDsToPause`: a later lapse
    /// keeps the three oldest surviving shows by original `dateAdded`; choices made
    /// during an earlier free period are not remembered.
    @Test("A second lapse keeps the three oldest surviving shows")
    func repeatedLapseIsDeterministic() async throws {
        let (repository, store, purchases, reconciler) = try await lapsedFixture()

        // Free period: delete 1, reactivate 5 into the freed slot. Active: 2, 3, 5.
        try await repository.remove(showID: 1)
        #expect(try await add(show(5), repository: repository, purchases: purchases) == .added)
        #expect(try await repository.activeShowIDs() == [2, 3, 5])

        store.isStoreEntitled = true
        await purchases.refreshEntitlements()
        #expect(await reconciler.reconcile() == .resumed([4]))

        store.isStoreEntitled = false
        await purchases.refreshEntitlements()
        #expect(await reconciler.reconcile() == .paused([5]))
        #expect(try await repository.activeShowIDs() == [2, 3, 4])
    }

    // MARK: - Alert

    @Test("The paused alert persists until acknowledged")
    func pausedAlertPersists() async throws {
        let repository = InMemoryWatchlistRepository()
        try await seed([1, 2, 3, 4], into: repository)
        let defaults = isolatedDefaults()
        let purchases = makePurchases(store: StubPurchaseStoreClient(isStoreEntitled: false))
        _ = await makeReconciler(
            repository: repository, purchases: purchases, defaults: defaults
        ).reconcile()

        let relaunched = makeReconciler(
            repository: repository, purchases: purchases, defaults: defaults)
        #expect(relaunched.isPausedAlertPending)
        relaunched.acknowledgePausedAlert()
        #expect(
            makeReconciler(repository: repository, purchases: purchases, defaults: defaults)
                .isPausedAlertPending == false)
    }

    // MARK: - Refresh and notifications

    @Test("Refresh skips paused shows: no fetch and no notification")
    func refreshExcludesPausedShows() async throws {
        let (repository, _, _, _) = try await lapsedFixture()
        let tvMaze = MockTVMazeService()
        let upcoming = Calendar.current.date(byAdding: .day, value: 30, to: .now)
        for id in 1...5 { tvMaze.showByID[id] = show(id, nextSeasonPremiere: upcoming) }
        let notifications = RecordingNotifications()
        let refreshService = WatchlistRefreshService(
            tvMaze: tvMaze, repository: repository, notifications: notifications,
            analytics: RecordingAnalyticsService())

        await refreshService.refreshAll(force: true)

        #expect(Set(tvMaze.fetchedShowIDs) == [1, 2, 3])
        #expect(Set(notifications.delivered.map(\.showID)) == [1, 2, 3])
        #expect(try await pausedIDs(repository) == [4, 5], "Refresh never un-pauses")
    }

    // MARK: - Opening paused shows

    @Test("A notification for a paused show opens the Watchlist, not detail")
    func notificationForPausedShowOpensWatchlistOnly() async throws {
        let (repository, _, _, _) = try await lapsedFixture()
        let tvMaze = MockTVMazeService()
        tvMaze.showByID[5] = show(5)
        let coordinator = AppNavigationCoordinator()
        coordinator.selectedTab = .search

        coordinator.queueShowNavigation(showID: 5)
        await coordinator.resolvePendingNavigation(
            repository: repository, tvMaze: tvMaze, analytics: RecordingAnalyticsService())

        #expect(coordinator.selectedTab == .watchlist)
        #expect(coordinator.pendingWatchlistDetail == nil)
        #expect(coordinator.watchlistPath.isEmpty)
        #expect(coordinator.searchPath.isEmpty)
        #expect(tvMaze.fetchedShowIDs.isEmpty, "No fresh show details are loaded")
    }

    /// Regression: on cold launch StoreKit has not answered yet, so the show is
    /// still active in storage. Navigation must wait for entitlement + reconcile
    /// instead of opening detail for a show that is about to be paused.
    @Test("Cold-launch notification waits for reconciliation before choosing detail")
    func coldLaunchNotificationUsesReconciledState() async throws {
        let repository = InMemoryWatchlistRepository()
        try await seed([1, 2, 3, 4, 5], into: repository)
        let store = StubPurchaseStoreClient(isStoreEntitled: false)
        store.delayEntitlementResolution = true
        let purchases = makePurchases(store: store, initial: .loading)
        let reconciler = WatchlistAccessReconciler(
            repository: repository,
            userDefaults: isolatedDefaults(),
            access: { purchases.confirmedWatchlistAccess },
            waitForAccess: { await purchases.waitForInitialEntitlementResolution() }
        )
        let coordinator = AppNavigationCoordinator()
        coordinator.selectedTab = .search
        let tvMaze = MockTVMazeService()
        tvMaze.showByID[5] = show(5)

        // Launch: the StoreKit read starts and suspends.
        let entitlementRead = Task { await purchases.refreshEntitlements() }
        coordinator.queueShowNavigation(showID: 5)
        let navigation = Task {
            await coordinator.resolvePendingNavigation(
                repository: repository, tvMaze: tvMaze, analytics: RecordingAnalyticsService(),
                prepare: { await reconciler.reconcileWhenAccessKnown() })
        }
        for _ in 0..<10 { await Task.yield() }
        #expect(coordinator.pendingWatchlistDetail == nil, "No decision before StoreKit answers")
        #expect(coordinator.selectedTab == .search)

        store.releaseEntitlementResolution()
        await entitlementRead.value
        await navigation.value

        #expect(try await repository.trackedShow(showID: 5)?.isPaused == true)
        #expect(coordinator.selectedTab == .watchlist)
        #expect(coordinator.pendingWatchlistDetail == nil)
        #expect(coordinator.searchPath.isEmpty)
        #expect(tvMaze.fetchedShowIDs.isEmpty)
    }

    @Test("Cold-launch notification for a show that stays active still opens detail")
    func coldLaunchNotificationForActiveShowOpensDetail() async throws {
        let repository = InMemoryWatchlistRepository()
        try await seed([1, 2, 3, 4, 5], into: repository)
        let store = StubPurchaseStoreClient(isStoreEntitled: false)
        store.delayEntitlementResolution = true
        let purchases = makePurchases(store: store, initial: .loading)
        let reconciler = WatchlistAccessReconciler(
            repository: repository,
            userDefaults: isolatedDefaults(),
            access: { purchases.confirmedWatchlistAccess },
            waitForAccess: { await purchases.waitForInitialEntitlementResolution() }
        )
        let coordinator = AppNavigationCoordinator()

        let entitlementRead = Task { await purchases.refreshEntitlements() }
        coordinator.queueShowNavigation(showID: 1)
        let navigation = Task {
            await coordinator.resolvePendingNavigation(
                repository: repository, tvMaze: MockTVMazeService(),
                analytics: RecordingAnalyticsService(),
                prepare: { await reconciler.reconcileWhenAccessKnown() })
        }
        for _ in 0..<10 { await Task.yield() }
        store.releaseEntitlementResolution()
        await entitlementRead.value
        await navigation.value

        #expect(coordinator.pendingWatchlistDetail?.id == 1)
    }

    @Test("Restoring Plus clears a pending alert even if no paused shows remain")
    func restoringPlusClearsAlertWithoutPausedShows() async throws {
        let (repository, store, purchases, reconciler) = try await lapsedFixture()
        #expect(reconciler.shouldPresentPausedAlert)
        try await repository.remove(showID: 4)
        try await repository.remove(showID: 5)

        store.isStoreEntitled = true
        await purchases.refreshEntitlements()
        #expect(reconciler.shouldPresentPausedAlert == false, "Never shown once Plus is back")
        #expect(await reconciler.reconcile() == .unchanged)
        #expect(reconciler.isPausedAlertPending == false)
    }

    @Test("A persisted alert is not shown before StoreKit answers, and is cleared by Plus")
    func persistedAlertWaitsForConfirmedFreeAccess() async throws {
        let repository = InMemoryWatchlistRepository()
        try await seed([1, 2, 3, 4], into: repository)
        let defaults = isolatedDefaults()
        // Earlier session (e.g. background refresh) paused show 4.
        let earlier = makePurchases(store: StubPurchaseStoreClient(isStoreEntitled: false))
        _ = await makeReconciler(repository: repository, purchases: earlier, defaults: defaults)
            .reconcile()

        // Next launch: Plus was restored meanwhile; StoreKit still loading.
        let store = StubPurchaseStoreClient(isStoreEntitled: true)
        let purchases = makePurchases(store: store, initial: .loading)
        let reconciler = makeReconciler(
            repository: repository, purchases: purchases, defaults: defaults)
        #expect(reconciler.isPausedAlertPending)
        #expect(reconciler.shouldPresentPausedAlert == false, "Unknown access: don't warn")

        await purchases.refreshEntitlements()
        #expect(reconciler.shouldPresentPausedAlert == false)
        #expect(await reconciler.reconcile() == .resumed([4]))
        #expect(reconciler.isPausedAlertPending == false)
    }

    @Test("Paused shows render only in the paused section, without season info")
    func pausedShowsSeparatedFromStatusSections() async throws {
        let (repository, _, _, reconciler) = try await lapsedFixture()
        let viewModel = WatchlistViewModel(
            repository: repository,
            removalCoordinator: WatchlistPendingRemoval(
                repository: repository, analytics: RecordingAnalyticsService()),
            analytics: RecordingAnalyticsService(),
            accessReconciler: reconciler
        )
        await viewModel.reload()

        let sectionIDs = Set(viewModel.filteredSectionGroups.flatMap(\.shows).map(\.id))
        #expect(sectionIDs == [1, 2, 3])
        #expect(Set(viewModel.filteredPausedShows.map(\.id)) == [4, 5])

        let label = ShowRowLabel(tracked: viewModel.filteredPausedShows[0])
        #expect(label.isPaused)
        #expect(label.subtitle == String(localized: "Paused"))
        #expect(label.footer == nil, "No stale last-checked time")
    }

    @Test("Watchlist load reconciles before reading rows")
    func reloadReconciles() async throws {
        let repository = InMemoryWatchlistRepository()
        try await seed([1, 2, 3, 4], into: repository)
        let purchases = makePurchases(store: StubPurchaseStoreClient(isStoreEntitled: false))
        let viewModel = WatchlistViewModel(
            repository: repository,
            removalCoordinator: WatchlistPendingRemoval(
                repository: repository, analytics: RecordingAnalyticsService()),
            analytics: RecordingAnalyticsService(),
            accessReconciler: makeReconciler(repository: repository, purchases: purchases)
        )
        await viewModel.reload()
        #expect(viewModel.filteredPausedShows.map(\.id) == [4])
    }

    @Test("Undoing the delete of a paused show restores it paused")
    func undoDeletePausedShowStaysPaused() async throws {
        let (repository, _, _, _) = try await lapsedFixture()
        let removal = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        let paused = try #require(try await repository.trackedShow(showID: 4))

        removal.requestImmediateRemoval(paused, source: .watchlist)
        var attempts = 0
        while try await repository.contains(showID: 4), attempts < 20 {
            attempts += 1
            await Task.yield()
        }
        #expect(try await repository.contains(showID: 4) == false)

        _ = await removal.undoRemoval()
        #expect(try await repository.trackedShow(showID: 4)?.isPaused == true)
        #expect(try await repository.activeShowIDs() == [1, 2, 3])
    }
}

/// SwiftData repository: pause flag persistence and query semantics.
@MainActor
struct SwiftDataPausedWatchlistTests {
    private func makeRepository() throws -> (SwiftDataWatchlistRepository, ModelContainer) {
        let container = try NextSeasonModelContainer.make(
            configuration: ModelConfiguration(
                "paused-watchlist-\(UUID().uuidString)", isStoredInMemoryOnly: true))
        return (SwiftDataWatchlistRepository(context: ModelContext(container)), container)
    }

    private func show(_ id: Int) -> Show {
        Show(
            id: id, name: "Show \(id)", tvMazeURL: nil, summaryHTML: nil,
            posterMediumURL: nil, posterOriginalURL: nil, status: .running,
            premiered: nil, ended: nil, network: nil, genres: [], averageRuntime: nil,
            seasons: [], nextEpisode: nil, updatedAt: .now)
    }

    @Test("Pause flags persist; saved queries include paused shows, active query does not")
    func pausePersistsAndQueriesDiffer() async throws {
        let (repository, container) = try makeRepository()
        for id in 1...4 { try await repository.add(show(id)) }
        try await repository.setPaused(true, showIDs: [4])

        let reopened = SwiftDataWatchlistRepository(context: ModelContext(container))
        #expect(try await reopened.trackedShowIDs() == [1, 2, 3, 4])
        #expect(try await reopened.contains(showID: 4))
        #expect(try await reopened.activeShowIDs() == [1, 2, 3])
        #expect(try await reopened.trackedShow(showID: 4)?.isPaused == true)
    }

    @Test("A refresh write never un-pauses a row")
    func refreshWriteKeepsPause() async throws {
        let (repository, _) = try makeRepository()
        try await repository.add(show(1))
        let loadedBeforePause = try #require(try await repository.trackedShow(showID: 1))
        try await repository.setPaused(true, showIDs: [1])

        try await repository.updateAfterRefresh(loadedBeforePause)
        #expect(try await repository.trackedShow(showID: 1)?.isPaused == true)
    }

    @Test("Adding a paused show reactivates it in place, keeping dateAdded")
    func addReactivatesInPlace() async throws {
        let (repository, _) = try makeRepository()
        try await repository.add(show(1))
        let original = try #require(try await repository.trackedShow(showID: 1))
        try await repository.setPaused(true, showIDs: [1])

        try await repository.add(show(1))
        let reactivated = try #require(try await repository.trackedShow(showID: 1))
        #expect(try await repository.all().count == 1)
        #expect(reactivated.isPaused == false)
        #expect(reactivated.dateAdded == original.dateAdded)
    }

    /// Undo must restore the same saved row: free-tier order and the row's
    /// catch-up mark both depend on its original `dateAdded`.
    @Test("Undoing an immediate delete restores the original dateAdded")
    func undoRestoresOriginalDateAdded() async throws {
        let (repository, _) = try makeRepository()
        try await repository.add(show(1))
        let original = try #require(try await repository.trackedShow(showID: 1))
        let removal = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())

        await withCheckedContinuation { (committed: CheckedContinuation<Void, Never>) in
            removal.addOutcomeHandler { outcome in
                if case .committed(let id) = outcome, id == 1 { committed.resume() }
            }
            removal.requestImmediateRemoval(original, source: .watchlist)
        }
        #expect(try await repository.contains(showID: 1) == false)

        _ = await removal.undoRemoval()
        #expect(try await repository.trackedShow(showID: 1)?.dateAdded == original.dateAdded)
    }
}
