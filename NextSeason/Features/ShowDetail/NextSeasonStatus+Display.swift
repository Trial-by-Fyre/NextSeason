//
//  NextSeasonStatus+Display.swift
//  NextSeason
//

import SwiftUI

/// User-facing presentation for `NextSeasonStatus`. Kept in the feature layer so
/// the domain enum stays free of display concerns.
extension NextSeasonStatus {
    /// Safe to call from CSV export and other non-UI code.
    nonisolated var headline: String {
        headline(dateStyle: Date.FormatStyle(date: .abbreviated, time: .omitted))
    }

    /// `dateStyle` supplies the locale (and, in tests, a fixed device time zone).
    /// The premiere keeps its provider calendar day regardless of time zone.
    nonisolated func headline(dateStyle: Date.FormatStyle) -> String {
        switch self {
        case .airing(let season):
            String(localized: "Currently showing Season \(season)")
        case .scheduled(let season, let premiere):
            String(
                localized:
                    "Season \(season) premieres \(TVMazeDate.calendarDayString(premiere, style: dateStyle))",
                locale: dateStyle.locale
            )
        case .announcedUndated(let season):
            String(localized: "Season \(season) announced — date to be confirmed")
        case .returningNoSeasonYet:
            String(localized: "Returning — no next season announced yet")
        case .ended:
            String(localized: "Ended — no next season expected")
        case .unknown:
            String(localized: "Next season status unknown")
        }
    }

    var statusSymbolName: String {
        switch self {
        case .airing:
            "play.tv"
        case .scheduled:
            "calendar"
        case .announcedUndated:
            "calendar.badge.clock"
        case .returningNoSeasonYet:
            "arrow.clockwise"
        case .ended:
            "checkmark.circle"
        case .unknown:
            "questionmark.circle"
        }
    }

    /// Tint for the status icon on show detail. Accent is reserved for
    /// scheduled/airing emphasis; quieter statuses use system hierarchy.
    func emphasisStyle() -> AnyShapeStyle {
        switch self {
        case .scheduled, .airing:
            AnyShapeStyle(AppColor.accent)
        case .announcedUndated, .returningNoSeasonYet, .unknown:
            AnyShapeStyle(.secondary)
        case .ended:
            AnyShapeStyle(.tertiary)
        }
    }
}
