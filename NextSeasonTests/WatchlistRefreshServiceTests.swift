//
//  WatchlistRefreshServiceTests.swift
//  NextSeasonTests
//

import Foundation
import Testing

@testable import NextSeason

@MainActor
struct WatchlistRefreshServiceTests {
    private let fixedNow = TVMazeDate.dateOnly("2026-06-14")!
    private let showID = 44933

    /// Captures delivered season notifications for assertions.
    private final class RecordingNotificationService: NotificationDelivering {
        private(set) var delivered: [SeasonNotificationContent] = []

        func deliver(_ content: SeasonNotificationContent) async -> NotificationDeliveryOutcome {
            delivered.append(content)
            return .accepted
        }
    }

    /// Stub TVMaze that records fetched show ids, cache bypass, and update period.
    private final class MockTVMazeService: TVMazeService, @unchecked Sendable {
        var updates: [Int: Date] = [:]
        var shows: [Int: Show] = [:]
        private(set) var fetchedShowIDs: [Int] = []
        private(set) var lastBypassCache: Bool?
        private(set) var lastUpdatePeriod: TVMazeUpdatePeriod?

        func searchShows(matching query: String) async throws -> [Show] { [] }

        func lookupShow(theTVDBID: Int) async throws -> Show {
            throw TVMazeError.notFound
        }

        func show(id: Int, bypassCache: Bool) async throws -> Show {
            fetchedShowIDs.append(id)
            lastBypassCache = bypassCache
            guard let show = shows[id] else { throw TVMazeError.notFound }
            return show
        }

        func updatedShows(since period: TVMazeUpdatePeriod) async throws -> [Int: Date] {
            lastUpdatePeriod = period
            return updates
        }

        private(set) var fullMapRequests = 0

        /// Same changed shows as the filtered map; the real full map also lists
        /// unchanged shows, which the refresh skips either way.
        func allUpdatedShows() async throws -> [Int: Date] {
            fullMapRequests += 1
            return updates
        }
    }

    private func season(_ number: Int, premiere: String?, end: String? = nil) -> Season {
        Season(
            id: number,
            number: number,
            premiereDate: TVMazeDate.dateOnly(premiere),
            endDate: TVMazeDate.dateOnly(end),
            episodeOrder: nil
        )
    }

    private func show(nextEpisode: NextEpisode? = nil, extraSeason: Season? = nil) -> Show {
        var seasons = [
            season(1, premiere: "2022-02-18", end: "2022-04-08"),
            season(2, premiere: "2025-01-17", end: "2025-03-21"),
        ]
        if let extraSeason { seasons.append(extraSeason) }

        return Show(
            id: showID,
            name: "Severance",
            tvMazeURL: nil,
            summaryHTML: nil,
            posterMediumURL: nil,
            posterOriginalURL: nil,
            status: .running,
            premiered: TVMazeDate.dateOnly("2022-02-18"),
            ended: nil,
            network: "Apple TV",
            genres: ["Drama"],
            averageRuntime: 49,
            seasons: seasons,
            nextEpisode: nextEpisode,
            updatedAt: fixedNow
        )
    }

    /// Refresh service wired to the suite's fixed clock.
    private func makeService(
        repository: InMemoryWatchlistRepository,
        tvMaze: MockTVMazeService,
        notifications: RecordingNotificationService,
        userDefaults: UserDefaults = isolatedDefaults()
    ) -> WatchlistRefreshService {
        makeService(
            repository: repository,
            tvMaze: tvMaze,
            notifications: notifications,
            userDefaults: userDefaults,
            clock: { fixedNow }
        )
    }

