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
    /// current persisted count is still below the free cap.
    ///
    /// A lapsed Plus user who already has more than `freeShowLimit` shows keeps
    /// those shows; they just cannot add another until they re-subscribe or
    /// remove shows so that `currentCount < freeShowLimit`.
    static func canAddShow(currentCount: Int, isUnlimited: Bool) -> Bool {
        isUnlimited || currentCount < freeShowLimit
    }
}
