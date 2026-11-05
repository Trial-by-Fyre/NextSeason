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
    /// Every such reactivation, from any screen, calls `willReactivate` first so
    /// the row can be marked for a silent catch-up baseline: it keeps its
    /// pre-pause notification signature and its detail may come from TVMaze's
    /// cache, so its first refresh must not announce what changed while paused.
    ///
    /// - Parameters:
    ///   - show: The show to track; full detail is fetched when it has no seasons.
    ///   - source: Screen that started the add, for analytics.
    ///   - repository: Saved shows; checked for capacity and written on success.
    ///   - tvMaze: Loads full show detail for search hits and Watchlist rows.
    ///   - analytics: Records the `watchlistAdded` event.
    ///   - notifications: Decides whether to arm the notification prompt.
    ///   - prompt: Set when the post-add notification prompt should appear.
    ///   - purchases: Entitlement for the free-tier cap (waits for the first read).
    ///   - pausedRow: Set when reactivating a paused Watchlist row. The write then
    ///     happens only if that same saved row (same `dateAdded`) is still saved
    ///     and paused at persistence; otherwise this returns `.ignored`. A row
    ///     deleted meanwhile is never re-created, and a row resumed meanwhile is
    ///     not reported as added (it never received `willReactivate`).
    ///   - willReactivate: Called with the saved paused row (whether or not
    ///     `pausedRow` was passed) after every check passes and immediately
    ///     before the write, with no suspension in between
    ///     (`WatchlistRefreshService.markForCatchUp`).
    static func add(
        _ show: Show,
        source: WatchlistActionSource,
        repository: any WatchlistRepository,
        tvMaze: any TVMazeService,
        analytics: any AnalyticsTracking,
        notifications: any NotificationManaging,
        prompt: WatchlistNotificationPromptState,
        purchases: PurchaseService,
        reactivating pausedRow: TrackedShow? = nil,
        willReactivate: @MainActor (TrackedShow) -> Void = { _ in }
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
        let stored = try await repository.trackedShow(showID: showToStore.id)
        if let pausedRow {
            guard let stored, stored.isPaused, stored.dateAdded == pausedRow.dateAdded else {
                return .ignored
            }
        }
        let activeIDs = try await repository.activeShowIDs()
        if !activeIDs.contains(showToStore.id),
            !WatchlistLimitPolicy.canAddShow(
                currentCount: activeIDs.count, isUnlimited: purchases.isUnlimitedWatchlist)
        {
            return .paywallRequired
        }
        // Search and Show Detail reach a paused row here too (its star shows
        // untracked), so the catch-up mark cannot depend on `pausedRow`.
        if let stored, stored.isPaused { willReactivate(stored) }
        try await repository.add(showToStore)
        analytics.track(.watchlistAdded(source: source, showID: showToStore.id))
        if await notifications.needsAuthorizationPrompt() {
            prompt.shouldPromptForNotifications = true
        }
        return .added
    }

    /// Full track/untrack flow: undo a pending removal, request undoable untrack, or add.
    ///
    /// - Parameter refreshService: Marks a reactivated paused row for catch-up
    ///   (see `add`) and starts that catch-up, which records a silent baseline.
    ///   Optional only for previews and tests without a refresh pipeline.
    /// - Parameter onCatchUpFinished: Called after that catch-up saves, so the
    ///   Watchlist reloads the refreshed row. Must not depend on the calling
    ///   screen still being shown (callers pass their app-level reload hook).
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
        purchases: PurchaseService,
        refreshService: WatchlistRefreshService? = nil,
        onCatchUpFinished: @escaping () -> Void = {}
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

        var didReactivate = false
        let outcome = try await add(
            show,
            source: source,
            repository: repository,
            tvMaze: tvMaze,
            analytics: analytics,
            notifications: notifications,
            prompt: prompt,
            purchases: purchases,
            willReactivate: { row in
                refreshService?.markForCatchUp([row])
                didReactivate = true
            }
        )
        // Like the Watchlist's paused-row tap, catch up the reactivated show
        // right away so the silent baseline covers only the paused period.
        if outcome == .added, didReactivate {
            refreshService?.startCatchUp(showIDs: [show.id], onFinished: onCatchUpFinished)
        }
        return outcome
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
