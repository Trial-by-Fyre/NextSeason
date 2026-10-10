//
//  WatchlistTrackingState.swift
//  NextSeason
//

import Foundation

/// Resolves UI-facing "tracked" state from persistence plus any pending
/// undoable removal. Search, detail, and other surfaces should use this so
/// "currently tracked" does not depend on which screen recomputed it.
///
/// "Persisted" here means *active*: a paused show (Plus lapsed) is saved but not
/// tracked, so its star is empty and tapping it goes through the add path,
/// which reactivates the saved row or presents the paywall.
enum WatchlistTrackingState {
    /// True when the show is persisted and not currently pending undoable removal.
    static func isTracked(
        showID: Int,
        isPersisted: Bool,
        pendingRemovalID: Int?
    ) -> Bool {
        isPersisted && pendingRemovalID != showID
    }

    /// Persisted IDs with any pending removal excluded.
    static func trackedIDs(
        persistedIDs: Set<Int>,
        pendingRemovalID: Int?
    ) -> Set<Int> {
        guard let pendingRemovalID else { return persistedIDs }
        var ids = persistedIDs
        ids.remove(pendingRemovalID)
        return ids
    }

    /// Reads persistence and applies pending-removal exclusion.
    @MainActor
    static func isTracked(
        showID: Int,
        repository: any WatchlistRepository,
        removalCoordinator: WatchlistPendingRemoval?
    ) async throws -> Bool {
        let isPersisted = try await repository.activeShowIDs().contains(showID)
        return isTracked(
            showID: showID,
            isPersisted: isPersisted,
            pendingRemovalID: removalCoordinator?.pendingRemoval?.id
        )
    }

    /// Reads all persisted IDs and applies pending-removal exclusion.
    @MainActor
    static func trackedIDs(
        repository: any WatchlistRepository,
        removalCoordinator: WatchlistPendingRemoval?
    ) async throws -> Set<Int> {
        let persisted = try await repository.activeShowIDs()
        return trackedIDs(
            persistedIDs: persisted,
            pendingRemovalID: removalCoordinator?.pendingRemoval?.id
        )
    }
}
