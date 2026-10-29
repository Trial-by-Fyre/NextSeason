//
//  WatchlistStatusWordingTests.swift
//  NextSeasonTests
//

import Foundation
import Testing

@testable import NextSeason

/// Watchlist rows name the stored broadcaster (without country) on airing and
/// scheduled rows and fall back to generic wording; CSV export keeps the shared
/// headline.
@MainActor
struct WatchlistStatusWordingTests {
    @Test("Airing rows name the broadcaster")
    func airingWithBroadcaster() {
        let row = ShowRowLabel(
            tracked: trackedShow(nextSeason: .airing(season: 20), broadcaster: "CBC Gem"))

        #expect(row.subtitle == "Season 20 airing on CBC Gem")
    }

    @Test("Airing rows without a broadcaster use the generic wording", arguments: [nil, "", "  "])
    func airingWithoutBroadcaster(_ broadcaster: String?) {
        let row = ShowRowLabel(
            tracked: trackedShow(nextSeason: .airing(season: 20), broadcaster: broadcaster))

        #expect(row.subtitle == "Season 20 currently airing")
    }

    @Test("Scheduled rows name the broadcaster after the premiere date")
    func scheduledWithBroadcaster() throws {
        let premiere = try #require(TVMazeDate.dateOnly("2027-01-01"))
        let status = NextSeasonStatus.scheduled(season: 21, premiere: premiere)
        let style = try dateStyle()

        #expect(
            status.watchlistHeadline(broadcaster: "CBC", dateStyle: style)
                == "Season 21 premieres Jan 1, 2027 on CBC")
        // The row passes the stored broadcaster and uses the shared date format.
        let row = ShowRowLabel(tracked: trackedShow(nextSeason: status, broadcaster: "CBC"))
        #expect(row.subtitle == status.headline + " on CBC")
    }

    @Test("Scheduled rows without a broadcaster keep the shared headline")
    func scheduledWithoutBroadcaster() throws {
        let premiere = try #require(TVMazeDate.dateOnly("2027-01-01"))
        let status = NextSeasonStatus.scheduled(season: 21, premiere: premiere)

        #expect(
            status.watchlistHeadline(broadcaster: nil, dateStyle: try dateStyle())
                == "Season 21 premieres Jan 1, 2027")
        let row = ShowRowLabel(tracked: trackedShow(nextSeason: status, broadcaster: nil))
        #expect(row.subtitle == status.headline)
    }

    @Test(
        "Statuses not tied to a broadcaster keep the shared headline",
        arguments: [
            NextSeasonStatus.announcedUndated(season: 4), .returningNoSeasonYet, .ended, .unknown,
        ]
    )
    func otherStatusesUnchanged(_ status: NextSeasonStatus) {
        let row = ShowRowLabel(tracked: trackedShow(nextSeason: status, broadcaster: "CBC Gem"))

        #expect(row.subtitle == status.headline)
    }

    @Test("Paused rows still show Paused")
    func pausedRowUnchanged() {
        let row = ShowRowLabel(
            tracked: trackedShow(
                nextSeason: .airing(season: 20), broadcaster: "CBC Gem", isPaused: true))

        #expect(row.subtitle == "Paused")
    }

    @Test("CSV export keeps the existing wording and omits the broadcaster")
    func csvUnchanged() {
        let csv = WatchlistCSVFormatter.csv(
            shows: [trackedShow(nextSeason: .airing(season: 20), broadcaster: "CBC Gem")],
            tvdbIDsByTVMazeID: [:])

        #expect(csv.contains("Currently showing Season 20"))
        #expect(!csv.contains("CBC Gem"))
    }

    private func trackedShow(
        nextSeason: NextSeasonStatus, broadcaster: String?, isPaused: Bool = false
    ) -> TrackedShow {
        let date = Date(timeIntervalSince1970: 0)
        return TrackedShow(
            id: 1,
            name: "Murdoch Mysteries",
            posterMediumURL: nil,
            broadcasterName: broadcaster,
            status: .running,
            nextSeason: nextSeason,
            sourceUpdatedAt: date,
            lastCheckedAt: date,
            dateAdded: date,
            isPaused: isPaused
        )
    }

    /// Fixed locale and time zone so the premiere date formats predictably.
    private func dateStyle() throws -> Date.FormatStyle {
        Date.FormatStyle(
            date: .abbreviated,
            time: .omitted,
            locale: Locale(identifier: "en_US"),
            calendar: Calendar(identifier: .gregorian),
            timeZone: try #require(TimeZone(identifier: "America/Los_Angeles"))
        )
    }
}
