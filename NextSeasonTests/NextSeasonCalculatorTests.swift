//
//  NextSeasonCalculatorTests.swift
//  NextSeasonTests
//

import Foundation
import Testing

@testable import NextSeason

struct NextSeasonCalculatorTests {
    /// Fixed "today" so date comparisons are deterministic.
    private let now = TVMazeDate.dateOnly("2026-06-14")!

    private func makeShow(
        status: ShowStatus = .running,
        seasons: [Season] = [],
        nextEpisode: NextEpisode? = nil
    ) -> Show {
        Show(
            id: 1,
            name: "Test Show",
            tvMazeURL: nil,
            summaryHTML: nil,
            posterMediumURL: nil,
            posterOriginalURL: nil,
            status: status,
            premiered: nil,
            ended: nil,
            network: nil,
            genres: [],
            averageRuntime: nil,
            seasons: seasons,
            nextEpisode: nextEpisode,
            updatedAt: .distantPast
        )
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

    @Test("A future-dated upcoming season is reported as scheduled")
    func scheduled() throws {
        let show = makeShow(seasons: [
            season(1, premiere: "2024-01-01", end: "2024-03-01"),
            season(2, premiere: "2026-09-01"),
        ])
        let expected = NextSeasonStatus.scheduled(
            season: 2, premiere: try #require(TVMazeDate.dateOnly("2026-09-01")))
        #expect(NextSeasonCalculator.status(for: show, at: now) == expected)
    }

    @Test("An undated upcoming season is reported as announced (Severance S3)")
    func announcedUndated() {
        let show = makeShow(seasons: [
            season(1, premiere: "2022-02-18", end: "2022-04-08"),
            season(2, premiere: "2025-01-17", end: "2025-03-21"),
            season(3, premiere: nil),
        ])
        #expect(NextSeasonCalculator.status(for: show, at: now) == .announcedUndated(season: 3))
    }

    @Test("The latest season still on air is reported as airing")
    func airing() {
        let show = makeShow(seasons: [
            season(1, premiere: "2025-01-01", end: "2025-03-01"),
            season(2, premiere: "2026-06-01", end: nil),
        ])
        #expect(NextSeasonCalculator.status(for: show, at: now) == .airing(season: 2))
    }

    @Test("A running show between seasons returns returningNoSeasonYet")
    func returningNoSeasonYet() {
        let show = makeShow(seasons: [
            season(1, premiere: "2024-01-01", end: "2024-03-01"),
            season(2, premiere: "2025-01-01", end: "2025-03-01"),
        ])
        #expect(NextSeasonCalculator.status(for: show, at: now) == .returningNoSeasonYet)
    }

    @Test("An ended show with only past seasons is rerun-safe and reports ended")
    func endedShow() {
        let show = makeShow(
            status: .ended,
            seasons: [
                season(1, premiere: "2007-09-24", end: "2008-05-19"),
                season(12, premiere: "2018-09-24", end: "2019-05-16"),
            ])
        #expect(NextSeasonCalculator.status(for: show, at: now) == .ended)
    }

    @Test("No seasons and unknown status returns unknown")
    func unknownStatus() {
        let show = makeShow(status: .unknown("Unknown"), seasons: [])
        #expect(NextSeasonCalculator.status(for: show, at: now) == .unknown)
    }

    @Test("A brand-new show with only a future first season is scheduled")
    func brandNewFirstSeason() throws {
        let show = makeShow(
            status: .toBeDetermined,
            seasons: [
                season(1, premiere: "2026-12-01")
            ])
        let expected = NextSeasonStatus.scheduled(
            season: 1, premiere: try #require(TVMazeDate.dateOnly("2026-12-01")))
        #expect(NextSeasonCalculator.status(for: show, at: now) == expected)
    }

    @Test("Specials (season 0) are ignored when deriving status")
    func ignoresSpecials() {
        let show = makeShow(seasons: [
            season(0, premiere: "2026-06-01"),
            season(1, premiere: "2024-01-01", end: "2024-03-01"),
            season(2, premiere: nil),
        ])
        #expect(NextSeasonCalculator.status(for: show, at: now) == .announcedUndated(season: 2))
    }

    @Test("An annual/daily show in its current yearly season reports airing")
    func annualSeasonAiring() {
        let show = makeShow(seasons: [
            season(2025, premiere: "2025-01-01", end: "2025-12-15"),
            season(2026, premiere: "2026-01-05", end: nil),
        ])
        #expect(NextSeasonCalculator.status(for: show, at: now) == .airing(season: 2026))
    }

    @Test("A next episode in an undated new season resolves to scheduled")
    func nextEpisodeSignalsScheduledSeason() throws {
        let show = makeShow(
            seasons: [season(1, premiere: "2025-01-01", end: "2025-03-01")],
            nextEpisode: NextEpisode(
                season: 2, number: 1, airdate: TVMazeDate.dateOnly("2026-08-01"))
        )
        let expected = NextSeasonStatus.scheduled(
            season: 2, premiere: try #require(TVMazeDate.dateOnly("2026-08-01")))
        #expect(NextSeasonCalculator.status(for: show, at: now) == expected)
    }

    /// Review finding R09: with season 2's row undated, a dated later episode
    /// (or a special, which has no number) used to become the season premiere.
    @Test(
        "Only episode 1 of an undated new season counts as its premiere",
        arguments: [(1, true), (8, false), (nil, false)] as [(Int?, Bool)]
    )
    func onlyEpisodeOneIsPremiere(number: Int?, isPremiere: Bool) throws {
        let airdate = try #require(TVMazeDate.dateOnly("2026-08-01"))
        let show = makeShow(
            seasons: [
                season(1, premiere: "2025-01-01", end: "2025-03-01"),
                season(2, premiere: nil),
            ],
            nextEpisode: NextEpisode(season: 2, number: number, airdate: airdate)
        )
        let expected: NextSeasonStatus =
            isPremiere
            ? .scheduled(season: 2, premiere: airdate)
            : .announcedUndated(season: 2)
        #expect(NextSeasonCalculator.status(for: show, at: now) == expected)
    }

    @Test("A dated later episode of a new season with no season row is announced, not scheduled")
    func laterEpisodeWithoutSeasonRowIsAnnounced() {
        let show = makeShow(
            seasons: [season(1, premiere: "2025-01-01", end: "2025-03-01")],
            nextEpisode: NextEpisode(
                season: 2, number: 8, airdate: TVMazeDate.dateOnly("2026-08-01"))
        )
        #expect(NextSeasonCalculator.status(for: show, at: now) == .announcedUndated(season: 2))
    }

    @Test("A season whose end date is today is still reported as airing")
    func seasonEndDateIsTodayStillAiring() throws {
        let endToday = try #require(TVMazeDate.dateOnly("2026-06-14"))
        let nowSameDay = endToday.addingTimeInterval(12 * 3600)
        let show = makeShow(seasons: [
            season(1, premiere: "2025-01-01", end: "2025-03-01"),
            season(2, premiere: "2026-06-01", end: "2026-06-14"),
        ])
        #expect(NextSeasonCalculator.status(for: show, at: nowSameDay) == .airing(season: 2))
    }

    @Test("An undated future season does not override a currently airing season")
    func undatedFutureSeasonWhileCurrentIsAiring() {
        let show = makeShow(seasons: [
            season(1, premiere: "2025-01-01", end: "2025-03-01"),
            season(2, premiere: "2026-06-01", end: nil),
            season(3, premiere: nil),
        ])
        #expect(NextSeasonCalculator.status(for: show, at: now) == .airing(season: 2))
    }

    @Test("A next episode with no airdate in a new season is announced, not airing")
    func nextEpisodeWithNoAirdate() {
        let show = makeShow(
            seasons: [season(1, premiere: "2025-01-01", end: "2025-03-01")],
            nextEpisode: NextEpisode(season: 2, number: 1, airdate: nil)
        )
        #expect(NextSeasonCalculator.status(for: show, at: now) == .announcedUndated(season: 2))
    }

    @Test("An undated next episode with a matching undated season row is announced")
    func nextEpisodeWithNoAirdateAndUndatedSeasonRow() {
        let show = makeShow(
            seasons: [
                season(1, premiere: "2025-01-01", end: "2025-03-01"),
                season(2, premiere: nil),
            ],
            nextEpisode: NextEpisode(season: 2, number: 1, airdate: nil)
        )
        #expect(NextSeasonCalculator.status(for: show, at: now) == .announcedUndated(season: 2))
    }
}
