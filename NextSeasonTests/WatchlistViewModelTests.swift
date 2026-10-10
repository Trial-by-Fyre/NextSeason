//
//  WatchlistViewModelTests.swift
//  NextSeasonTests
//

import CoreGraphics
import Foundation
import Testing

@testable import NextSeason

/// Watchlist list UI model: reload, pending removal/undo, swipe delete, in-list search,
/// section grouping/sorting, and stale-reload generation discard.
@MainActor
struct WatchlistViewModelTests {
    private var sampleShow: Show {
        makeShow(id: 44933, name: "Severance")
    }

    private func makeShow(id: Int, name: String) -> Show {
        Show(
            id: id,
            name: name,
            tvMazeURL: URL(string: "https://www.tvmaze.com/shows/\(id)"),
            summaryHTML: "<p>A workplace thriller.</p>",
            posterMediumURL: nil,
            posterOriginalURL: nil,
            status: .running,
            premiered: TVMazeDate.dateOnly("2022-02-18"),
            ended: nil,
            network: "Apple TV",
            genres: ["Drama"],
            averageRuntime: 49,
            seasons: [],
            nextEpisode: nil,
            updatedAt: .now
        )
    }

    /// View model preloaded from an in-memory repository and already reloaded to `.loaded`.
    private func loadedViewModel(with shows: [Show]) async throws -> WatchlistViewModel {
        let repository = InMemoryWatchlistRepository()
        let removalCoordinator = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        let viewModel = WatchlistViewModel(
            repository: repository,
            removalCoordinator: removalCoordinator,
            analytics: RecordingAnalyticsService()
        )
        for show in shows {
            try await repository.add(show)
        }
        await viewModel.reload()
        return viewModel
    }

    private func trackedShow(
        id: Int,
        name: String,
        nextSeason: NextSeasonStatus
    ) -> TrackedShow {
        TrackedShow(
            id: id,
            name: name,
            posterMediumURL: nil,
            status: .running,
            nextSeason: nextSeason,
            sourceUpdatedAt: .now,
            lastCheckedAt: .now,
            dateAdded: .now
        )
    }

    @Test("Reload loads tracked shows from persistence")
    func reloadLoadsTrackedShows() async throws {
        let repository = InMemoryWatchlistRepository()
        let removalCoordinator = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        let viewModel = WatchlistViewModel(
            repository: repository,
            removalCoordinator: removalCoordinator,
            analytics: RecordingAnalyticsService()
        )
        try await repository.add(sampleShow)

        await viewModel.reload()

        #expect(viewModel.state == .loaded)
        #expect(viewModel.shows.count == 1)
        #expect(viewModel.shows[0].name == sampleShow.name)
    }

    @Test("A pending removal keeps the show visible in the loaded list")
    func pendingRemovalKeepsRowVisible() async throws {
        let repository = InMemoryWatchlistRepository()
        let removalCoordinator = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        let viewModel = WatchlistViewModel(
            repository: repository,
            removalCoordinator: removalCoordinator,
            analytics: RecordingAnalyticsService()
        )
        try await repository.add(sampleShow)
        await viewModel.reload()
        let tracked = try #require((try await repository.all()).first)

        viewModel.requestRemoval(tracked, anchor: .zero)

        #expect(viewModel.isPendingRemoval(tracked))
        #expect(viewModel.shows.count == 1)
        #expect(try await repository.contains(showID: tracked.id))
    }

    @Test("Committing a pending removal reloads an empty watchlist")
    func commitPendingRemovalReloadsList() async throws {
        let repository = InMemoryWatchlistRepository()
        let removalCoordinator = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        let viewModel = WatchlistViewModel(
            repository: repository,
            removalCoordinator: removalCoordinator,
            analytics: RecordingAnalyticsService()
        )
        try await repository.add(sampleShow)
        await viewModel.reload()
        let tracked = try #require((try await repository.all()).first)

        viewModel.requestRemoval(tracked, anchor: .zero)
        await viewModel.commitPendingRemovalIfNeeded()

        #expect(viewModel.state == .loaded)
        #expect(viewModel.shows.isEmpty)
        #expect(viewModel.pendingRemoval == nil)
    }

