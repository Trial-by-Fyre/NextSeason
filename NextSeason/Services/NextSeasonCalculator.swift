//
//  NextSeasonCalculator.swift
//  NextSeason
//

import Foundation

/// Derives a `NextSeasonStatus` from a show's status, seasons, and next episode.
///
/// TVMaze has no single "next season" field, so this is the one place that rule
/// lives. Pure and date-injectable (`at:`) so unit tests can pin the calendar;
/// shared by show detail, watchlist save, and `WatchlistRefreshService`.
///
/// Rerun-safe by construction: it keys only off original season premiere dates and
/// the next *unaired* episode, none of which a re-broadcast changes
/// (see `Documentation/TVMazeResearch.md` §6.3).
nonisolated enum NextSeasonCalculator {
    /// Priority order: dated upcoming season → next-episode hint → currently
    /// airing latest season → undated upcoming row → overall show status.
    ///
    /// - Parameter show: Domain show whose seasons and next episode drive the status.
    /// - Parameter at: Reference "today" for premiere / end comparisons (UTC days).
    static func status(for show: Show, at: Date = .now) -> NextSeasonStatus {
        // Ignore specials / season 0 for "next season" purposes.
        let seasons = show.seasons
            .filter { $0.number >= 1 }
            .sorted { $0.number < $1.number }

        let aired = seasons.filter { season in
            if let date = season.premiereDate { return TVMazeDate.isOnOrBefore(date, at) }
            return false
        }
        let latestAired = aired.last
        let latestAiredNumber = latestAired?.number ?? 0

        // Seasons numbered beyond the latest one that has actually aired.
        let upcoming = seasons.filter { $0.number > latestAiredNumber }

        // 1. A not-yet-aired season with a known future premiere date.
        let datedUpcoming =
            upcoming
            .compactMap { season -> (number: Int, date: Date)? in
                guard let date = season.premiereDate, TVMazeDate.isAfter(date, at) else {
                    return nil
                }
                return (season.number, date)
            }
            .sorted { $0.date < $1.date }
        if let next = datedUpcoming.first {
            return .scheduled(season: next.number, premiere: next.date)
        }

        // 2. The next episode points at a season beyond the latest aired one —
        //    useful when that new season has no dated row yet.
        if let episode = show.nextEpisode,
            let season = episode.season,
            season > latestAiredNumber
        {
            if let date = episode.airdate {
                if TVMazeDate.isAfter(date, at) {
                    // Only episode 1's date is the premiere. A later episode or a
                    // special (no number) proves the season exists, not when it
                    // starts (review finding R09).
                    guard episode.number == 1 else {
                        return .announcedUndated(season: season)
                    }
                    return .scheduled(season: season, premiere: date)
                }
                // Only episode 1 airing on or before today means the new season
                // is underway; a dated later episode is not premiere evidence.
                // When the season row still has no premiere date, status may
                // read `.airing` on episode 1's day and revert to
                // `.announcedUndated` after TVMaze advances the next-episode
                // pointer (see `episodeOnePremiereDayOscillatesWhenPointerAdvances`).
                guard episode.number == 1 else {
                    return .announcedUndated(season: season)
                }
                return .airing(season: season)
            }
            // Next episode exists for a new season but no date yet — announced, not airing.
            return .announcedUndated(season: season)
        }

        // 3. The most recent season is currently airing (premiered, not yet ended).
        if show.status != .ended, let latest = latestAired {
            let hasEnded = latest.endDate.map { TVMazeDate.isBefore($0, at) } ?? false
            if !hasEnded {
                return .airing(season: latest.number)
            }
        }

        // 4. A future season row exists but has no date yet.
        if let undated = upcoming.first(where: { $0.premiereDate == nil }) {
            return .announcedUndated(season: undated.number)
        }

        // 5. Fall back to the show's overall status.
        switch show.status {
        case .running, .toBeDetermined, .inDevelopment:
            return .returningNoSeasonYet
        case .ended:
            return .ended
        case .unknown:
            return .unknown
        }
    }
}
