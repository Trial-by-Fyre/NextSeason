//
//  TrackedShowEntity.swift
//  NextSeason
//

import Foundation
import SwiftData

/// SwiftData persistence model for a watchlist row.
///
/// Mirrors `TrackedShow` but stores types SwiftData handles natively:
/// - `statusRaw` — TVMaze status string (`ShowStatus.persistenceRawValue`)
/// - `nextSeasonSnapshot` — JSON-encoded `NextSeasonStatus` (associated values
///   don’t map cleanly to SwiftData attributes)
///
/// Notification debounce fields (`lastNotifiedSignature`, `pendingChangeSignature`)
/// persist across launches so PD-008 soft-change confirmation survives process death.
///
/// Frozen V1 persistence contract (`NextSeasonSchemaV1.TrackedShowEntity`).
/// Changing stored properties requires `NextSeasonSchemaV2`, not an in-place edit.
///
/// Pre-release exception: `isPaused` was added in place before public release.
/// Beta testers reinstall with a fresh database, so no migration exists for it.
/// From the first App Store release onward, the V2 rule above applies.
///
/// The class name stays `TrackedShowEntity` so `Schema.entityName(for:)` remains
/// the same string used by unversioned TestFlight stores.
extension NextSeasonSchemaV1 {
    @Model
    final class TrackedShowEntity {
        /// TVMaze show ID; unique so a show can appear at most once on the watchlist.
        @Attribute(.unique) var tvMazeID: Int
        var name: String
        var posterMediumURL: URL?
        var summaryHTML: String?
        var tvMazeURL: URL?
        var statusRaw: String
        var nextSeasonSnapshot: Data
        var sourceUpdatedAt: Date
        var lastCheckedAt: Date
        var lastNotifiedSignature: String?
        var pendingChangeSignature: String?
        var isStale: Bool
        var dateAdded: Date
        /// Plus-lapse pause flag. Written only by the repository's `setPaused` and
        /// reactivating `add`, never by `apply(_:)`, so a refresh that loaded the
        /// row before it was paused cannot un-pause it when it writes back.
        var isPaused: Bool = false

        init(tracked: TrackedShow) throws {
            self.tvMazeID = tracked.id
            self.name = tracked.name
            self.posterMediumURL = tracked.posterMediumURL
            self.summaryHTML = tracked.summaryHTML
            self.tvMazeURL = tracked.tvMazeURL
            self.statusRaw = tracked.status.persistenceRawValue
            self.nextSeasonSnapshot = try JSONEncoder().encode(tracked.nextSeason)
            self.sourceUpdatedAt = tracked.sourceUpdatedAt
            self.lastCheckedAt = tracked.lastCheckedAt
            self.lastNotifiedSignature = tracked.lastNotifiedSignature
            self.pendingChangeSignature = tracked.pendingChangeSignature
            self.isStale = tracked.isStale
            self.dateAdded = tracked.dateAdded
            self.isPaused = tracked.isPaused
        }

        /// Updates mutable fields after a refresh. Does not change `tvMazeID` or
        /// `isPaused`.
        ///
        /// `dateAdded` is copied from `tracked`. Refresh writes pass the stored row
        /// back, so it is unchanged there; undoing a delete passes the removed row,
        /// which restores its original save date (free-tier order and the row's
        /// catch-up mark both depend on it). Matches `InMemoryWatchlistRepository`.
        func apply(_ tracked: TrackedShow) throws {
            dateAdded = tracked.dateAdded
            name = tracked.name
            posterMediumURL = tracked.posterMediumURL
            summaryHTML = tracked.summaryHTML
            tvMazeURL = tracked.tvMazeURL
            statusRaw = tracked.status.persistenceRawValue
            nextSeasonSnapshot = try JSONEncoder().encode(tracked.nextSeason)
            sourceUpdatedAt = tracked.sourceUpdatedAt
            lastCheckedAt = tracked.lastCheckedAt
            lastNotifiedSignature = tracked.lastNotifiedSignature
            pendingChangeSignature = tracked.pendingChangeSignature
            isStale = tracked.isStale
        }

        func toDomain() throws -> TrackedShow {
            let nextSeason = try JSONDecoder().decode(
                NextSeasonStatus.self, from: nextSeasonSnapshot)
            return TrackedShow(
                id: tvMazeID,
                name: name,
                posterMediumURL: posterMediumURL,
                summaryHTML: summaryHTML,
                tvMazeURL: tvMazeURL,
                status: ShowStatus(rawValue: statusRaw),
                nextSeason: nextSeason,
                sourceUpdatedAt: sourceUpdatedAt,
                lastCheckedAt: lastCheckedAt,
                lastNotifiedSignature: lastNotifiedSignature,
                pendingChangeSignature: pendingChangeSignature,
                isStale: isStale,
                dateAdded: dateAdded,
                isPaused: isPaused
            )
        }
    }
}

/// Current-schema alias. Point this at `NextSeasonSchemaV2.TrackedShowEntity`
/// when that version becomes current; leave the V1 nested type unchanged.
typealias TrackedShowEntity = NextSeasonSchemaV1.TrackedShowEntity
