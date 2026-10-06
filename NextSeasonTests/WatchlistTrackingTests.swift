//
//  WatchlistTrackingTests.swift
//  NextSeasonTests
//

import CoreGraphics
import Foundation
import Testing
import UserNotifications

@testable import NextSeason

/// Shared watchlist toggle/add paths: undo removal, detail fetch for search stubs, Plus
/// paywall, complimentary access, and StoreKit entitlement loading races.
@MainActor
struct WatchlistTrackingTests {
    private var sampleShow: Show {
        Show(
            id: 44933,
            name: "Severance",
            tvMazeURL: nil,
            summaryHTML: nil,
            posterMediumURL: nil,
            posterOriginalURL: nil,
            status: .running,
            premiered: nil,
            ended: nil,
            network: nil,
            genres: [],
            averageRuntime: nil,
            seasons: [],
            nextEpisode: nil,
            updatedAt: .now
        )
    }

    /// TVMaze stub recording fetched show ids and serving preloaded full-show payloads.
    private final class MockTVMazeService: TVMazeService, @unchecked Sendable {
        var showByID: [Int: Show] = [:]
        private(set) var fetchedShowIDs: [Int] = []

        func searchShows(matching query: String) async throws -> [Show] { [] }

        func lookupShow(theTVDBID: Int) async throws -> Show {
            throw TVMazeError.notFound
        }

        func show(id: Int, bypassCache: Bool) async throws -> Show {
            fetchedShowIDs.append(id)
            guard let show = showByID[id] else { throw TVMazeError.notFound }
            return show
        }

        func updatedShows(since period: TVMazeUpdatePeriod) async throws -> [Int: Date] { [:] }
    }

