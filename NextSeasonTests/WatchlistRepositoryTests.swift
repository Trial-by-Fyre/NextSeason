//
//  WatchlistRepositoryTests.swift
//  NextSeasonTests
//

import Foundation
import Testing

@testable import NextSeason

@MainActor
struct WatchlistRepositoryTests {
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
            seasons: [
                Season(
                    id: 1, number: 1, premiereDate: TVMazeDate.dateOnly("2022-02-18"),
                    endDate: TVMazeDate.dateOnly("2022-04-08"), episodeOrder: 9),
                Season(id: 3, number: 3, premiereDate: nil, endDate: nil, episodeOrder: nil),
            ],
            nextEpisode: nil,
            updatedAt: .now
        )
    }

    @Test("Adding a show stores a snapshot and prevents duplicates")
    func addAndContains() async throws {
        let repository = InMemoryWatchlistRepository()
        let show = sampleShow
        #expect(try await repository.contains(showID: show.id) == false)

        try await repository.add(show)
        #expect(try await repository.contains(showID: show.id))

        let all = try await repository.all()
        #expect(all.count == 1)
        #expect(all[0].name == show.name)
        #expect(all[0].summaryHTML == show.summaryHTML)
        #expect(all[0].tvMazeURL == show.tvMazeURL)
        #expect(all[0].nextSeason == NextSeasonCalculator.status(for: show))

        try await repository.add(show)
        #expect(try await repository.all().count == 1)
    }

    @Test("Tracked show lookup returns a single show without loading the full watchlist")
    func trackedShowLookup() async throws {
        let repository = InMemoryWatchlistRepository()
        let show = sampleShow
        try await repository.add(show)

        let tracked = try await repository.trackedShow(showID: show.id)
        #expect(tracked?.name == show.name)

        let ids = try await repository.trackedShowIDs()
        #expect(ids == [show.id])
        #expect(try await repository.trackedShow(showID: 999) == nil)
    }

    @Test("Removing a show deletes it from the watchlist")
    func removeShow() async throws {
        let repository = InMemoryWatchlistRepository()
        let show = sampleShow
        try await repository.add(show)
        try await repository.remove(showID: show.id)
        #expect(try await repository.all().isEmpty)
    }

    @Test("Refresh update is a no-op when the row was removed")
    func updateAfterRefreshNoOpsWhenMissing() async throws {
        let repository = InMemoryWatchlistRepository()
        let show = sampleShow
        try await repository.add(show)
        let tracked = try #require(try await repository.trackedShow(showID: show.id))
        try await repository.remove(showID: show.id)

        try await repository.updateAfterRefresh(tracked)

        #expect(try await repository.all().isEmpty)
    }

    @Test("Refresh update preserves the stored pause flag")
    func updateAfterRefreshPreservesPauseFlag() async throws {
        let repository = InMemoryWatchlistRepository()
        let show = sampleShow
        try await repository.add(show)
        try await repository.setPaused(true, showIDs: [show.id])
        var refreshed = try #require(try await repository.trackedShow(showID: show.id))
        refreshed.isPaused = false
        refreshed.name = "Updated Name"

        try await repository.updateAfterRefresh(refreshed)

        let stored = try #require(try await repository.trackedShow(showID: show.id))
        #expect(stored.isPaused)
        #expect(stored.name == "Updated Name")
    }

    @Test("Refresh update copies dateAdded from the incoming row")
    func updateAfterRefreshCopiesDateAdded() async throws {
        let storedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let incomingDate = Date(timeIntervalSince1970: 1_800_000_000)
        let storedRow = TrackedShow(from: sampleShow, at: storedDate)
        let repository = InMemoryWatchlistRepository(seed: [storedRow])

        var incoming = storedRow
        incoming.dateAdded = incomingDate
        incoming.name = "Renamed on refresh"

        try await repository.updateAfterRefresh(incoming)

        let after = try #require(try await repository.trackedShow(showID: sampleShow.id))
        #expect(after.dateAdded == incomingDate)
        #expect(after.name == "Renamed on refresh")
    }
}
