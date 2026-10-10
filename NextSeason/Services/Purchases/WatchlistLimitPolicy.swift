//
//  WatchlistLimitPolicy.swift
//  NextSeason
//

import Foundation

/// Free-tier watchlist capacity and the rule for whether another show can be added.
nonisolated enum WatchlistLimitPolicy {
    /// Permanent free allowance. Paid or complimentary users are unlimited.
    static let freeShowLimit = 3

    /// Adds are allowed when the user has Plus (or complimentary access), or when the
    /// current *active* count is still below the free cap.
    ///
    /// A lapsed Plus user keeps every saved show; shows past the first
    /// `freeShowLimit` are paused (see `showIDsToPause`). Paused shows do not
    /// count, so deleting an active show frees a slot for a new or paused show.
    static func canAddShow(currentCount: Int, isUnlimited: Bool) -> Bool {
        isUnlimited || currentCount < freeShowLimit
    }

    /// Shows to pause when the user does not have Unlimited access.
    ///
    /// Acts only when more than `freeShowLimit` shows are active: the active shows
    /// with the oldest `dateAdded` (ties broken by ID, so the result is
    /// deterministic) stay active and the rest are paused. Already-paused shows
    /// are never considered, so a free user's own choices — deleting an active
    /// show, or reactivating a paused one into a free slot — are left alone.
    ///
    /// Repeated lapses: restoring Plus resumes everything, so the next lapse sees
    /// every saved show as active again and keeps the three oldest by original
    /// `dateAdded`. Reactivating a paused show keeps its original `dateAdded`, so
    /// selections made during an earlier free period are not remembered.
    static func showIDsToPause(in shows: [TrackedShow]) -> Set<Int> {
        let active = shows.filter { !$0.isPaused }
        guard active.count > freeShowLimit else { return [] }
        let oldestFirst = active.sorted {
            ($0.dateAdded, $0.id) < ($1.dateAdded, $1.id)
        }
        return Set(oldestFirst.dropFirst(freeShowLimit).map(\.id))
    }

    /// Shows to resume when the user has Unlimited access: every paused show.
    static func showIDsToResume(in shows: [TrackedShow]) -> Set<Int> {
        Set(shows.filter(\.isPaused).map(\.id))
    }
}