    /// Refresh service with an injectable clock (stale / cooldown tests).
    /// Each service gets its own defaults so the persisted coverage watermark
    /// and catch-up marks never leak between tests.
    private func makeService(
        repository: InMemoryWatchlistRepository,
        tvMaze: MockTVMazeService,
        notifications: RecordingNotificationService,
        userDefaults: UserDefaults = isolatedDefaults(),
        clock: @escaping @Sendable () -> Date
    ) -> WatchlistRefreshService {
        WatchlistRefreshService(
            tvMaze: tvMaze,
            repository: repository,
            notifications: notifications,
            analytics: RecordingAnalyticsService(),
            userDefaults: userDefaults,
            clock: clock
        )
    }

    /// Defaults with a coverage watermark `age` before the suite's fixed clock.
    private func defaults(coveredFor age: TimeInterval) -> UserDefaults {
        let defaults = isolatedDefaults()
        defaults.set(
            fixedNow.addingTimeInterval(-age).timeIntervalSinceReferenceDate,
            forKey: WatchlistRefreshService.updatesCoveredThroughKey)
        return defaults
    }

    @Test("Background refresh skips shows that did not change on TVMaze")
    func skipsUnchangedShowsInUpdatesMap() async throws {
        let repository = InMemoryWatchlistRepository()
        let tvMaze = MockTVMazeService()
        let notifications = RecordingNotificationService()

        let initial = show(extraSeason: season(3, premiere: nil))
        try await repository.add(initial)

        var tracked = try await repository.all()[0]
        tracked.sourceUpdatedAt = fixedNow
        try await repository.updateAfterRefresh(tracked)

        tvMaze.updates = [:]
        tvMaze.shows[showID] = initial

        await makeService(repository: repository, tvMaze: tvMaze, notifications: notifications)
            .refreshAll()

        #expect(tvMaze.fetchedShowIDs.isEmpty)
        #expect(notifications.delivered.isEmpty)
    }

    @Test("Background refresh re-fetches and notifies when TVMaze reports an update")
    func notifiesWhenUpdatesMapHasNewerEpoch() async throws {
        let repository = InMemoryWatchlistRepository()
        let tvMaze = MockTVMazeService()
        let notifications = RecordingNotificationService()

        let initial = show(extraSeason: season(3, premiere: nil))
        try await repository.add(initial)

        var tracked = try await repository.all()[0]
        tracked.sourceUpdatedAt = .distantPast
        try await repository.updateAfterRefresh(tracked)

        let premiere = TVMazeDate.dateOnly("2026-09-01")!
        let updated = show(extraSeason: season(3, premiere: "2026-09-01"))
        tvMaze.updates = [showID: fixedNow]
        tvMaze.shows[showID] = updated

        await makeService(repository: repository, tvMaze: tvMaze, notifications: notifications)
            .refreshAll()

        #expect(tvMaze.fetchedShowIDs == [showID])
        #expect(tvMaze.lastBypassCache == true)
        #expect(notifications.delivered.count == 1)
        #expect(notifications.delivered[0].status == .scheduled(season: 3, premiere: premiere))

        let stored = try await repository.all()[0]
        #expect(stored.nextSeason == .scheduled(season: 3, premiere: premiere))
    }

    @Test("Force refresh re-fetches every tracked show regardless of the updates map")
    func forceRefreshFetchesAllTrackedShows() async throws {
        let repository = InMemoryWatchlistRepository()
        let tvMaze = MockTVMazeService()
        let notifications = RecordingNotificationService()

        try await repository.add(show())
        try await repository.add(
            Show(
                id: 82,
                name: "Game of Thrones",
                tvMazeURL: nil,
                summaryHTML: nil,
                posterMediumURL: nil,
                posterOriginalURL: nil,
                status: .ended,
                premiered: nil,
                ended: nil,
                network: nil,
                genres: [],
                averageRuntime: nil,
                seasons: [],
                nextEpisode: nil,
                updatedAt: fixedNow
            )
        )

        tvMaze.updates = [:]
        tvMaze.shows[showID] = show()
        tvMaze.shows[82] = tvMaze.shows[showID]!

        await makeService(repository: repository, tvMaze: tvMaze, notifications: notifications)
            .refreshAll(force: true)

        #expect(Set(tvMaze.fetchedShowIDs) == Set([showID, 82]))
    }

