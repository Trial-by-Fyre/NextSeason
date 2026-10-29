//
//  Show.swift
//  NextSeason
//

import Foundation

/// The app-facing show model. API quirks (HTML summaries, raw date strings,
/// open-ended status) are already resolved here so views never see DTO types.
nonisolated struct Show: Identifiable, Sendable, Hashable {
    let id: Int
    let name: String
    /// The show's page on TVMaze, used for attribution and a "view more" link.
    let tvMazeURL: URL?
    /// Raw TVMaze summary HTML, kept intact so it can be rendered formatted at
    /// display time (see `SummaryFormatter`).
    let summaryHTML: String?
    let posterMediumURL: URL?
    let posterOriginalURL: URL?
    let status: ShowStatus
    let premiered: Date?
    let ended: Date?
    let network: String?
    /// Country of the broadcaster in `network`, from TVMaze. A defaulted `var`
    /// so the memberwise initializer keeps it optional for callers without one.
    var networkCountry: String? = nil
    let genres: [String]
    let averageRuntime: Int?
    let seasons: [Season]
    let nextEpisode: NextEpisode?
    let updatedAt: Date
}
