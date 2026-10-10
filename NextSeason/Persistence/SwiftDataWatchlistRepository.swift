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
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
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
        if let existing = try entity(for: show.id) {
            guard existing.isPaused else { return }
            try existing.apply(TrackedShow(reactivating: try existing.toDomain(), from: show))
            existing.isPaused = false
            try context.save()
            return
        }
        let tracked = TrackedShow(from: show)
        context.insert(try TrackedShowEntity(tracked: tracked))
        try context.save()
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
        for entity in try context.fetch(descriptor) {
            entity.isPaused = isPaused
        }
        try context.save()
    }

    /// No-op if the show is not on the watchlist.
    func remove(showID: Int) async throws {
        AppDiagnosticsLogger.logger(for: .persistence)
            .notice("watchlist_write_remove show_id=\(showID, privacy: .public)")
        AppDiagnosticsLogger.breadcrumb("watchlist_remove:\(showID)")
        guard let entity = try entity(for: showID) else { return }
        context.delete(entity)
        try context.save()
    }

    /// Applies refresh fields onto an existing row. No-op if the show was removed
    /// between fetch and write (e.g. user untracked during a background refresh).
    func updateAfterRefresh(_ tracked: TrackedShow) async throws {
        AppDiagnosticsLogger.logger(for: .persistence)
            .notice("watchlist_write_refresh show_id=\(tracked.id, privacy: .public)")
        AppDiagnosticsLogger.breadcrumb("watchlist_refresh_write:\(tracked.id)")
        guard let entity = try entity(for: tracked.id) else { return }
        try entity.apply(tracked)
        try context.save()
    }

    private func entity(for showID: Int) throws -> TrackedShowEntity? {
        var descriptor = FetchDescriptor<TrackedShowEntity>(
            predicate: #Predicate { $0.tvMazeID == showID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