    /// Notification service with isolated defaults and `.denied` authorization for toggle tests.
    private func makeNotificationService(analytics: any AnalyticsTracking) -> NotificationService {
        let suiteName = "WatchlistTrackingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return NotificationService(
            userDefaults: defaults,
            authorizationStatusForTesting: .denied,
            analytics: analytics
        )
    }

    private func season(_ number: Int, premiere: Date?, end: Date? = nil) -> Season {
        Season(
            id: number,
            number: number,
            premiereDate: premiere,
            endDate: end,
            episodeOrder: nil
        )
    }

    /// UTC calendar-day offset so fixtures stay aligned with `TVMazeDate` comparisons
    /// and with `TrackedShow(from:)` which evaluates status at `Date.now`.
    private func utcDayOffset(_ days: Int, from date: Date = .now) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    @Test("Toggle with a missing undo coordinator returns ignored without mutating persistence")
    func toggleWithoutCoordinatorReturnsIgnored() async throws {
        let repository = InMemoryWatchlistRepository()
        let analytics = RecordingAnalyticsService()
        let tvMaze = MockTVMazeService()
        try await repository.add(sampleShow)

        let outcome = try await WatchlistTracking.toggle(
            sampleShow,
            isTracked: true,
            anchor: .zero,
            source: .search,
            repository: repository,
            tvMaze: tvMaze,
            removalCoordinator: nil,
            analytics: analytics,
            notifications: makeNotificationService(analytics: analytics),
            prompt: WatchlistNotificationPromptState(),
            purchases: .stub()
        )

        #expect(outcome == .ignored)
        #expect(try await repository.contains(showID: sampleShow.id))
        #expect(analytics.events.isEmpty)
        #expect(tvMaze.fetchedShowIDs.isEmpty)
    }

    @Test("A second quick tap while removal is pending undoes that removal")
    func secondTapUndoesPendingRemoval() async throws {
        let repository = InMemoryWatchlistRepository()
        let analytics = RecordingAnalyticsService()
        let removalCoordinator = WatchlistPendingRemoval(
            repository: repository, analytics: analytics)
        let notifications = makeNotificationService(analytics: analytics)
        let prompt = WatchlistNotificationPromptState()
        let tvMaze = MockTVMazeService()
        try await repository.add(sampleShow)

        let first = try await WatchlistTracking.toggle(
            sampleShow,
            isTracked: true,
            anchor: .zero,
            source: .detail,
            repository: repository,
            tvMaze: tvMaze,
            removalCoordinator: removalCoordinator,
            analytics: analytics,
            notifications: notifications,
            prompt: prompt,
            purchases: .stub()
        )
        #expect(first == .removalRequested)
        #expect(removalCoordinator.pendingRemoval?.id == sampleShow.id)
        #expect(try await repository.contains(showID: sampleShow.id))

        let second = try await WatchlistTracking.toggle(
            sampleShow,
            isTracked: false,
            anchor: .zero,
            source: .detail,
            repository: repository,
            tvMaze: tvMaze,
            removalCoordinator: removalCoordinator,
            analytics: analytics,
            notifications: notifications,
            prompt: prompt,
            purchases: .stub()
        )

        #expect(second == .undidPendingRemoval)
        #expect(removalCoordinator.pendingRemoval == nil)
        #expect(try await repository.contains(showID: sampleShow.id))
        #expect(tvMaze.fetchedShowIDs.isEmpty)
    }

    @Test("Tracking a search stub fetches full show data before storing next-season status")
    func addFromSearchStubStoresResolvedNextSeason() async throws {
        let repository = InMemoryWatchlistRepository()
        let analytics = RecordingAnalyticsService()
        let tvMaze = MockTVMazeService()
        let now = Date.now

        let fullShow = Show(
            id: sampleShow.id,
            name: sampleShow.name,
            tvMazeURL: nil,
            summaryHTML: nil,
            posterMediumURL: nil,
            posterOriginalURL: nil,
            status: .running,
            premiered: nil,
            ended: nil,
            network: nil,
            genres: [],
            averageRuntime: nil,
            seasons: [
                season(
                    16, premiere: utcDayOffset(-400, from: now), end: utcDayOffset(-250, from: now)),
                season(
                    17, premiere: utcDayOffset(-120, from: now), end: utcDayOffset(120, from: now)),
            ],
            nextEpisode: NextEpisode(
                season: 17,
                airdate: utcDayOffset(4, from: now)
            ),
            updatedAt: now
        )
        tvMaze.showByID[fullShow.id] = fullShow

        // Search stubs have no seasons; without a detail fetch they would store
        // `.returningNoSeasonYet` even while a season is still airing.
        #expect(NextSeasonCalculator.status(for: sampleShow, at: now) == .returningNoSeasonYet)
        #expect(NextSeasonCalculator.status(for: fullShow, at: now) == .airing(season: 17))

        let outcome = try await WatchlistTracking.toggle(
            sampleShow,
            isTracked: false,
            anchor: .zero,
            source: .search,
            repository: repository,
            tvMaze: tvMaze,
            removalCoordinator: nil,
            analytics: analytics,
            notifications: makeNotificationService(analytics: analytics),
            prompt: WatchlistNotificationPromptState(),
            purchases: .stub()
        )

        #expect(outcome == .added)
        #expect(tvMaze.fetchedShowIDs == [sampleShow.id])

        let tracked = try #require(await repository.trackedShow(showID: sampleShow.id))
        #expect(tracked.nextSeason == .airing(season: 17))
    }

    @Test("Tracking a show that already has seasons skips the detail fetch")
    func addWithSeasonsSkipsDetailFetch() async throws {
        let repository = InMemoryWatchlistRepository()
        let analytics = RecordingAnalyticsService()
        let tvMaze = MockTVMazeService()
        let now = Date.now

        let detailedShow = Show(
            id: sampleShow.id,
            name: sampleShow.name,
            tvMazeURL: nil,
            summaryHTML: nil,
            posterMediumURL: nil,
            posterOriginalURL: nil,
            status: .running,
            premiered: nil,
            ended: nil,
            network: nil,
            genres: [],
            averageRuntime: nil,
            seasons: [
                season(
                    17, premiere: utcDayOffset(-120, from: now), end: utcDayOffset(120, from: now))
            ],
            nextEpisode: nil,
            updatedAt: now
        )

        let outcome = try await WatchlistTracking.toggle(
            detailedShow,
            isTracked: false,
            anchor: .zero,
            source: .detail,
            repository: repository,
            tvMaze: tvMaze,
            removalCoordinator: nil,
            analytics: analytics,
            notifications: makeNotificationService(analytics: analytics),
            prompt: WatchlistNotificationPromptState(),
            purchases: .stub()
        )

        #expect(outcome == .added)
        #expect(tvMaze.fetchedShowIDs.isEmpty)

        let tracked = try #require(await repository.trackedShow(showID: sampleShow.id))
        #expect(tracked.nextSeason == .airing(season: 17))
    }

    @Test("Adding a fourth show without Plus returns paywallRequired and does not persist")
    func fourthShowRequiresPlus() async throws {
        let repository = InMemoryWatchlistRepository()
        let analytics = RecordingAnalyticsService()
        let tvMaze = MockTVMazeService()
        try await repository.add(show(id: 1))
        try await repository.add(show(id: 2))
        try await repository.add(show(id: 3))

        let outcome = try await WatchlistTracking.toggle(
            sampleShow,
            isTracked: false,
            anchor: .zero,
            source: .search,
            repository: repository,
            tvMaze: tvMaze,
            removalCoordinator: nil,
            analytics: analytics,
            notifications: makeNotificationService(analytics: analytics),
            prompt: WatchlistNotificationPromptState(),
            purchases: .stub()
        )

        #expect(outcome == .paywallRequired)
        #expect(try await repository.contains(showID: sampleShow.id) == false)
        #expect(tvMaze.fetchedShowIDs.isEmpty)
        #expect(analytics.events.isEmpty)
    }

    @Test("Plus entitlement allows adding past the free limit")
    func plusAllowsUnlimitedAdds() async throws {
        let repository = InMemoryWatchlistRepository()
        let analytics = RecordingAnalyticsService()
        try await repository.add(show(id: 1))
        try await repository.add(show(id: 2))
        try await repository.add(show(id: 3))

        let detailed = Show(
            id: sampleShow.id,
            name: sampleShow.name,
            tvMazeURL: nil,
            summaryHTML: nil,
            posterMediumURL: nil,
            posterOriginalURL: nil,
            status: .running,
            premiered: nil,
            ended: nil,
            network: nil,
            genres: [],
            averageRuntime: nil,
            seasons: [season(1, premiere: utcDayOffset(-10))],
            nextEpisode: nil,
            updatedAt: .now
        )

        let outcome = try await WatchlistTracking.toggle(
            detailed,
            isTracked: false,
            anchor: .zero,
            source: .detail,
            repository: repository,
            tvMaze: MockTVMazeService(),
            removalCoordinator: nil,
            analytics: analytics,
            notifications: makeNotificationService(analytics: analytics),
            prompt: WatchlistNotificationPromptState(),
            purchases: .stub(isStoreEntitled: true)
        )

        #expect(outcome == .added)
        #expect(try await repository.contains(showID: sampleShow.id))
    }

    @Test("A lapsed user with more than three shows can still track existing shows")
    func lapsedUserKeepsExistingShows() async throws {
        let repository = InMemoryWatchlistRepository()
        try await repository.add(show(id: 1))
        try await repository.add(show(id: 2))
        try await repository.add(show(id: 3))
        try await repository.add(show(id: 4))

        #expect(try await repository.trackedShowIDs().count == 4)
        #expect(await PurchaseService.stub().canAddToWatchlist(currentCount: 4) == false)
        #expect(await PurchaseService.stub().canAddToWatchlist(currentCount: 2))
    }

    @Test("A Plus customer is not paywalled while StoreKit entitlement is still resolving")
    func delayedPlusEntitlementDoesNotPaywallAdd() async throws {
        let repository = InMemoryWatchlistRepository()
        let analytics = RecordingAnalyticsService()
        try await repository.add(show(id: 1))
        try await repository.add(show(id: 2))
        try await repository.add(show(id: 3))

        let store = StubPurchaseStoreClient(isStoreEntitled: true)
        store.delayEntitlementResolution = true
        let suiteName = "WatchlistTrackingTests.plusDelay.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let purchases = PurchaseService(
            store: store,
            entitlementStore: PlusEntitlementStore(
                userDefaults: defaults, persistence: MemoryComplimentaryPlusPersistence()),
            initialStoreEntitlement: .loading
        )

        let startTask = Task { await purchases.start(watchlistCount: 3) }
        await waitUntilEntitlementIsHeld(store)

        var outcome: WatchlistTracking.ToggleOutcome?
        let addTask = Task {
            outcome = try await WatchlistTracking.add(
                show(id: sampleShow.id),
                source: .search,
                repository: repository,
                tvMaze: MockTVMazeService(),
                analytics: analytics,
                notifications: makeNotificationService(analytics: analytics),
                prompt: WatchlistNotificationPromptState(),
                purchases: purchases
            )
        }
        for _ in 0..<50 { await Task.yield() }
        #expect(outcome == nil)
        #expect(purchases.storeEntitlement == .loading)

        store.releaseEntitlementResolution()
        await startTask.value
        try await addTask.value

        #expect(outcome == .added)
        #expect(try await repository.contains(showID: sampleShow.id))
        #expect(purchases.isStoreEntitled)
    }

    @Test("After Plus lapses, existing shows remain but adding another is blocked")
    func lapsedPlusBlocksNewAddsWithoutRemovingShows() async throws {
        let repository = InMemoryWatchlistRepository()
        let analytics = RecordingAnalyticsService()
        let store = StubPurchaseStoreClient(isStoreEntitled: true)
        let suiteName = "WatchlistTrackingTests.lapse.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let entitlementStore = PlusEntitlementStore(
            userDefaults: defaults, persistence: MemoryComplimentaryPlusPersistence())
        let purchases = PurchaseService(
            store: store,
            entitlementStore: entitlementStore,
            initialStoreEntitlement: .resolved(isEntitled: true)
        )
        await purchases.start(watchlistCount: 0)

        try await repository.add(show(id: 1))
        try await repository.add(show(id: 2))
        try await repository.add(show(id: 3))
        try await repository.add(show(id: 4))

        store.isStoreEntitled = false
        await purchases.refreshEntitlements()

        let outcome = try await WatchlistTracking.add(
            sampleShow,
            source: .search,
            repository: repository,
            tvMaze: MockTVMazeService(),
            analytics: analytics,
            notifications: makeNotificationService(analytics: analytics),
            prompt: WatchlistNotificationPromptState(),
            purchases: purchases
        )

        #expect(outcome == .paywallRequired)
        #expect(try await repository.trackedShowIDs().count == 4)
        #expect(try await repository.contains(showID: sampleShow.id) == false)
        #expect(purchases.isComplimentary == false)
    }

    /// Yields until delayed StoreKit entitlement resolution is suspended (see PurchaseServiceTests).
    private func waitUntilEntitlementIsHeld(_ store: StubPurchaseStoreClient) async {
        for _ in 0..<200 {
            if store.entitlementWaiterCount > 0 { return }
            await Task.yield()
        }
        Issue.record("StoreKit entitlement resolution did not suspend")
    }

    private func show(id: Int) -> Show {
        Show(
            id: id,
            name: "Show \(id)",
            tvMazeURL: nil,
            summaryHTML: nil,
            posterMediumURL: nil,
            posterOriginalURL: nil,
            status: .running,
            premiered: nil,
            ended: nil,
            network: nil,
            genres: [],
            averageRuntime: nil,
            seasons: [season(1, premiere: utcDayOffset(-10))],
            nextEpisode: nil,
            updatedAt: .now
        )
    }
}
