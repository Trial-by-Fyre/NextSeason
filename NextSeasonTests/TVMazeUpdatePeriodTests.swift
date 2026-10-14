//
//  TVMazeUpdatePeriodTests.swift
//  NextSeasonTests
//

import Foundation
import Testing

@testable import NextSeason

struct TVMazeUpdatePeriodTests {
    private let now = TVMazeDate.dateOnly("2026-06-14")!

    @Test("Day window covers checks within the last 24 hours")
    func dayWindow() {
        let oldest = now.addingTimeInterval(-86_400)
        #expect(TVMazeUpdatePeriod.covering(since: oldest, at: now) == .day)
    }

    @Test("Week window covers checks between one and seven days ago")
    func weekWindow() {
        let oldest = now.addingTimeInterval(-2 * 86_400)
        #expect(TVMazeUpdatePeriod.covering(since: oldest, at: now) == .week)
    }

    @Test("Month window covers checks older than a week but within about a month")
    func monthWindow() {
        let oldest = now.addingTimeInterval(-8 * 86_400)
        #expect(TVMazeUpdatePeriod.covering(since: oldest, at: now) == .month)
        #expect(
            TVMazeUpdatePeriod.requiresUnfilteredUpdateMap(since: oldest, at: now) == false
        )
    }

    @Test("Gaps older than a month require the unfiltered updates map")
    func unfilteredMapRequiredAfterMonth() {
        let oldest = now.addingTimeInterval(-(TVMazeUpdatePeriod.monthWindow + 86_400))
        #expect(TVMazeUpdatePeriod.covering(since: oldest, at: now) == .month)
        #expect(TVMazeUpdatePeriod.requiresUnfilteredUpdateMap(since: oldest, at: now))
    }

    /// (gap, expected window, needs the full map). Each window includes its exact
    /// boundary; one second more needs the next. The month boundary is 28 days, a
    /// conservative assumption: TVMaze does not document the length of `since=month`.
    private static let boundaries: [(TimeInterval, TVMazeUpdatePeriod, Bool)] = [
        (86_400, .day, false),
        (86_401, .week, false),
        (604_800, .week, false),
        (604_801, .month, false),
        (2_419_200, .month, false),
        (2_419_201, .month, true),
    ]

    @Test("Window boundaries", arguments: boundaries)
    func windowBoundaries(gap: TimeInterval, period: TVMazeUpdatePeriod, needsFullMap: Bool) {
        let since = now.addingTimeInterval(-gap)
        #expect(TVMazeUpdatePeriod.covering(since: since, at: now) == period)
        #expect(
            TVMazeUpdatePeriod.requiresUnfilteredUpdateMap(since: since, at: now) == needsFullMap)
    }
}
