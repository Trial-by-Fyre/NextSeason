//
//  ExternalLinks.swift
//  NextSeason
//

import Foundation

/// Websites opened from About: NextSeason support and the TVMaze credit link.
///
/// TVMaze licenses its data under CC BY-SA and asks apps to satisfy attribution
/// by linking back to TVMaze (https://www.tvmaze.com/api#licensing). TheTVDB's
/// credit link lives in `TheTVDBConfiguration.websiteURL`; legal links shared
/// with the Plus paywall live in `StoreLegalLinks`.
nonisolated enum ExternalLinks {
    /// Support page on the NextSeason website.
    static let support = URL(string: "https://getnextseason.com/support.html")!

    /// TVMaze home page for the data credit.
    static let tvMaze = URL(string: "https://www.tvmaze.com")!
}
