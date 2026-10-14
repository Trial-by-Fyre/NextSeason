//
//  ShowIDMappingRefreshService.swift
//  NextSeason
//

import Foundation
import os

/// Opportunistic on-device refresh of the TVDB↔TVMaze show ID mapping.
///
/// Never blocks Search or launch. Failures leave the existing writable database
/// untouched aside from whatever partial writes already committed — the bundled
/// baseline remains a recovery path via `ShowIDMappingDatabase`.
///
/// Update passes are newest-first and **resumable**. Each sync captures a fixed
/// upper watermark (`syncHorizonAt`) when it begins. Only updates at or before
/// that horizon are drained; when the backlog finishes, `lastSuccessfulSyncAt`
/// is set to the horizon (not “now”), so changes that arrived mid-drain are
/// picked up on the next sync instead of being skipped forever.
///
/// The updates lower watermark is `lastSuccessfulSyncAt ?? generatedAt`, so a
/// freshly installed bundled database only processes changes newer than the
/// bundled snapshot.
actor ShowIDMappingRefreshService {
    /// Roughly weekly refreshes are enough for search filtering freshness.
    static let refreshInterval: TimeInterval = 7 * 24 * 60 * 60

    /// Cap per opportunity so a large `/updates/shows` window cannot burst.
    static let defaultMaxShowDetailFetchesPerRefresh = 75

    /// Delay between TVMaze calls during refresh (stay under ≥20 / 10s).
    static let defaultRequestPause: Duration = .milliseconds(400)

    private let database: ShowIDMappingDatabase
    private let tvMaze: any TVMazeService
    private let now: @Sendable () -> Date
    private let maxShowDetailFetchesPerRefresh: Int
    private let requestPause: Duration
    private var isRunning = false

    init(
        database: ShowIDMappingDatabase,
        tvMaze: any TVMazeService,
        now: @escaping @Sendable () -> Date = { Date() },
        maxShowDetailFetchesPerRefresh: Int = ShowIDMappingRefreshService
            .defaultMaxShowDetailFetchesPerRefresh,
        requestPause: Duration = ShowIDMappingRefreshService.defaultRequestPause
    ) {
        self.database = database
        self.tvMaze = tvMaze
        self.now = now
        self.maxShowDetailFetchesPerRefresh = maxShowDetailFetchesPerRefresh
        self.requestPause = requestPause
    }

    /// Starts a refresh when due, or continues a capped updates pass.
    /// Safe to call from foreground activation.
    func refreshIfNeeded() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        do {
            let metadata = try await database.metadata()
            if !metadata.hasInProgressSync,
                let lastSync = metadata.lastSuccessfulSyncAt,
                now().timeIntervalSince(lastSync) < Self.refreshInterval
            {
                return
            }

            // Freeze the upper bound for this sync. Mid-drain TVMaze changes after
            // this instant are deferred until the next sync cycle.
            let horizonAt = metadata.syncHorizonAt ?? now()
            if metadata.syncHorizonAt == nil {
                try await database.setSyncHorizonAt(horizonAt)
            }

            AppDiagnosticsLogger.logger(for: .network)
                .notice("show_id_mapping_refresh_start")
            AppDiagnosticsLogger.breadcrumb("show_id_mapping_refresh")

            try await refreshTail(fromHighestID: metadata.highestTVMazeID)
            // Prefer the last completed sync; on first launch fall back to the
            // bundled snapshot's generation time so we only pull genuinely new
            // changes instead of rechecking a default week of already-mapped shows.
            let updatesWatermark = metadata.lastSuccessfulSyncAt ?? metadata.generatedAt
            let updatesFinished = try await refreshUpdatedShows(
                since: updatesWatermark,
                horizonAt: horizonAt,
                resumeCursor: metadata.updatesResumeCursor
            )
            if updatesFinished {
                // Commit the horizon, not wall-clock "now", so anything newer than
                // the horizon remains eligible for the next sync window. Step back
                // by TVMaze's propagation delay: a change made just before the
                // horizon may not have been published yet, so the next sync
                // re-checks that hour (re-applying a mapping is harmless).
                try await database.setLastSuccessfulSyncAt(
                    horizonAt.addingTimeInterval(-TVMazeUpdatePeriod.propagationDelay))
                try await database.clearInProgressSyncState()
                AppDiagnosticsLogger.logger(for: .network)
                    .notice("show_id_mapping_refresh_complete")
            } else {
                AppDiagnosticsLogger.logger(for: .network)
                    .notice("show_id_mapping_refresh_paused")
                AppDiagnosticsLogger.breadcrumb("show_id_mapping_refresh_paused")
            }
        } catch {
            // Non-fatal: keep serving the existing map.
            AppDiagnosticsLogger.logger(for: .network)
                .error(
                    "show_id_mapping_refresh_failed error=\(error.localizedDescription, privacy: .public)"
                )
            AppDiagnosticsLogger.breadcrumb("show_id_mapping_refresh_failed")
        }
    }

    /// Walks TVMaze show-index pages from the local high-water mark to the end.
    private func refreshTail(fromHighestID highestID: Int) async throws {
        var page = max(highestID, 0) / 250
        var highest = highestID
        var emptyPages = 0

        while true {
            let shows: [ShowIndexEntryData]
            do {
                shows = try await tvMaze.showsIndex(page: page)
            } catch TVMazeError.notFound {
                break
            }

            if shows.isEmpty {
                emptyPages += 1
                // Defensive: avoid spinning if the API returns empty pages forever.
                if emptyPages >= 3 { break }
            } else {
                emptyPages = 0
                for entry in shows {
                    if entry.id > highest { highest = entry.id }
                    try await database.applyMapping(
                        tvMazeID: entry.id,
                        tvdbID: entry.externals?.thetvdb,
                        name: entry.name,
                        posterMediumURL: entry.posterMediumURL
                    )
                }
                try await database.setHighestTVMazeID(highest)
            }

            page += 1
            try await Task.sleep(for: requestPause)
            try Task.checkCancellation()
        }
    }

    /// Refreshes mappings for shows TVMaze reports as updated since the last sync.
    ///
    /// - Returns: `true` when the horizon window is fully drained; `false` when
    ///   work remains and a resume cursor was persisted.
    private func refreshUpdatedShows(
        since lastSync: Date?,
        horizonAt: Date,
        resumeCursor: ShowIDMappingResumeCursor?
    ) async throws -> Bool {
        let updates = try await fetchUpdates(since: lastSync, horizonAt: horizonAt)
        let pending = Self.pendingUpdates(
            from: updates,
            updatedAfter: lastSync,
            horizonAt: horizonAt,
            resumeCursor: resumeCursor
        )
        guard !pending.isEmpty else { return true }

        var fetched = 0
        var lastProcessed: ShowIDMappingResumeCursor?
        for item in pending {
            guard fetched < maxShowDetailFetchesPerRefresh else { break }
            do {
                let entry = try await tvMaze.showIndexEntry(id: item.showID)
                try await database.applyMapping(
                    tvMazeID: entry.id,
                    tvdbID: entry.externals?.thetvdb,
                    name: entry.name,
                    posterMediumURL: entry.posterMediumURL
                )
            } catch TVMazeError.notFound {
                // Show removed from TVMaze — drop any local mapping.
                try await database.removeMappings(forTVMazeID: item.showID)
            }
            lastProcessed = item
            fetched += 1
            try await Task.sleep(for: requestPause)
            try Task.checkCancellation()
        }

        let remaining = pending.count - fetched
        if remaining > 0, let lastProcessed {
            // Pause: keep lastSuccessfulSyncAt unchanged and resume older work next time.
            try await database.setUpdatesResumeCursor(lastProcessed)
            return false
        }

        return true
    }

    /// Loads the TVMaze update map for this sync window.
    ///
    /// TVMaze can only filter updates as far back as one month.
    /// For older sync points, fetch the complete show-update map and
    /// locally discard entries whose last-updated timestamp is at or
    /// before our saved sync watermark.
    ///
    /// The window is chosen from the request time, not the frozen horizon:
    /// `since=` is a rolling window ending now, so a sync resumed days after it
    /// started must reach back further. `pendingUpdates` still limits the
    /// result to (`lastSync`, `horizonAt`].
    private func fetchUpdates(
        since lastSync: Date?,
        horizonAt: Date
    ) async throws -> [Int: Date] {
        guard let lastSync else {
            // No trustworthy baseline exists.
            return try await tvMaze.allUpdatedShows()
        }

        let requestTime = now()
        if TVMazeUpdatePeriod.requiresUnfilteredUpdateMap(
            since: lastSync,
            at: requestTime
        ) {
            AppDiagnosticsLogger.breadcrumb("show_id_mapping_updates_unfiltered")
            return try await tvMaze.allUpdatedShows()
        }

        let period = TVMazeUpdatePeriod.covering(
            since: lastSync,
            at: requestTime
        )

        return try await tvMaze.updatedShows(since: period)
    }

    /// Newest-first ordering by update timestamp, then show id for stability.
    ///
    /// Keeps updates strictly after `updatedAfter` (prior sync watermark) and at
    /// or before `horizonAt`. When resuming, also keeps only entries strictly
    /// older than the stored cursor.
    nonisolated static func pendingUpdates(
        from updates: [Int: Date],
        updatedAfter: Date?,
        horizonAt: Date,
        resumeCursor: ShowIDMappingResumeCursor?
    ) -> [ShowIDMappingResumeCursor] {
        let items = updates.compactMap {
            showID, updatedAt -> ShowIDMappingResumeCursor? in
            if let updatedAfter, updatedAt <= updatedAfter { return nil }
            guard updatedAt <= horizonAt else { return nil }
            return ShowIDMappingResumeCursor(updatedAt: updatedAt, showID: showID)
        }
        let filtered: [ShowIDMappingResumeCursor]
        if let resumeCursor {
            filtered = items.filter { Self.isOlderThanCursor($0, resumeCursor) }
        } else {
            filtered = items
        }
        return filtered.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.showID > rhs.showID
        }
    }

    nonisolated private static func isOlderThanCursor(
        _ item: ShowIDMappingResumeCursor,
        _ cursor: ShowIDMappingResumeCursor
    ) -> Bool {
        if item.updatedAt != cursor.updatedAt {
            return item.updatedAt < cursor.updatedAt
        }
        return item.showID < cursor.showID
    }
}
