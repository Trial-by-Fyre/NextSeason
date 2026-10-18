//
//  SwiftDataWatchlistRepository.swift
//  NextSeason
//

import Foundation
import SwiftData
import os

/// Production `WatchlistRepository` backed by SwiftData / `TrackedShowEntity`.
///
/// `@MainActor` because `ModelContext` is main-actor bound. Callers (view models,
/// refresh) already hop to the main actor before awaiting these methods.
@MainActor
final class SwiftDataWatchlistRepository: WatchlistRepository {
    /// Replaced after a failed write; see `performWrite`.
    private var context: ModelContext
    private let save: (ModelContext) throws -> Void
    /// Repair marks for rows with an undecodable snapshot; see `domain(_:)`.
    private let rowMarks: WatchlistRowMarks
    private let analytics: (any AnalyticsTracking)?

    /// `save` is a test seam for forcing a save failure; production uses the default.
    /// `rowMarks` must use the refresh service's defaults so it sees repair marks.
    init(
        context: ModelContext,
        rowMarks: WatchlistRowMarks = WatchlistRowMarks(userDefaults: .standard),
        analytics: (any AnalyticsTracking)? = nil,
        save: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.context = context
        self.rowMarks = rowMarks
        self.analytics = analytics
        self.save = save
    }

    /// Newest saves first (`dateAdded` descending).
    func all() async throws -> [TrackedShow] {
        AppDiagnosticsLogger.logger(for: .persistence).notice("watchlist_read_all start")
        AppDiagnosticsLogger.breadcrumb("watchlist_read_all")
        let descriptor = FetchDescriptor<TrackedShowEntity>(
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
        let result = try context.fetch(descriptor).map(domain)
        AppDiagnosticsLogger.logger(for: .persistence)
            .notice("watchlist_read_all complete count=\(result.count, privacy: .public)")
        return result
    }

    func trackedShow(showID: Int) async throws -> TrackedShow? {
        guard let entity = try entity(for: showID) else { return nil }
        return domain(entity)
    }

    func trackedShowIDs() async throws -> Set<Int> {
        let descriptor = FetchDescriptor<TrackedShowEntity>()
        return Set(try context.fetch(descriptor).map(\.tvMazeID))
    }

    func contains(showID: Int) async throws -> Bool {
        var descriptor = FetchDescriptor<TrackedShowEntity>(
            predicate: #Predicate { $0.tvMazeID == showID }
        )
        descriptor.fetchLimit = 1
        return try context.fetchCount(descriptor) > 0
    }

    func activeShowIDs() async throws -> Set<Int> {
        let descriptor = FetchDescriptor<TrackedShowEntity>(
            predicate: #Predicate { $0.isPaused == false }
        )
        return Set(try context.fetch(descriptor).map(\.tvMazeID))
    }

    /// Idempotent for active rows. A paused row is reactivated in place with
    /// fresh show data, keeping its original `dateAdded`.
    func add(_ show: Show) async throws {
        AppDiagnosticsLogger.logger(for: .persistence)
            .notice("watchlist_write_add show_id=\(show.id, privacy: .public)")
        AppDiagnosticsLogger.breadcrumb("watchlist_add:\(show.id)")
        try performWrite {
            if let existing = try entity(for: show.id) {
                guard existing.isPaused else { return }
                try existing.apply(TrackedShow(reactivating: domain(existing), from: show))
                existing.isPaused = false
                return
            }
            let tracked = TrackedShow(from: show)
            context.insert(try TrackedShowEntity(tracked: tracked))
        }
    }

    func setPaused(_ isPaused: Bool, showIDs: Set<Int>) async throws {
        guard !showIDs.isEmpty else { return }
        AppDiagnosticsLogger.logger(for: .persistence)
            .notice(
                "watchlist_write_paused paused=\(isPaused, privacy: .public) count=\(showIDs.count, privacy: .public)"
            )
        AppDiagnosticsLogger.breadcrumb("watchlist_set_paused:\(isPaused):\(showIDs.count)")
        let ids = Array(showIDs)
        let descriptor = FetchDescriptor<TrackedShowEntity>(
            predicate: #Predicate { ids.contains($0.tvMazeID) }
        )
        try performWrite {
            for entity in try context.fetch(descriptor) {
                entity.isPaused = isPaused
            }
        }
    }

    /// No-op if the show is not on the watchlist.
    func remove(showID: Int) async throws {
        AppDiagnosticsLogger.logger(for: .persistence)
            .notice("watchlist_write_remove show_id=\(showID, privacy: .public)")
        AppDiagnosticsLogger.breadcrumb("watchlist_remove:\(showID)")
        try performWrite {
            guard let entity = try entity(for: showID) else { return }
            context.delete(entity)
        }
    }

    /// Re-inserts a row removed by immediate swipe-delete Undo (R10).
    func restoreRemoved(_ tracked: TrackedShow, isPaused: Bool) async throws {
        AppDiagnosticsLogger.logger(for: .persistence)
            .notice(
                "watchlist_write_restore_removed show_id=\(tracked.id, privacy: .public) paused=\(isPaused, privacy: .public)"
            )
        AppDiagnosticsLogger.breadcrumb("watchlist_restore_removed:\(tracked.id):\(isPaused)")
        var row = tracked
        row.isPaused = isPaused
        try performWrite {
            if try entity(for: tracked.id) != nil { return }
            context.insert(try TrackedShowEntity(tracked: row))
        }
    }

    /// Applies refresh fields onto an existing row. No-op if the show was removed
    /// between fetch and write (e.g. user untracked during a background refresh).
    func updateAfterRefresh(_ tracked: TrackedShow) async throws {
        AppDiagnosticsLogger.logger(for: .persistence)
            .notice("watchlist_write_refresh show_id=\(tracked.id, privacy: .public)")
        AppDiagnosticsLogger.breadcrumb("watchlist_refresh_write:\(tracked.id)")
        try performWrite {
            guard let entity = try entity(for: tracked.id) else { return }
            try entity.apply(tracked)
        }
    }

    /// One guarded write inside `performWrite`, so a failed restore is rolled back
    /// like any other write (R03 scenario 17). Touches only the two signatures.
    @discardableResult
    func restoreUndeliveredNotification(
        _ attempt: TrackedShow, previousLastNotifiedSignature: String?
    ) async throws -> Bool {
        AppDiagnosticsLogger.logger(for: .persistence)
            .notice("watchlist_write_restore_undelivered show_id=\(attempt.id, privacy: .public)")
        AppDiagnosticsLogger.breadcrumb("watchlist_restore_undelivered:\(attempt.id)")
        var restored = false
        try performWrite {
            guard let entity = try entity(for: attempt.id),
                StatusChangeDetector.isStillCurrent(domain(entity), decidedBy: attempt)
            else { return }
            entity.lastNotifiedSignature = previousLastNotifiedSignature
            entity.pendingChangeSignature = attempt.lastNotifiedSignature
            restored = true
        }
        return restored
    }

    /// Runs one logical write and saves it. If any step throws (a failed save, or
    /// `apply` failing partway), rolls the context back so later reads do not see
    /// the failed change and a later save cannot commit it.
    ///
    /// Rolling back alone is not enough on iOS 18: after a save the store rejected,
    /// the next fetch on the rolled-back context still returned the discarded
    /// insert or omitted the discarded delete once. Fresh contexts read correctly,
    /// so the repository switches to a new context on the same container.
    ///
    /// Discarding the context is safe because it belongs to the repository alone
    /// (autosave off), and every write saves or rolls back here without awaiting,
    /// so it never holds another operation's unsaved work. Models never leave
    /// the repository, so no caller keeps objects from the old context.
    private func performWrite(_ mutate: () throws -> Void) throws {
        do {
            try mutate()
            try save(context)
        } catch {
            context.rollback()
            context = ModelContext(context.container)
            AppDiagnosticsLogger.logger(for: .persistence).error(
                "watchlist_write_rolled_back error=\(String(describing: error), privacy: .public)"
            )
            throw error
        }
    }

    /// Every path that turns a saved row into a `TrackedShow` goes through here.
    ///
    /// An undecodable next-season snapshot must not hide the row or the rest of the
    /// watchlist (review finding R13). The row is marked for a silent repair
    /// baseline before any caller sees it, then returned with `.unknown`. Marking
    /// first means an action that rewrites the row, such as Undo or reactivation,
    /// cannot erase the repair. Damage is recognized only by a decode failure, and
    /// nothing here rewrites the damaged snapshot; a successful repair write does.
    private func domain(_ entity: TrackedShowEntity) -> TrackedShow {
        do {
            return try entity.toDomain()
        } catch {
            recordDamage(entity, error: error)
            return entity.toDomain(nextSeason: .unknown)
        }
    }

    /// Marks a damaged row for repair and reports the first detection only. The
    /// report is tracked apart from the mark: a resumed row may already carry a
    /// mark when its damage is first found.
    private func recordDamage(_ entity: TrackedShowEntity, error: Error) {
        let showID = entity.tvMazeID
        let dateAdded = entity.dateAdded.timeIntervalSinceReferenceDate
        rowMarks.catchUp[showID] = dateAdded
        guard rowMarks.damageReported[showID] != dateAdded else { return }
        rowMarks.damageReported[showID] = dateAdded
        AppDiagnosticsLogger.logger(for: .persistence).error(
            "watchlist_snapshot_damaged show_id=\(showID, privacy: .public) error=\(String(describing: error), privacy: .public)"
        )
        analytics?.trackNonFatalError(error, context: "watchlist_snapshot_damaged")
    }

    private func entity(for showID: Int) throws -> TrackedShowEntity? {
        var descriptor = FetchDescriptor<TrackedShowEntity>(
            predicate: #Predicate { $0.tvMazeID == showID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
