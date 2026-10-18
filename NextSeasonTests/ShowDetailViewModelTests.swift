//
//  ShowDetailViewModelTests.swift
//  NextSeasonTests
//

import CoreGraphics
import Foundation
import Testing
import UserNotifications

@testable import NextSeason

/// Show-detail watchlist toggle: stale-state reconciliation, lookup failures, add
/// failures, and free-tier paywall. Uses denied notification authorization by default.
@MainActor
struct ShowDetailViewModelTests {
    private var sampleShow: Show {
        Show(
            id: 44933,
            name: "Severance",
            tvMazeURL: URL(string: "https://www.tvmaze.com/shows/44933/severance"),
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

    /// Notification service with isolated defaults and fixed `.denied` authorization for tests.
    private func makeNotificationService(analytics: any AnalyticsTracking) -> NotificationService {
        let suiteName = "ShowDetailViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return NotificationService(
            userDefaults: defaults,
            authorizationStatusForTesting: .denied,
            analytics: analytics
        )
    }

    /// TVMaze stub returning an optional fixed show; fails if fetched unexpectedly.
    private final class StubTVMazeService: TVMazeService, @unchecked Sendable {
        private let showToReturn: Show?

        init(showToReturn: Show? = nil) {
            self.showToReturn = showToReturn
        }

        func searchShows(matching query: String) async throws -> [Show] { [] }

        func lookupShow(theTVDBID: Int) async throws -> Show {
            throw TVMazeError.notFound
        }

        func show(id: Int, bypassCache: Bool) async throws -> Show {
            if let showToReturn { return showToReturn }
            Issue.record("Unexpected show fetch in watchlist-toggle tests")
            throw TVMazeError.notFound
        }

        func updatedShows(since period: TVMazeUpdatePeriod) async throws -> [Int: Date] { [:] }
    }

    /// Fails the removal lookup, while `contains` reports the show as absent so
    /// a post-failure refresh can clear stale local tracked state.
    private final class FailingTrackedShowLookupRepository: WatchlistRepository {
        func all() async throws -> [TrackedShow] { [] }

        func trackedShow(showID: Int) async throws -> TrackedShow? {
            throw URLError(.cannotConnectToHost)
        }

        func trackedShowIDs() async throws -> Set<Int> { [] }

        func contains(showID: Int) async throws -> Bool { false }

        func add(_ show: Show) async throws {}

        func remove(showID: Int) async throws {}

        func updateAfterRefresh(_ tracked: TrackedShow) async throws {}

        func setPaused(_ isPaused: Bool, showIDs: Set<Int>) async throws {}

        func restoreRemoved(_ tracked: TrackedShow, isPaused: Bool) async throws {}
    }

    /// Fails the removal lookup, while `contains` still reports the show as
    /// persisted — simulating a lookup error without a successful removal.
    private final class FailingLookupStillPersistedRepository: WatchlistRepository {
        let showID: Int

        init(showID: Int) {
            self.showID = showID
        }

        func all() async throws -> [TrackedShow] { [] }

        func trackedShow(showID: Int) async throws -> TrackedShow? {
            throw URLError(.cannotConnectToHost)
        }

        func trackedShowIDs() async throws -> Set<Int> { [showID] }

        func contains(showID: Int) async throws -> Bool { showID == self.showID }

        /// Still persisted and active (star state reads the active query).
        func activeShowIDs() async throws -> Set<Int> { [showID] }

        func add(_ show: Show) async throws {}

        func remove(showID: Int) async throws {}

        func updateAfterRefresh(_ tracked: TrackedShow) async throws {}

        func setPaused(_ isPaused: Bool, showIDs: Set<Int>) async throws {}

        func restoreRemoved(_ tracked: TrackedShow, isPaused: Bool) async throws {}
    }

    /// Repository whose `add` always fails so the detail view keeps loaded content.
    private final class FailingAddRepository: WatchlistRepository {
        func all() async throws -> [TrackedShow] { [] }

        func trackedShow(showID: Int) async throws -> TrackedShow? { nil }

        func trackedShowIDs() async throws -> Set<Int> { [] }

        func contains(showID: Int) async throws -> Bool { false }

        func add(_ show: Show) async throws {
            throw URLError(.cannotConnectToHost)
        }

        func remove(showID: Int) async throws {}

        func updateAfterRefresh(_ tracked: TrackedShow) async throws {}

        func setPaused(_ isPaused: Bool, showIDs: Set<Int>) async throws {}

        func restoreRemoved(_ tracked: TrackedShow, isPaused: Bool) async throws {}
    }

    @Test("Stale tracked state reconciles when removal lookup finds nothing")
    func removalIgnoredReconcilesTrackedState() async {
        let repository = InMemoryWatchlistRepository()
        let analytics = RecordingAnalyticsService()
        let removalCoordinator = WatchlistPendingRemoval(
            repository: repository, analytics: analytics)
        let viewModel = ShowDetailViewModel(
            show: sampleShow,
            service: StubTVMazeService(),
            repository: repository,
            notifications: makeNotificationService(analytics: analytics),
            analytics: analytics,
            purchases: .stub(),
            initialIsTracked: true
        )

        await viewModel.handleTrackButton(
            removalCoordinator: removalCoordinator,
            onWatchlistChanged: {},
            onPaywallRequired: {}
        )

        #expect(viewModel.isTracked == false)
        #expect(viewModel.watchlistActionErrorMessage == nil)
    }

    @Test("Removal lookup failure reports analytics, refreshes, and shows a generic alert")
    func removalLookupFailureReportsAndRefreshes() async {
        let repository = FailingTrackedShowLookupRepository()
        let analytics = RecordingAnalyticsService()
        let removalCoordinator = WatchlistPendingRemoval(
            repository: repository, analytics: analytics)
        let viewModel = ShowDetailViewModel(
            show: sampleShow,
            service: StubTVMazeService(),
            repository: repository,
            notifications: makeNotificationService(analytics: analytics),
            analytics: analytics,
            purchases: .stub(),
            initialIsTracked: true
        )

        await viewModel.handleTrackButton(
            removalCoordinator: removalCoordinator,
            onWatchlistChanged: {},
            onPaywallRequired: {}
        )

        #expect(
            analytics.events.contains {
                if case .nonFatalError(_, let context) = $0 {
                    return context == "show_detail_watchlist_lookup"
                }
                return false
            }
        )
        #expect(viewModel.isTracked == false)
        #expect(viewModel.watchlistActionErrorMessage == WatchlistTracking.updateFailedMessage)
    }

