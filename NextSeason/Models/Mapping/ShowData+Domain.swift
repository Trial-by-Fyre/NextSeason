//
//  ShowData+Domain.swift
//  NextSeason
//
//  Maps network DTOs into clean domain models. Kept separate so the API shape
//  and the app's model can evolve independently.
//

import Foundation

// From the agent supervisor: I was not familiar with using the term domain in
// this way, so I asked Cursor what it meant by it. It said “the app’s own idea
// of the data”, which is distinct from what the API sent and said it's
// sometimes referred to as an app model or business model.

extension ShowData {
    /// Converts a TVMaze show payload into the app's `Show` model.
    ///
    /// Date-only fields go through `TVMazeDate.dateOnly` (UTC calendar days).
    /// Streaming-only titles often have `webChannel` instead of `network`; we
    /// surface whichever name is present. Missing `updated` becomes
    /// `.distantPast` so refresh comparisons treat the show as never updated
    /// rather than colliding with a real timestamp.
    nonisolated func toDomain() -> Show {
        Show(
            id: id,
            name: name,
            tvMazeURL: url.flatMap(URL.init(string:)),
            summaryHTML: summary,
            posterMediumURL: image?.medium.flatMap(URL.init(string:)),
            posterOriginalURL: image?.original.flatMap(URL.init(string:)),
            status: ShowStatus(rawValue: status),
            premiered: TVMazeDate.dateOnly(premiered),
            ended: TVMazeDate.dateOnly(ended),
            // Prefer broadcast network; fall back to streaming webChannel.
            network: network?.name ?? webChannel?.name,
            genres: genres ?? [],
            averageRuntime: averageRuntime,
            seasons: (embedded?.seasons ?? []).map { $0.toDomain() },
            nextEpisode: embedded?.nextepisode.map {
                NextEpisode(
                    season: $0.season, number: $0.number, airdate: TVMazeDate.dateOnly($0.airdate))
            },
            // Unix seconds from TVMaze; absent → sentinel so "never updated" sorts earliest.
            updatedAt: updated.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? .distantPast
        )
    }
}

extension SeasonData {
    /// Maps a season DTO; premiere/end stay nil when TVMaze has announced but not scheduled.
    nonisolated func toDomain() -> Season {
        Season(
            id: id,
            number: number,
            premiereDate: TVMazeDate.dateOnly(premiereDate),
            endDate: TVMazeDate.dateOnly(endDate),
            episodeOrder: episodeOrder
        )
    }
}
