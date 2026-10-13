//
//  PremiereDateDisplayTests.swift
//  NextSeasonTests
//

import Foundation
import Testing

@testable import NextSeason

/// Review finding R02: a TVMaze premiere date must keep its calendar day on every
/// display surface, whatever the device time zone. Each test injects the locale
/// and time zone, so results do not depend on the simulator's settings.
struct PremiereDateDisplayTests {
    /// West of UTC, positive offset, and UTC itself.
    static let deviceTimeZones = ["America/Los_Angeles", "UTC", "Asia/Tokyo"]

    @Test(
        "Shared formatter keeps the provider calendar day",
        arguments: deviceTimeZones
    )
    func calendarDayStringKeepsDay(_ timeZoneID: String) throws {
        let premiere = try #require(TVMazeDate.dateOnly("2027-01-01"))
        let style = try dateStyle(timeZoneID: timeZoneID)

        #expect(TVMazeDate.calendarDayString(premiere, style: style) == "Jan 1, 2027")
    }

    @Test(
        "Next Season headline shows the provider premiere day",
        arguments: deviceTimeZones
    )
    func headlineKeepsDay(_ timeZoneID: String) throws {
        let premiere = try #require(TVMazeDate.dateOnly("2027-01-01"))
        let status = NextSeasonStatus.scheduled(season: 2, premiere: premiere)
        let style = try dateStyle(timeZoneID: timeZoneID)

        #expect(status.headline(dateStyle: style) == "Season 2 premieres Jan 1, 2027")
    }

    @Test(
        "Notification body shows the provider premiere day",
        arguments: deviceTimeZones
    )
    func notificationBodyKeepsDay(_ timeZoneID: String) throws {
        let premiere = try #require(TVMazeDate.dateOnly("2027-01-01"))
        let content = SeasonNotificationContent(
            showID: 1,
            showName: "Example",
            status: .scheduled(season: 2, premiere: premiere)
        )
        let style = try dateStyle(timeZoneID: timeZoneID)

        #expect(content.body(dateStyle: style) == "Season 2 premieres Jan 1, 2027.")
    }

    /// Control: the injected style really carries the device time zone, so the
    /// tests above would catch a formatter that stopped overriding it.
    @Test("Formatting the stored instant in Los Angeles shows the previous day")
    func injectedTimeZoneShiftsPlainFormatting() throws {
        let premiere = try #require(TVMazeDate.dateOnly("2027-01-01"))
        let style = try dateStyle(timeZoneID: "America/Los_Angeles")

        #expect(premiere.formatted(style) == "Dec 31, 2026")
    }

    /// Mirrors the app's default style, with a fixed locale and device time zone.
    private func dateStyle(timeZoneID: String) throws -> Date.FormatStyle {
        let timeZone = try #require(TimeZone(identifier: timeZoneID))
        return Date.FormatStyle(
            date: .abbreviated,
            time: .omitted,
            locale: Locale(identifier: "en_US"),
            calendar: Calendar(identifier: .gregorian),
            timeZone: timeZone
        )
    }
}
