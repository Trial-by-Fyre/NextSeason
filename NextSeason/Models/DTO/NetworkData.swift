//
//  NetworkData.swift
//  NextSeason
//

import Foundation

/// A TVMaze `network` or `webChannel`. The app uses the name and, on show
/// detail, the country of original broadcast.
nonisolated struct NetworkData: Codable, Sendable {
    let id: Int?
    let name: String?
    /// Null for global streaming services (e.g. Netflix's `webChannel`).
    let country: CountryData?

    /// TVMaze `country` object; only the display name is needed.
    nonisolated struct CountryData: Codable, Sendable {
        let name: String?
    }
}
