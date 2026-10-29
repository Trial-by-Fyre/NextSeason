//
//  TrackedShow.swift
//  NextSeason
//

import Foundation

/// A show the user is monitoring for next-season changes. Stored on-device only.
///
/// Refresh, notification debounce, and SwiftData persistence all share this
/// shape; signatures and timestamps below drive PD-008 change detection.
nonisolated struct TrackedShow: Identifiable, Sendable, Hashable {
    let id: Int
    var name: String
    var posterMediumURL: URL?
    var summaryHTML: String?
    var tvMazeURL: URL?
    /// TVMaze network or web channel name (`Show.network`), shown on airing and
    /// scheduled Watchlist rows. Display-only: not part of change detection.
    var broadcasterName: String?
    var status: ShowStatus
    var nextSeason: NextSeasonStatus
    /// TVMaze's `updated` timestamp for this show; used to skip re-fetch when
    /// `/updates/shows` reports no newer change.
    var sourceUpdatedAt: Date
    /// Last time we successfully refreshed this row (policy / diagnostics).
    var lastCheckedAt: Date
    /// Signature of the last status we already notified about; suppresses repeat
    /// alerts for the same change (`StatusChangeDetector`).
    var lastNotifiedSignature: String?
    /// When a non-date-backed change is first seen, holds its signature until a
    /// second poll confirms it (PD-008 debounce).
    var pendingChangeSignature: String?
    /// True when TVMaze no longer returns this show (merged/deleted).
    var isStale: Bool
    var dateAdded: Date
    /// True when a lapsed Plus subscription left this show beyond the free limit.
    /// Paused shows stay saved but are not refreshed, notified, or opened.
    var isPaused: Bool

    init(
        id: Int,
        name: String,
        posterMediumURL: URL?,
        summaryHTML: String? = nil,
        tvMazeURL: URL? = nil,
        broadcasterName: String? = nil,
        status: ShowStatus,
        nextSeason: NextSeasonStatus,
        sourceUpdatedAt: Date,
        lastCheckedAt: Date,
        lastNotifiedSignature: String? = nil,
        pendingChangeSignature: String? = nil,
        isStale: Bool = false,
        dateAdded: Date,
        isPaused: Bool = false
    ) {
        self.id = id
        self.name = name
        self.posterMediumURL = posterMediumURL
        self.summaryHTML = summaryHTML
        self.tvMazeURL = tvMazeURL
        self.broadcasterName = broadcasterName
        self.status = status
        self.nextSeason = nextSeason
        self.sourceUpdatedAt = sourceUpdatedAt
        self.lastCheckedAt = lastCheckedAt
        self.lastNotifiedSignature = lastNotifiedSignature
        self.pendingChangeSignature = pendingChangeSignature
        self.isStale = isStale
        self.dateAdded = dateAdded
        self.isPaused = isPaused
    }

    /// Fresh data for reactivating a paused row from a newly loaded show. Keeps
    /// the original `dateAdded` (free-tier ordering) and last-notified signature
    /// (no repeat alert for a state already announced); clears pause and debounce.
    init(reactivating existing: TrackedShow, from show: Show, at: Date = .now) {
        self.init(from: show, at: at)
        dateAdded = existing.dateAdded
        lastNotifiedSignature = existing.lastNotifiedSignature
    }

    /// Builds a tracked row from a fully-loaded show at save time.
    init(from show: Show, at: Date = .now) {
        self.init(
            id: show.id,
            name: show.name,
            posterMediumURL: show.posterMediumURL,
            summaryHTML: show.summaryHTML,
            tvMazeURL: show.tvMazeURL,
            broadcasterName: show.network,
            status: show.status,
            nextSeason: NextSeasonCalculator.status(for: show, at: at),
            sourceUpdatedAt: show.updatedAt,
            lastCheckedAt: at,
            dateAdded: at
        )
    }
}

extension Show {
    /// A lightweight show for navigation from the watchlist; detail reloads full data.
    init(tracked: TrackedShow) {
        self.init(
            id: tracked.id,
            name: tracked.name,
            tvMazeURL: tracked.tvMazeURL,
            summaryHTML: tracked.summaryHTML,
            posterMediumURL: tracked.posterMediumURL,
            posterOriginalURL: nil,
            status: tracked.status,
            premiered: nil,
            ended: nil,
            network: nil,
            genres: [],
            averageRuntime: nil,
            seasons: [],
            nextEpisode: nil,
            updatedAt: tracked.sourceUpdatedAt
        )
    }
}
