//
//  SearchWatchlistTrackingTests.swift
//  NextSeasonTests
//

import CoreGraphics
import Foundation
import Testing
import UserNotifications

@testable import NextSeason

@MainActor
struct SearchWatchlistTrackingTests {
    private final class MockTVMazeService: TVMazeService, @unchecked Sendable {
        var show: Show

        init(show: Show) {
            self.show = show
        }

        func searchShows(matching query: String) async throws -> [Show] { [] }
        func lookupShow(theTVDBID: Int) async throws -> Show { show }
        func show(id: Int, bypassCache: Bool) async throws -> Show { show }
        func updatedShows(since period: TVMazeUpdatePeriod) async throws -> [Int: Date] { [:] }
    }

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

    private final class FailingTrackedShowLookupRepository: WatchlistRepository {
        let showID: Int

        init(showID: Int) {
            self.showID = showID
        }

        func all() async throws -> [TrackedShow] { [] }

        func trackedShow(showID: Int) async throws -> TrackedShow? {
            throw URLError(.cannotConnectToHost)
        }

        func trackedShowIDs() async throws -> Set<Int> { [showID] }
        func activeShowIDs() async throws -> Set<Int> { [showID] }
        func contains(showID: Int) async throws -> Bool { showID == self.showID }
        func add(_ show: Show) async throws {}
        func remove(showID: Int) async throws {}
        func updateAfterRefresh(_ tracked: TrackedShow) async throws {}
        func setPaused(_ isPaused: Bool, showIDs: Set<Int>) async throws {}
        func restoreRemoved(_ tracked: TrackedShow, isPaused: Bool) async throws {}
    }

    private func context(
        repository: any WatchlistRepository,
        removalCoordinator: WatchlistPendingRemoval? = nil
    ) -> SearchWatchlistTracking.Context {
        SearchWatchlistTracking.Context(
            repository: repository,
            tvMaze: MockTVMazeService(show: sampleShow),
            removalCoordinator: removalCoordinator,
            notificationService: NotificationService(
                userDefaults: UserDefaults(suiteName: "SearchWatchlistTrackingTests.\(UUID())")!,
                authorizationStatusForTesting: .denied,
                analytics: RecordingAnalyticsService()),
            notificationPrompt: WatchlistNotificationPromptState(),
            analytics: RecordingAnalyticsService(),
            purchases: .stub(),
            onWatchlistChanged: {},
            onSearchResultsHintDismissed: {},
            onPaywallRequired: {}
        )
    }

    @Test("A failed add propagates to the search caller")
    func addFailurePropagates() async throws {
        let tracking = SearchWatchlistTracking()
        let repository = FailingAddRepository()

        await #expect(throws: URLError.self) {
            try await tracking.handleTrackButton(
                for: sampleShow,
                context: context(repository: repository)
            )
        }
        #expect(tracking.trackedShowIDs.isEmpty)
    }

    @Test("A failed deferred-removal lookup propagates to the search caller")
    func removalLookupFailurePropagates() async throws {
        let repository = FailingTrackedShowLookupRepository(showID: sampleShow.id)
        let removalCoordinator = WatchlistPendingRemoval(
            repository: repository,
            analytics: RecordingAnalyticsService())
        let tracking = SearchWatchlistTracking()
        await tracking.refresh(
            repository: repository,
            excludingPendingRemovalFrom: removalCoordinator,
            analytics: RecordingAnalyticsService()
        )
        #expect(tracking.trackedShowIDs.contains(sampleShow.id))

        await #expect(throws: URLError.self) {
            try await tracking.handleTrackButton(
                for: sampleShow,
                context: context(
                    repository: repository,
                    removalCoordinator: removalCoordinator
                )
            )
        }
    }
}
