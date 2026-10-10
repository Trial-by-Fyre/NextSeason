//
//  WatchlistRepository.swift
//  NextSeason
//

import Foundation

/// Persistence boundary for saved shows. View models depend on this protocol, not
/// on SwiftData directly (PD-007).
///
/// Production: `SwiftDataWatchlistRepository`. UI tests / previews:
/// `InMemoryWatchlistRepository`.
///
/// "Saved" queries (`all`, `trackedShow`, `trackedShowIDs`, `contains`) include
/// paused shows — a paused show is still on the Watchlist. Use `activeShowIDs()`
/// for anything that means "actively tracked" (free-limit count, star state).
@MainActor
protocol WatchlistRepository: AnyObject {
    /// All saved shows (active and paused), newest `dateAdded` first.
    func all() async throws -> [TrackedShow]
    func trackedShow(showID: Int) async throws -> TrackedShow?
    /// IDs of every saved show, including paused ones.
    func trackedShowIDs() async throws -> Set<Int>
    /// True when the show is saved, including when it is paused.
    func contains(showID: Int) async throws -> Bool
    /// IDs of saved shows that are not paused.
    func activeShowIDs() async throws -> Set<Int>
    /// Insert from a fully loaded `Show`. A second add of an active show is a
    /// no-op; adding a paused show reactivates that row (keeping its original
    /// `dateAdded`) with fresh show data instead of creating a duplicate.
    func add(_ show: Show) async throws
    /// No-op when the ID is not present.
    func remove(showID: Int) async throws
    /// Writes refresh / notification-debounce fields onto an existing row.
    /// Never changes `isPaused`.
    func updateAfterRefresh(_ tracked: TrackedShow) async throws
    /// Sets `isPaused` on the given saved rows; missing IDs are ignored.
    func setPaused(_ isPaused: Bool, showIDs: Set<Int>) async throws
}

extension WatchlistRepository {
    /// Default derived from `all()`; production overrides with a direct query.
    func activeShowIDs() async throws -> Set<Int> {
        Set(try await all().filter { !$0.isPaused }.map(\.id))
    }
}