    @Test("Animated removal drops the row from the loaded list")
    func removeShowAnimatedDropsRow() async throws {
        let repository = InMemoryWatchlistRepository()
        let removalCoordinator = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        let viewModel = WatchlistViewModel(
            repository: repository,
            removalCoordinator: removalCoordinator,
            analytics: RecordingAnalyticsService()
        )
        try await repository.add(sampleShow)
        await viewModel.reload()
        let tracked = try #require((try await repository.all()).first)

        viewModel.removeShowAnimated(showID: tracked.id)

        #expect(viewModel.state == .loaded)
        #expect(viewModel.shows.isEmpty)
    }

    @Test("Committing a pending removal animates the row away via outcome")
    func commitPendingRemovalAnimatesRowAway() async throws {
        let repository = InMemoryWatchlistRepository()
        let removalCoordinator = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        let viewModel = WatchlistViewModel(
            repository: repository,
            removalCoordinator: removalCoordinator,
            analytics: RecordingAnalyticsService()
        )
        try await repository.add(sampleShow)
        await viewModel.reload()
        let tracked = try #require((try await repository.all()).first)

        viewModel.requestRemoval(tracked, anchor: .zero)
        await removalCoordinator.commitPendingRemovalIfNeeded()

        #expect(viewModel.shows.isEmpty)
    }

    @Test("Undo outcome leaves a deferred row visible")
    func undoOutcomeKeepsDeferredRowVisible() async throws {
        let repository = InMemoryWatchlistRepository()
        let removalCoordinator = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        let viewModel = WatchlistViewModel(
            repository: repository,
            removalCoordinator: removalCoordinator,
            analytics: RecordingAnalyticsService()
        )
        try await repository.add(sampleShow)
        await viewModel.reload()
        let tracked = try #require((try await repository.all()).first)

        viewModel.requestRemoval(tracked, anchor: .zero)
        await viewModel.undoPendingRemoval()

        #expect(viewModel.shows.count == 1)
        #expect(try await repository.contains(showID: tracked.id))
    }

    @Test("Failed immediate delete restores the row via outcome")
    func failedImmediateDeleteRestoresRow() async throws {
        let repository = FailingRemoveWatchlistRepository()
        let removalCoordinator = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        let viewModel = WatchlistViewModel(
            repository: repository,
            removalCoordinator: removalCoordinator,
            analytics: RecordingAnalyticsService()
        )
        try await repository.add(sampleShow)
        await viewModel.reload()
        let tracked = try #require((try await repository.all()).first)

        viewModel.deleteImmediately(
            at: IndexSet(integer: 0),
            in: [tracked],
            rowAnchors: [tracked.id: .zero]
        )

        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline, viewModel.shows.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(removalCoordinator.lastOutcome == .failed(showID: tracked.id))
        #expect(viewModel.shows.count == 1)
        #expect(try await repository.contains(showID: tracked.id))
    }

