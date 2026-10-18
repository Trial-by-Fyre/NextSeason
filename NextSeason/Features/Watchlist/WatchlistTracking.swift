//
//  WatchlistTracking.swift
//  NextSeason
//

import Foundation

/// Shared watchlist track/untrack orchestration used by search rows and show detail.
@MainActor
enum WatchlistTracking {
    /// Generic user-facing copy for thrown watchlist add/remove failures.
    static let updateFailedMessage = String(
        localized: "NextSeason couldn't update your Watchlist. Please try again."
    )

    /// Result of a track-button tap after shared side effects have run.
    enum ToggleOutcome: Equatable {
        /// A pending undoable removal for this show was cancelled.
        case undidPendingRemoval
        /// An undoable removal was requested (persistence deferred).
        case removalRequested
        /// The show was persisted and analytics / notification prompt ran.
        case added
        /// The free watchlist is full; the caller should present NextSeason Plus.
        case paywallRequired
        /// No-op (e.g. missing undo coordinator, or show already gone from the repo).
        case ignored
    }

    /// Persists the show when under the free-tier cap, records analytics, and arms
    /// the notification prompt when needed. Returns `.paywallRequired` without
    /// touching persistence when `PurchaseService` blocks another add.
    ///
    /// Search hits omit seasons / next episode. When those are missing, this loads the
    /// full `/shows/:id` payload so stored `nextSeason` matches show detail.
    ///
    /// Only active shows count toward the free cap. Adding a show that is saved but
    /// paused reactivates that row (via `repository.add`) when a slot is free.
    static func add(
        _ show: Show,
        source: WatchlistActionSource,
        repository: any WatchlistRepository,
        tvMaze: any TVMazeService,
        analytics: any AnalyticsTracking,
        notifications: any NotificationManaging,
        prompt: WatchlistNotificationPromptState,
        purchases: PurchaseService
    ) async throws -> ToggleOutcome {
        let currentCount = try await repository.activeShowIDs().count
        guard await purchases.canAddToWatchlist(currentCount: currentCount) else {
            return .paywallRequired
        }
        try Task.checkCancellation()
        let showToStore = try await resolvedShowForTracking(show, tvMaze: tvMaze)
        // Final admission check at persistence. The count above was read before
        // the entitlement wait and the detail fetch suspended; meanwhile another
        // add or an Undo may have taken the last free slot. Nothing between this
        // check and the write suspends (repository calls are main-actor and do
        // not await internally). An already-active show is an idempotent no-op.
        let activeIDs = try await repository.activeShowIDs()
        if !activeIDs.contains(showToStore.id),
            !WatchlistLimitPolicy.canAddShow(
                currentCount: activeIDs.count, isUnlimited: purchases.isUnlimitedWatchlist)
        {
            return .paywallRequired
        }
        try await repository.add(showToStore)
        analytics.track(.watchlistAdded(source: source, showID: showToStore.id))
        if await notifications.needsAuthorizationPrompt() {
            prompt.shouldPromptForNotifications = true
        }
        return .added
    }

    /// Full track/untrack flow: undo a pending removal, request undoable untrack, or add.
    static func toggle(
        _ show: Show,
        isTracked: Bool,
        source: WatchlistActionSource,
        repository: any WatchlistRepository,
        tvMaze: any TVMazeService,
        removalCoordinator: WatchlistPendingRemoval?,
        analytics: any AnalyticsTracking,
        notifications: any NotificationManaging,
        prompt: WatchlistNotificationPromptState,
        purchases: PurchaseService
    ) async throws -> ToggleOutcome {
        if removalCoordinator?.pendingRemoval?.id == show.id {
            _ = await removalCoordinator?.undoRemoval()
            return .undidPendingRemoval
        }

        if isTracked {
            guard let removalCoordinator else { return .ignored }
            guard let tracked = try await repository.trackedShow(showID: show.id) else {
                return .ignored
            }
            removalCoordinator.requestRemoval(tracked, source: source)
            return .removalRequested
        }

        return try await add(
            show,
            source: source,
            repository: repository,
            tvMaze: tvMaze,
            analytics: analytics,
            notifications: notifications,
            prompt: prompt,
            purchases: purchases
        )
    }

    /// Uses the caller's show when it already has season data; otherwise fetches detail.
    private static func resolvedShowForTracking(
        _ show: Show,
        tvMaze: any TVMazeService
    ) async throws -> Show {
        guard show.seasons.isEmpty else { return show }
        return try await tvMaze.show(id: show.id)
    }
}