    @Test("Force refresh recomputes next-season status even when TVMaze reports no update")
    func forceRefreshCorrectsStaleReturningStatus() async throws {
        let repository = InMemoryWatchlistRepository()
        let tvMaze = MockTVMazeService()
        let notifications = RecordingNotificationService()
        // Mid-season "now" so S2 is still airing.
        let airingNow = TVMazeDate.dateOnly("2026-06-14")!
        let service = makeService(
            repository: repository,
            tvMaze: tvMaze,
            notifications: notifications,
            clock: { airingNow }
        )

        // Simulate a search-track snapshot: Running, but nextSeason was computed
        // without season rows and stuck on returning.
        let searchStub = Show(
            id: showID,
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
            updatedAt: airingNow
        )
        try await repository.add(searchStub)

        var tracked = try await repository.all()[0]
        #expect(tracked.nextSeason == .returningNoSeasonYet)
        // TVMaze "updated" matches the stored epoch, so an updates-only refresh
        // would previously skip forever.
        tracked.sourceUpdatedAt = airingNow
        try await repository.updateAfterRefresh(tracked)

        let airingShow = Show(
            id: showID,
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
            seasons: [
                season(1, premiere: "2025-01-01", end: "2025-03-01"),
                season(2, premiere: "2026-06-01", end: "2026-08-01"),
            ],
            nextEpisode: nil,
            updatedAt: airingNow
        )
        tvMaze.updates = [:]
        tvMaze.shows[showID] = airingShow

        // Returning snapshots are re-checked even without a server `updated` bump.
        await service.refreshAll()
        #expect(tvMaze.fetchedShowIDs == [showID])
        #expect(try await repository.all()[0].nextSeason == .airing(season: 2))

        await service.refreshAll(force: true)
        #expect(tvMaze.fetchedShowIDs == [showID, showID])
        #expect(try await repository.all()[0].nextSeason == .airing(season: 2))
    }

    @Test("Interactive force refresh updates status without delivering notifications")
    func interactiveForceRefreshSuppressesNotifications() async throws {
        let repository = InMemoryWatchlistRepository()
        let tvMaze = MockTVMazeService()
        let notifications = RecordingNotificationService()
        let airingNow = TVMazeDate.dateOnly("2026-06-14")!
        let service = makeService(
            repository: repository,
            tvMaze: tvMaze,
            notifications: notifications,
            clock: { airingNow }
        )

        let searchStub = Show(
            id: showID,
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
            updatedAt: airingNow
        )
        try await repository.add(searchStub)

        tvMaze.shows[showID] = Show(
            id: showID,
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
            seasons: [
                season(1, premiere: "2025-01-01", end: "2025-03-01"),
                season(2, premiere: "2026-06-01", end: "2026-08-01"),
            ],
            nextEpisode: nil,
            updatedAt: airingNow
        )

        let outcome = await service.refreshAll(force: true, deliverNotifications: false)
        #expect(try await repository.all()[0].nextSeason == .airing(season: 2))
        #expect(notifications.delivered.isEmpty)
        #expect(outcome?.notificationDecision.contains("Suppressed") == true)
    }

    @Test("A 404 from TVMaze marks the tracked show stale without delivering a notification")
    func notFoundMarksShowStale() async throws {
        let repository = InMemoryWatchlistRepository()
        let tvMaze = MockTVMazeService()
        let notifications = RecordingNotificationService()

        try await repository.add(show())

        var tracked = try await repository.all()[0]
        tracked.sourceUpdatedAt = .distantPast
        try await repository.updateAfterRefresh(tracked)

        tvMaze.updates = [showID: fixedNow]
        tvMaze.shows = [:]

        await makeService(repository: repository, tvMaze: tvMaze, notifications: notifications)
            .refreshAll()

        let stored = try await repository.all()[0]
        #expect(stored.isStale)
        #expect(notifications.delivered.isEmpty)
    }

