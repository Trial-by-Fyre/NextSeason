//
//  TVMazeDate.swift
//  NextSeason
//

import Foundation

/// Parses TVMaze date-only strings ("yyyy-MM-dd"). Implemented without a shared
/// `DateFormatter` so it is safe to call from any concurrency context.
///
/// TVMaze date-only fields represent calendar days in UTC. Comparisons against
/// `Date.now` should use the helpers below so a season ending "today" is not
/// treated as ended for most of that day.
nonisolated enum TVMazeDate {
    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// UTC calendar-day boundary for TVMaze date-only comparisons.
    static func startOfDayUTC(_ date: Date) -> Date {
        utcCalendar.startOfDay(for: date)
    }

    /// True when `date`'s calendar day is on or before `other`'s (UTC).
    static func isOnOrBefore(_ date: Date, _ other: Date) -> Bool {
        startOfDayUTC(date) <= startOfDayUTC(other)
    }

    /// True when `date`'s calendar day is strictly before `other`'s (UTC).
    static func isBefore(_ date: Date, _ other: Date) -> Bool {
        startOfDayUTC(date) < startOfDayUTC(other)
    }

    /// True when `date`'s calendar day is strictly after `other`'s (UTC).
    static func isAfter(_ date: Date, _ other: Date) -> Bool {
        startOfDayUTC(date) > startOfDayUTC(other)
    }

    /// Formats a TVMaze date-only value for display, keeping its calendar day.
    ///
    /// Provider dates are stored as midnight UTC (see `dateOnly`), so formatting
    /// them in the device time zone shows the previous day west of UTC. `style`
    /// supplies the user's locale and calendar; its time zone is replaced with UTC.
    /// Use only for provider calendar dates, never for real instants such as
    /// `dateAdded` or `lastCheckedAt`, which belong in the user's local time.
    static func calendarDayString(
        _ date: Date,
        style: Date.FormatStyle = Date.FormatStyle(date: .abbreviated, time: .omitted)
    ) -> String {
        var style = style
        style.timeZone = utcCalendar.timeZone
        return date.formatted(style)
    }

    /// Parses a TVMaze `"yyyy-MM-dd"` (or longer ISO) string as a UTC calendar date.
    static func dateOnly(_ string: String?) -> Date? {
        guard let string, string.count >= 10 else { return nil }
        let parts = string.prefix(10).split(separator: "-")
        guard parts.count == 3,
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            let day = Int(parts[2])
        else {
            return nil
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return utcCalendar.date(from: components)
    }
}
