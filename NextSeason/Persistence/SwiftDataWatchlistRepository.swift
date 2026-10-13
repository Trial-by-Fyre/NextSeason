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

    /// `save` is a test seam for forcing a save failure; production uses the default.
    init(context: ModelContext, save: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.context = context
        self.save = save
    }

    /// Newest saves first (`dateAdded` descending).
    func all() async throws -> [TrackedShow] {
        AppDiagnosticsLogger.logger(for: .persistence).notice("watchlist_read_all start")
        AppDiagnosticsLogger.breadcrumb("watchlist_read_all")
        let descriptor = FetchDescriptor<TrackedShowEntity>(
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
        let result = try context.fetch(descriptor).map { try $0.toDomain() }
        AppDiagnosticsLogger.logger(for: .persistence)
            .notice("watchlist_read_all complete count=\(result.count, privacy: .public)")
        return result
    }

    func trackedShow(showID: Int) async throws -> TrackedShow? {
        guard let entity = try entity(for: showID) else { return nil }
        return try entity.toDomain()
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
                try existing.apply(TrackedShow(reactivating: try existing.toDomain(), from: show))
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

    private func entity(for showID: Int) throws -> TrackedShowEntity? {
        var descriptor = FetchDescriptor<TrackedShowEntity>(
            predicate: #Predicate { $0.tvMazeID == showID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
