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
    /// Re-inserts a row removed by immediate swipe-delete Undo in one write, with
    /// the intended pause state and preserved refresh metadata / `dateAdded`.
    func restoreRemoved(_ tracked: TrackedShow, isPaused: Bool) async throws
    /// After `attempt`'s notification definitely failed to schedule (review
    /// finding R03), restores `previousLastNotifiedSignature` and makes the
    /// undelivered signature pending, so the next poll that sees the same status
    /// announces it. Applies only while the stored row passes
    /// `StatusChangeDetector.isStillCurrent`. Returns whether it applied.
    @discardableResult
    func restoreUndeliveredNotification(
        _ attempt: TrackedShow, previousLastNotifiedSignature: String?
    ) async throws -> Bool
}

extension WatchlistRepository {
    /// Default derived from `all()`; production overrides with a direct query.
    func activeShowIDs() async throws -> Set<Int> {
        Set(try await all().filter { !$0.isPaused }.map(\.id))
    }

    /// Default for test doubles, composed from a read and a refresh write. The
    /// app's repositories implement it as a single write.
    @discardableResult
    func restoreUndeliveredNotification(
        _ attempt: TrackedShow, previousLastNotifiedSignature: String?
    ) async throws -> Bool {
        guard var stored = try await trackedShow(showID: attempt.id),
            StatusChangeDetector.isStillCurrent(stored, decidedBy: attempt)
        else { return false }
        stored.lastNotifiedSignature = previousLastNotifiedSignature
        stored.pendingChangeSignature = attempt.lastNotifiedSignature
        try await updateAfterRefresh(stored)
        return true
    }
}
