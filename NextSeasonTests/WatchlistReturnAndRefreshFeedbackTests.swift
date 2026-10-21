//
//  WatchlistReturnAndRefreshFeedbackTests.swift
//  NextSeasonTests
//

import Foundation
import Testing

@testable import NextSeason

private final class OfflineTVMaze: TVMazeService, @unchecked Sendable {
    /// IDs that still load; every other show fails as if offline.
    var reachableShows: [Int: Show] = [:]

    func searchShows(matching query: String) async throws -> [Show] { [] }
    func lookupShow(theTVDBID: Int) async throws -> Show { throw TVMazeError.notFound }
    func show(id: Int, bypassCache: Bool) async throws -> Show {
        guard let show = reachableShows[id] else { throw URLError(.notConnectedToInternet) }
        return show
    }
    func updatedShows(since period: TVMazeUpdatePeriod) async throws -> [Int: Date] {
        throw URLError(.notConnectedToInternet)
    }
}

private final class SilentNotifications: NotificationDelivering {
    func deliver(_ content: SeasonNotificationContent) async -> NotificationDeliveryOutcome {
        .accepted
    }
}

/// Watchlist return after a deferred removal elsewhere (#4) and pull-to-refresh
/// failure feedback (#5).
@MainActor
struct WatchlistReturnAndRefreshFeedbackTests {
    private func show(_ id: Int) -> Show {
        Show(
            id: id, name: "Show \(id)", tvMazeURL: nil, summaryHTML: nil,
            posterMediumURL: nil, posterOriginalURL: nil, status: .running,
            premiered: nil, ended: nil, network: nil, genres: [], averageRuntime: nil,
            seasons: [], nextEpisode: nil, updatedAt: .distantPast)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "WatchlistReturnAndRefreshFeedbackTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeViewModel(
        repository: InMemoryWatchlistRepository,
        removal: WatchlistPendingRemoval,
        tvMaze: OfflineTVMaze = OfflineTVMaze()
    ) -> WatchlistViewModel {
        WatchlistViewModel(
            repository: repository,
            refreshService: WatchlistRefreshService(
                tvMaze: tvMaze,
                repository: repository,
                notifications: SilentNotifications(),
                analytics: RecordingAnalyticsService(),
                userDefaults: isolatedDefaults()
            ),
            removalCoordinator: removal,
            analytics: RecordingAnalyticsService()
        )
    }

    private func waitUntilRemoved(_ id: Int, from repository: InMemoryWatchlistRepository)
        async throws
    {
        var attempts = 0
        while try await repository.contains(showID: id), attempts < 50 {
            attempts += 1
            await Task.yield()
        }
    }

    // MARK: - Returning to the Watchlist

    @Test("Returning with a deferred removal removes the row at once and keeps Undo")
    func returnPersistsDeferredRemovalKeepingUndo() async throws {
        let repository = InMemoryWatchlistRepository()
        try await repository.add(show(1))
        try await repository.add(show(2))
        let removal = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        removal.undoWindowSecondsOverride = 60
        let viewModel = makeViewModel(repository: repository, removal: removal)
        await viewModel.reload()

        // Star removal in Show Details (deferred), then back to the Watchlist.
        removal.requestRemoval(
            try #require(try await repository.trackedShow(showID: 1)),
            source: .detail)
        viewModel.persistDeferredRemovalOnReturn()

        #expect(viewModel.shows.map(\.id) == [2], "Row leaves immediately")
        #expect(removal.pendingRemoval?.id == 1, "Toast stays up")
        #expect(removal.deferredRemovalShowID == nil, "Now an immediate removal")
        try await waitUntilRemoved(1, from: repository)
        #expect(try await repository.contains(showID: 1) == false)

        _ = await removal.undoRemoval()
        #expect(try await repository.contains(showID: 1))
        #expect(removal.pendingRemoval == nil)
    }

    @Test("Returning without a deferred removal changes nothing")
    func returnWithoutPendingRemovalIsNoOp() async throws {
        let repository = InMemoryWatchlistRepository()
        try await repository.add(show(1))
        let removal = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        let viewModel = makeViewModel(repository: repository, removal: removal)
        await viewModel.reload()

        viewModel.persistDeferredRemovalOnReturn()
        #expect(viewModel.shows.map(\.id) == [1])
        #expect(try await repository.contains(showID: 1))
    }

    // MARK: - Pull-to-refresh feedback

    @Test("Offline pull-to-refresh reports failure and keeps saved rows")
    func offlineRefreshReportsFailure() async throws {
        let repository = InMemoryWatchlistRepository()
        try await repository.add(show(1))
        try await repository.add(show(2))
        let removal = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        let viewModel = makeViewModel(repository: repository, removal: removal)
        await viewModel.reload()

        await viewModel.refreshFromNetwork()

        #expect(viewModel.refreshFailureMessage == WatchlistViewModel.refreshFailedMessage)
        #expect(Set(viewModel.shows.map(\.id)) == [1, 2])
        viewModel.clearRefreshFailure()
        #expect(viewModel.refreshFailureMessage == nil)
    }

    @Test("A partly failed pull-to-refresh says some shows failed")
    func partialRefreshFailure() async throws {
        let repository = InMemoryWatchlistRepository()
        try await repository.add(show(1))
        try await repository.add(show(2))
        let tvMaze = OfflineTVMaze()
        tvMaze.reachableShows = [1: show(1)]
        let removal = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        let viewModel = makeViewModel(repository: repository, removal: removal, tvMaze: tvMaze)

        await viewModel.refreshFromNetwork()
        #expect(viewModel.refreshFailureMessage == WatchlistViewModel.refreshPartlyFailedMessage)

        // A later successful refresh clears the old message.
        tvMaze.reachableShows[2] = show(2)
        await viewModel.refreshFromNetwork()
        #expect(viewModel.refreshFailureMessage == nil)
    }

    @Test("Outcome mapping: only failures produce a message")
    func outcomeMapping() {
        func outcome(_ completion: WatchlistRefreshCompletion) -> WatchlistRefreshOutcome {
            WatchlistRefreshOutcome(
                fetchResult: "", notificationDecision: "", completion: completion)
        }
        #expect(WatchlistViewModel.refreshFailureMessage(for: nil) == nil)
        #expect(WatchlistViewModel.refreshFailureMessage(for: outcome(.cancelled)) == nil)
        #expect(
            WatchlistViewModel.refreshFailureMessage(for: outcome(.aborted))
                == WatchlistViewModel.refreshFailedMessage)
        #expect(
            WatchlistViewModel.refreshFailureMessage(
                for: outcome(.finished(WatchlistRefreshCounts(refreshed: 2)))) == nil)
        #expect(
            WatchlistViewModel.refreshFailureMessage(
                for: outcome(.finished(WatchlistRefreshCounts()))) == nil,
            "Empty watchlist")
    }
}