    @Test("Debounced changes notify only after a second refresh sees the same status")
    func debouncedChangeRequiresTwoRefreshCycles() async throws {
        let repository = InMemoryWatchlistRepository()
        let tvMaze = MockTVMazeService()
        let notifications = RecordingNotificationService()
        let service = makeService(
            repository: repository, tvMaze: tvMaze, notifications: notifications)

        let betweenSeasons = show()
        try await repository.add(betweenSeasons)

        var tracked = try await repository.all()[0]
        tracked.nextSeason = .returningNoSeasonYet
        tracked.sourceUpdatedAt = .distantPast
        try await repository.updateAfterRefresh(tracked)

        let announced = show(extraSeason: season(3, premiere: nil))
        tvMaze.updates = [showID: fixedNow]
        tvMaze.shows[showID] = announced

        await service.refreshAll()
        #expect(notifications.delivered.isEmpty)

        let pending = try await repository.all()[0]
        #expect(
            pending.pendingChangeSignature
                == StatusChangeDetector.signature(for: .announcedUndated(season: 3)))

        await service.refreshAll(force: true)
        #expect(notifications.delivered.count == 1)
        #expect(notifications.delivered[0].status == .announcedUndated(season: 3))
    }

    @Test("Background refresh uses a week window when coverage is more than a day old")
    func usesWeekWindowAfterDayGap() async throws {
        let repository = InMemoryWatchlistRepository()
        let tvMaze = MockTVMazeService()
        let notifications = RecordingNotificationService()

        try await repository.add(show())

        tvMaze.updates = [:]
        await makeService(
            repository: repository, tvMaze: tvMaze, notifications: notifications,
            userDefaults: defaults(coveredFor: 2 * 86_400)
        ).refreshAll()

        #expect(tvMaze.lastUpdatePeriod == .week)
        #expect(tvMaze.fullMapRequests == 0)
    }

    @Test("Background refresh uses a month window when coverage is more than a week old")
    func usesMonthWindowAfterWeekGap() async throws {
        let repository = InMemoryWatchlistRepository()
        let tvMaze = MockTVMazeService()
        let notifications = RecordingNotificationService()

        try await repository.add(show())

        tvMaze.updates = [:]
        await makeService(
            repository: repository, tvMaze: tvMaze, notifications: notifications,
            userDefaults: defaults(coveredFor: 8 * 86_400)
        ).refreshAll()

        #expect(tvMaze.lastUpdatePeriod == .month)
        #expect(tvMaze.fullMapRequests == 0)
    }

    @Test("Foreground refresh skips network work when a refresh just ran")
    func skipsImmediateForegroundRefresh() async throws {
        final class NowBox: @unchecked Sendable {
            var date: Date
            init(_ date: Date) { self.date = date }
        }

        let nowBox = NowBox(fixedNow)
        let repository = InMemoryWatchlistRepository()
        let tvMaze = MockTVMazeService()
        let notifications = RecordingNotificationService()
        let service = makeService(
            repository: repository,
            tvMaze: tvMaze,
            notifications: notifications,
            clock: { nowBox.date }
        )

        try await repository.add(show())
        tvMaze.shows[showID] = show()
        tvMaze.updates = [showID: fixedNow.addingTimeInterval(60)]

        await service.refreshAllIfNeeded()
        #expect(tvMaze.fetchedShowIDs.count == 1)

        await service.refreshAllIfNeeded()
        #expect(tvMaze.fetchedShowIDs.count == 1)

        nowBox.date = fixedNow.addingTimeInterval(16 * 60)
        await service.refreshAllIfNeeded()
        #expect(tvMaze.fetchedShowIDs.count == 2)
    }
}

private func isolatedDefaults() -> UserDefaults {
    let suiteName = "WatchlistRefreshServiceTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