    @Test("Removal lookup failure keeps the star when persistence still contains the show")
    func removalLookupFailurePreservesStarWhenStillPersisted() async {
        let repository = FailingLookupStillPersistedRepository(showID: sampleShow.id)
        let analytics = RecordingAnalyticsService()
        let removalCoordinator = WatchlistPendingRemoval(
            repository: repository, analytics: analytics)
        let viewModel = ShowDetailViewModel(
            show: sampleShow,
            service: StubTVMazeService(),
            repository: repository,
            notifications: makeNotificationService(analytics: analytics),
            analytics: analytics,
            purchases: .stub(),
            initialIsTracked: true
        )

        await viewModel.handleTrackButton(
            removalCoordinator: removalCoordinator,
            onWatchlistChanged: {},
            onPaywallRequired: {}
        )

        #expect(viewModel.isTracked)
        #expect(viewModel.watchlistActionErrorMessage == WatchlistTracking.updateFailedMessage)
        #expect(
            analytics.events.contains {
                if case .nonFatalError(_, let context) = $0 {
                    return context == "show_detail_watchlist_lookup"
                }
                return false
            }
        )
    }

    @Test("Add failure keeps loaded content and surfaces a watchlist error")
    func addFailureDoesNotReplaceLoadedContent() async {
        let repository = FailingAddRepository()
        let analytics = RecordingAnalyticsService()
        let viewModel = ShowDetailViewModel(
            show: sampleShow,
            service: StubTVMazeService(showToReturn: sampleShow),
            repository: repository,
            notifications: makeNotificationService(analytics: analytics),
            analytics: analytics,
            purchases: .stub(),
            initialIsTracked: false
        )

        await viewModel.load(removalCoordinator: nil)
        #expect(viewModel.loadState == .loaded)

        await viewModel.handleTrackButton(
            removalCoordinator: nil,
            onWatchlistChanged: {},
            onPaywallRequired: {}
        )

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.isTracked == false)
        #expect(viewModel.watchlistActionErrorMessage == WatchlistTracking.updateFailedMessage)
        #expect(
            analytics.events.contains {
                if case .nonFatalError(_, let context) = $0 {
                    return context == "watchlist_add_detail"
                }
                return false
            }
        )
    }

    @Test("A fourth-show add presents Plus instead of failing")
    func fourthShowAddPresentsPaywall() async throws {
        let repository = InMemoryWatchlistRepository()
        let analytics = RecordingAnalyticsService()
        try await repository.add(show(id: 1, name: "One"))
        try await repository.add(show(id: 2, name: "Two"))
        try await repository.add(show(id: 3, name: "Three"))

        var didPresentPaywall = false
        let viewModel = ShowDetailViewModel(
            show: sampleShow,
            service: StubTVMazeService(showToReturn: sampleShow),
            repository: repository,
            notifications: makeNotificationService(analytics: analytics),
            analytics: analytics,
            purchases: .stub(),
            initialIsTracked: false
        )

        await viewModel.handleTrackButton(
            removalCoordinator: nil,
            onWatchlistChanged: {},
            onPaywallRequired: { didPresentPaywall = true }
        )

        #expect(didPresentPaywall)
        #expect(viewModel.isTracked == false)
        #expect(viewModel.watchlistActionErrorMessage == nil)
        #expect(try await repository.contains(showID: sampleShow.id) == false)
    }

    private func show(id: Int, name: String) -> Show {
        Show(
            id: id,
            name: name,
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
}
