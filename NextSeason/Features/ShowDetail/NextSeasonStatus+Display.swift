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

    /// Watchlist row wording: the stored broadcaster on airing and scheduled rows,
    /// without the country so typical names fit on one line. Same phrasing as
    /// show detail, sharing its blank-name handling. CSV export intentionally
    /// keeps the shared `headline`.
    nonisolated func watchlistHeadline(
        broadcaster: String?,
        dateStyle: Date.FormatStyle = Date.FormatStyle(date: .abbreviated, time: .omitted)
    ) -> String {
        detailHeadline(broadcaster: broadcaster, country: nil, dateStyle: dateStyle)
    }

    /// Show detail wording. TVMaze schedules describe the original broadcast, not
    /// availability in the user's country, so airing and scheduled seasons name
    /// the broadcaster (and its country when known). Other statuses keep the
    /// shared `headline`: an undated announcement isn't tied to a broadcaster in
    /// the data, so naming one could imply it confirmed the season.
    nonisolated func detailHeadline(
        broadcaster: String?,
        country: String?,
        dateStyle: Date.FormatStyle = Date.FormatStyle(date: .abbreviated, time: .omitted)
    ) -> String {
        let broadcast = Self.broadcastLabel(broadcaster: broadcaster, country: country)
        switch self {
        case .airing(let season):
            guard let broadcast else {
                return String(localized: "Season \(season) currently airing")
            }
            return String(localized: "Season \(season) airing on \(broadcast)")
        case .scheduled(let season, let premiere):
            guard let broadcast else { return headline(dateStyle: dateStyle) }
            return String(
                localized:
                    "Season \(season) premieres \(TVMazeDate.calendarDayString(premiere, style: dateStyle)) on \(broadcast)",
                locale: dateStyle.locale
            )
        case .announcedUndated, .returningNoSeasonYet, .ended, .unknown:
            return headline(dateStyle: dateStyle)
        }
    }

    /// "CBC Gem (Canada)", or just the broadcaster when the country is missing.
    /// Blank provider values are treated as missing.
    private nonisolated static func broadcastLabel(broadcaster: String?, country: String?)
        -> String?
    {
        guard let broadcaster = broadcaster?.trimmingCharacters(in: .whitespaces),
            !broadcaster.isEmpty
        else { return nil }
        guard let country = country?.trimmingCharacters(in: .whitespaces), !country.isEmpty else {
            return broadcaster
        }
        return String(localized: "\(broadcaster) (\(country))")
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
