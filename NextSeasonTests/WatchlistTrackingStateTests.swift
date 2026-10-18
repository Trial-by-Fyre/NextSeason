//
//  WatchlistTrackingStateTests.swift
//  NextSeasonTests
//

import CoreGraphics
import Foundation
import Testing

@testable import NextSeason

@MainActor
struct WatchlistTrackingStateTests {
    @Test("A persisted show is tracked unless it is pending removal")
    func isTrackedExcludesPendingRemoval() {
        #expect(
            WatchlistTrackingState.isTracked(
                showID: 1,
                isPersisted: true,
                pendingRemovalID: nil
            )
        )
        #expect(
            WatchlistTrackingState.isTracked(
                showID: 1,
                isPersisted: true,
                pendingRemovalID: 1
            ) == false
        )
        #expect(
            WatchlistTrackingState.isTracked(
                showID: 1,
                isPersisted: true,
                pendingRemovalID: 2
            )
        )
        #expect(
            WatchlistTrackingState.isTracked(
                showID: 1,
                isPersisted: false,
                pendingRemovalID: nil
            ) == false
        )
    }

    @Test("Tracked ID sets drop the pending removal")
    func trackedIDsExcludePendingRemoval() {
        let persisted: Set<Int> = [1, 2, 3]

        #expect(
            WatchlistTrackingState.trackedIDs(
                persistedIDs: persisted,
                pendingRemovalID: nil
            ) == persisted
        )
        #expect(
            WatchlistTrackingState.trackedIDs(
                persistedIDs: persisted,
                pendingRemovalID: 2
            ) == [1, 3]
        )
        #expect(
            WatchlistTrackingState.trackedIDs(
                persistedIDs: persisted,
                pendingRemovalID: 99
            ) == persisted
        )
    }

    @Test("Repository helpers apply the same pending-removal rule")
    func repositoryHelpersMatchPureLogic() async throws {
        let repository = InMemoryWatchlistRepository()
        let show = Show(
            id: 10,
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
        try await repository.add(show)

        let removalCoordinator = WatchlistPendingRemoval(
            repository: repository,
            analytics: RecordingAnalyticsService()
        )
        let tracked = try #require(await repository.trackedShow(showID: show.id))
        removalCoordinator.requestRemoval(tracked, source: .search)

        #expect(
            try await WatchlistTrackingState.isTracked(
                showID: show.id,
                repository: repository,
                removalCoordinator: removalCoordinator
            ) == false
        )
        #expect(
            try await WatchlistTrackingState.trackedIDs(
                repository: repository,
                removalCoordinator: removalCoordinator
            ).isEmpty
        )

        _ = await removalCoordinator.undoRemoval()

        #expect(
            try await WatchlistTrackingState.isTracked(
                showID: show.id,
                repository: repository,
                removalCoordinator: removalCoordinator
            )
        )
        #expect(
            try await WatchlistTrackingState.trackedIDs(
                repository: repository,
                removalCoordinator: removalCoordinator
            ) == [show.id]
        )
    }
}
