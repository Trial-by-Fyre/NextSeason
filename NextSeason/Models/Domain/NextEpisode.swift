//
//  NextEpisode.swift
//  NextSeason
//

import Foundation

/// The show's next scheduled episode, when one exists. `season` indicates which
/// season that upcoming episode belongs to — a useful signal for detecting a new
/// season that doesn't yet have its own dated season row.
///
/// `number` is the episode's number within that season. TVMaze sends `null`
/// for specials, so `nil` must not be read as episode 1.
nonisolated struct NextEpisode: Sendable, Hashable {
    let season: Int?
    let number: Int?
    let airdate: Date?
}