    @Test("Replacing a pending removal drops the first show from the displayed list")
    func replacingPendingRemovalDropsFirstShowFromDisplayedList() async throws {
        let repository = InMemoryWatchlistRepository()
        let removalCoordinator = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        let viewModel = WatchlistViewModel(
            repository: repository,
            removalCoordinator: removalCoordinator,
            analytics: RecordingAnalyticsService()
        )
        let firstShow = makeShow(id: 44933, name: "Severance")
        let secondShow = makeShow(id: 82, name: "Game of Thrones")
        try await repository.add(firstShow)
        try await repository.add(secondShow)
        await viewModel.reload()

        let first = try #require(viewModel.shows.first { $0.id == firstShow.id })
        let second = try #require(viewModel.shows.first { $0.id == secondShow.id })

        viewModel.requestRemoval(first, anchor: .zero)
        viewModel.requestRemoval(second, anchor: .zero)

        #expect(viewModel.pendingRemoval?.id == second.id)

        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline, try await repository.contains(showID: first.id) {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(try await repository.contains(showID: first.id) == false)
        #expect(viewModel.shows.map(\.id).contains(first.id) == false)
        #expect(viewModel.shows.map(\.id).contains(second.id))
        #expect(viewModel.isPendingRemoval(second))
        #expect(try await repository.contains(showID: second.id))
    }

    @Test("Swipe delete removes the row immediately and persists")
    func deleteImmediatelyRemovesRowAndPersists() async throws {
        let repository = InMemoryWatchlistRepository()
        let removalCoordinator = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        let viewModel = WatchlistViewModel(
            repository: repository,
            removalCoordinator: removalCoordinator,
            analytics: RecordingAnalyticsService()
        )
        try await repository.add(sampleShow)
        await viewModel.reload()
        let tracked = try #require((try await repository.all()).first)

        viewModel.deleteImmediately(
            at: IndexSet(integer: 0),
            in: [tracked],
            rowAnchors: [tracked.id: CGRect(x: 0, y: 120, width: 300, height: 60)]
        )

        #expect(viewModel.shows.isEmpty)
        #expect(removalCoordinator.pendingRemoval?.id == tracked.id)
        #expect(removalCoordinator.toastAnchor?.minY == 120)

        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline, try await repository.contains(showID: tracked.id) {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(try await repository.contains(showID: tracked.id) == false)
    }

    @Test("VoiceOver-equivalent immediate delete uses the same path as swipe")
    func deleteImmediatelyTrackedShowRemovesRowAndPersists() async throws {
        let repository = InMemoryWatchlistRepository()
        let removalCoordinator = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        let viewModel = WatchlistViewModel(
            repository: repository,
            removalCoordinator: removalCoordinator,
            analytics: RecordingAnalyticsService()
        )
        try await repository.add(sampleShow)
        await viewModel.reload()
        let tracked = try #require((try await repository.all()).first)
        let anchor = CGRect(x: 0, y: 120, width: 300, height: 60)

        viewModel.deleteImmediately(tracked, rowAnchor: anchor)

        #expect(viewModel.shows.isEmpty)
        #expect(removalCoordinator.pendingRemoval?.id == tracked.id)
        #expect(removalCoordinator.toastAnchor == anchor)

        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline, try await repository.contains(showID: tracked.id) {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(try await repository.contains(showID: tracked.id) == false)
    }

    @Test("Undo clears the pending removal flag")
    func undoPendingRemovalClearsPendingState() async throws {
        let repository = InMemoryWatchlistRepository()
        let removalCoordinator = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        let viewModel = WatchlistViewModel(
            repository: repository,
            removalCoordinator: removalCoordinator,
            analytics: RecordingAnalyticsService()
        )
        try await repository.add(sampleShow)
        await viewModel.reload()
        let tracked = try #require((try await repository.all()).first)

        viewModel.requestRemoval(tracked, anchor: .zero)
        await viewModel.undoPendingRemoval()

        #expect(viewModel.pendingRemoval == nil)
        #expect(viewModel.isPendingRemoval(tracked) == false)
    }

    @Test("An empty search query shows every tracked show")
    func emptySearchReturnsAllShows() async throws {
        let viewModel = try await loadedViewModel(with: [
            makeShow(id: 1, name: "Severance"),
            makeShow(id: 2, name: "The Bear"),
        ])

        #expect(viewModel.searchText.isEmpty)
        #expect(viewModel.filteredShows.count == 2)
    }

    @Test("A whitespace-only query is treated as no filter")
    func whitespaceQueryReturnsAllShows() async throws {
        let viewModel = try await loadedViewModel(with: [
            makeShow(id: 1, name: "Severance"),
            makeShow(id: 2, name: "The Bear"),
        ])

        viewModel.searchText = "   "

        #expect(viewModel.filteredShows.count == 2)
    }

    @Test("Search matches a partial substring of the show name")
    func searchMatchesPartialName() async throws {
        let viewModel = try await loadedViewModel(with: [
            makeShow(id: 1, name: "Severance"),
            makeShow(id: 2, name: "The Bear"),
            makeShow(id: 3, name: "Slow Horses"),
        ])

        viewModel.searchText = "ear"

        #expect(viewModel.filteredShows.map(\.name) == ["The Bear"])
    }

    @Test("Search ignores case and diacritics", arguments: ["POKEMON", "pokemon", "pokémon"])
    func searchIgnoresCaseAndDiacritics(query: String) async throws {
        let viewModel = try await loadedViewModel(with: [
            makeShow(id: 1, name: "Pokémon"),
            makeShow(id: 2, name: "The Bear"),
        ])

        viewModel.searchText = query

        #expect(viewModel.filteredShows.map(\.id) == [1])
    }

    @Test("A query with no matches yields an empty filtered list")
    func searchWithNoMatchesReturnsEmpty() async throws {
        let viewModel = try await loadedViewModel(with: [
            makeShow(id: 1, name: "Severance"),
            makeShow(id: 2, name: "The Bear"),
        ])

        viewModel.searchText = "zzz"

        #expect(viewModel.filteredShows.isEmpty)
        #expect(viewModel.shows.count == 2)
    }

    @Test("Filtering leaves the underlying show list intact")
    func filteringDoesNotMutateBackingList() async throws {
        let viewModel = try await loadedViewModel(with: [
            makeShow(id: 1, name: "Severance"),
            makeShow(id: 2, name: "The Bear"),
        ])

        viewModel.searchText = "Severance"

        #expect(viewModel.filteredShows.count == 1)
        #expect(viewModel.shows.count == 2)
    }

    @Test("Section groups follow status order and omit empty sections")
    func sectionGroupsFollowStatusOrderAndOmitEmptySections() {
        let premiere = TVMazeDate.dateOnly("2026-09-01")!
        let shows = [
            trackedShow(id: 1, name: "Unknown Show", nextSeason: .unknown),
            trackedShow(id: 2, name: "Ended Show", nextSeason: .ended),
            trackedShow(id: 3, name: "Airing Show", nextSeason: .airing(season: 2)),
            trackedShow(id: 4, name: "Waiting Show", nextSeason: .returningNoSeasonYet),
            trackedShow(
                id: 5, name: "Coming Show", nextSeason: .scheduled(season: 3, premiere: premiere)),
        ]

        let groups = WatchlistViewModel.sectionGroups(from: shows)

        #expect(
            groups.map(\.section) == [
                .airingNow,
                .comingSoon,
                .waitingForADate,
                .ended,
                .unknown,
            ])
        #expect(groups.map { $0.shows.map(\.id) } == [[3], [5], [4], [2], [1]])
    }

    @Test("Waiting for a Date includes announced-undated and returning shows")
    func waitingSectionIncludesAnnouncedAndReturning() {
        let groups = WatchlistViewModel.sectionGroups(from: [
            trackedShow(id: 1, name: "Announced", nextSeason: .announcedUndated(season: 4)),
            trackedShow(id: 2, name: "Returning", nextSeason: .returningNoSeasonYet),
        ])

        #expect(groups.map(\.section) == [.waitingForADate])
        #expect(groups[0].shows.map(\.id) == [1, 2])
    }

    @Test("Coming Soon sorts by premiere date ascending")
    func comingSoonSortsByPremiereDate() {
        let earlier = TVMazeDate.dateOnly("2026-08-01")!
        let later = TVMazeDate.dateOnly("2026-12-01")!
        let groups = WatchlistViewModel.sectionGroups(from: [
            trackedShow(id: 1, name: "Later", nextSeason: .scheduled(season: 2, premiere: later)),
            trackedShow(
                id: 2, name: "Earlier", nextSeason: .scheduled(season: 3, premiere: earlier)),
        ])

        #expect(groups.map(\.section) == [.comingSoon])
        #expect(groups[0].shows.map(\.name) == ["Earlier", "Later"])
    }

    @Test("Non-Coming Soon sections sort alphabetically by name")
    func nonComingSoonSectionsSortAlphabetically() {
        let groups = WatchlistViewModel.sectionGroups(from: [
            trackedShow(id: 1, name: "Zebra", nextSeason: .airing(season: 1)),
            trackedShow(id: 2, name: "aardvark", nextSeason: .airing(season: 2)),
            trackedShow(id: 3, name: "Middle", nextSeason: .ended),
            trackedShow(id: 4, name: "Alpha", nextSeason: .ended),
        ])

        #expect(groups.map(\.section) == [.airingNow, .ended])
        #expect(groups[0].shows.map(\.name) == ["aardvark", "Zebra"])
        #expect(groups[1].shows.map(\.name) == ["Alpha", "Middle"])
    }

    @Test("Filtered section groups honor the search query")
    func filteredSectionGroupsHonorSearchQuery() async throws {
        let repository = InMemoryWatchlistRepository()
        let removalCoordinator = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        let viewModel = WatchlistViewModel(
            repository: repository,
            removalCoordinator: removalCoordinator,
            analytics: RecordingAnalyticsService()
        )
        try await repository.add(makeShow(id: 1, name: "Severance"))
        try await repository.add(makeShow(id: 2, name: "The Bear"))
        await viewModel.reload()

        var severance = try #require(viewModel.shows.first { $0.id == 1 })
        var bear = try #require(viewModel.shows.first { $0.id == 2 })
        severance.nextSeason = .airing(season: 2)
        bear.nextSeason = .ended
        try await repository.updateAfterRefresh(severance)
        try await repository.updateAfterRefresh(bear)
        await viewModel.reload()

        viewModel.searchText = "Bear"

        #expect(viewModel.filteredSectionGroups.map(\.section) == [.ended])
        #expect(viewModel.filteredSectionGroups[0].shows.map(\.id) == [2])
    }

    @Test("A slower older reload cannot overwrite a newer reload result")
    func slowerOlderReloadDoesNotOverwriteNewerResult() async throws {
        let repository = ReentrantWatchlistRepository()
        let removalCoordinator = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        let viewModel = WatchlistViewModel(
            repository: repository,
            removalCoordinator: removalCoordinator,
            analytics: RecordingAnalyticsService()
        )
        repository.viewModel = viewModel
        repository.showToInsertDuringFirstAll = TrackedShow(from: sampleShow)

        await viewModel.reload()

        // Nested reload during the first `all()` applies the newer list; the
        // outer reload's empty result must not overwrite it.
        #expect(viewModel.shows.map(\.id) == [sampleShow.id])
        #expect(viewModel.state == .loaded)
        #expect(repository.allCallCount == 2)
    }
}

/// On the first `all()`, inserts a show and re-enters `reload()` before returning
/// an empty (stale) snapshot — exercising generation discard without concurrent tasks.
@MainActor
private final class ReentrantWatchlistRepository: WatchlistRepository {
    weak var viewModel: WatchlistViewModel?
    var showToInsertDuringFirstAll: TrackedShow?
    private(set) var allCallCount = 0
    private var shows: [Int: TrackedShow] = [:]

    func all() async throws -> [TrackedShow] {
        allCallCount += 1
        if allCallCount == 1, let showToInsertDuringFirstAll, let viewModel {
            shows[showToInsertDuringFirstAll.id] = showToInsertDuringFirstAll
            await viewModel.reload()
            return []
        }
        return shows.values.sorted { $0.dateAdded > $1.dateAdded }
    }

    func trackedShow(showID: Int) async throws -> TrackedShow? {
        shows[showID]
    }

    func trackedShowIDs() async throws -> Set<Int> {
        Set(shows.keys)
    }

    func contains(showID: Int) async throws -> Bool {
        shows[showID] != nil
    }

    func add(_ show: Show) async throws {
        guard shows[show.id] == nil else { return }
        shows[show.id] = TrackedShow(from: show)
    }

    func remove(showID: Int) async throws {
        shows.removeValue(forKey: showID)
    }

    func updateAfterRefresh(_ tracked: TrackedShow) async throws {
        shows[tracked.id] = tracked
    }

    func setPaused(_ isPaused: Bool, showIDs: Set<Int>) async throws {
        for id in showIDs { shows[id]?.isPaused = isPaused }
    }
}

/// Stores shows normally but throws from `remove`.
@MainActor
private final class FailingRemoveWatchlistRepository: WatchlistRepository {
    private var shows: [Int: TrackedShow] = [:]

    func all() async throws -> [TrackedShow] {
        shows.values.sorted { $0.dateAdded > $1.dateAdded }
    }

    func trackedShow(showID: Int) async throws -> TrackedShow? {
        shows[showID]
    }

    func trackedShowIDs() async throws -> Set<Int> {
        Set(shows.keys)
    }

    func contains(showID: Int) async throws -> Bool {
        shows[showID] != nil
    }

    func add(_ show: Show) async throws {
        guard shows[show.id] == nil else { return }
        shows[show.id] = TrackedShow(from: show)
    }

    func remove(showID: Int) async throws {
        throw URLError(.cannotConnectToHost)
    }

    func updateAfterRefresh(_ tracked: TrackedShow) async throws {
        shows[tracked.id] = tracked
    }

    func setPaused(_ isPaused: Bool, showIDs: Set<Int>) async throws {
        for id in showIDs { shows[id]?.isPaused = isPaused }
    }
}
