//
//  SearchWatchlistTracking.swift
//  NextSeason
//

import Foundation

/// Search-tab star state: which result IDs are effectively tracked, and row taps.
///
/// Uses `WatchlistTrackingState` so a show pending undo-removal appears
/// untracked (filled star off) even though it is still in the repository.
/// Add/remove goes through shared `WatchlistTracking.toggle` (same path as
/// Show Detail). Local `trackedShowIDs` updates immediately so the star feels
/// responsive without waiting for a full refresh.
@Observable
@MainActor
final class SearchWatchlistTracking {
    /// Bundled dependencies for search-row watchlist add/remove actions.
    ///
    /// Built by `SearchView` and passed into track handling so row buttons can
    /// persist changes, drive the notification prompt, and dismiss the first-run
    /// results hint without threading each dependency through the list separately.
    struct Context {
        let repository: any WatchlistRepository
        let tvMaze: any TVMazeService
        let removalCoordinator: WatchlistPendingRemoval?
        let notificationService: any NotificationManaging
        let notificationPrompt: WatchlistNotificationPromptState
        let analytics: any AnalyticsTracking
        /// Free-tier cap enforcement for add-to-watchlist from search rows.
        let purchases: PurchaseService
        let onWatchlistChanged: () -> Void
        let onSearchResultsHintDismissed: () -> Void
        /// Presents the Plus store when `WatchlistTracking.toggle` returns
        /// `.paywallRequired`. Called from the view layer so this helper stays
        /// unaware of paywall UI.
        let onPaywallRequired: () -> Void
    }

    /// IDs shown as tracked on search rows (excludes pending removals).
    private(set) var trackedShowIDs: Set<Int> = []
    /// IDs with an in-flight add (prevents double-tap while fetching full show data).
    private(set) var updatingShowIDs: Set<Int> = []

    /// Reloads star state from persistence, excluding any pending removal.
    func refresh(
        repository: any WatchlistRepository,
        excludingPendingRemovalFrom removalCoordinator: WatchlistPendingRemoval?,
        analytics: any AnalyticsTracking
    ) async {
        do {
            trackedShowIDs = try await WatchlistTrackingState.trackedIDs(
                repository: repository,
                removalCoordinator: removalCoordinator
            )
        } catch is CancellationError {
            return
        } catch {
            analytics.trackNonFatalError(error, context: "search_watchlist_tracking_refresh")
        }
    }

    /// Handles a search-row track / untrack tap.
    func handleTrackButton(
        for show: Show,
        anchor: CGRect,
        context: Context
    ) async throws {
        guard !updatingShowIDs.contains(show.id) else { return }

        let isTracked = trackedShowIDs.contains(show.id)
        let isPendingRemoval = context.removalCoordinator?.pendingRemoval?.id == show.id
        // Only the add path needs an in-flight lock; untrack/undo update local
        // star state immediately. Capture before await so defer still clears.
        let shouldLockForAdd = !isTracked && !isPendingRemoval

        if shouldLockForAdd {
            updatingShowIDs.insert(show.id)
        }
        defer {
            if shouldLockForAdd {
                updatingShowIDs.remove(show.id)
            }
        }

        do {
            let outcome = try await WatchlistTracking.toggle(
                show,
                isTracked: isTracked,
                anchor: anchor,
                source: .search,
                repository: context.repository,
                tvMaze: context.tvMaze,
                removalCoordinator: context.removalCoordinator,
                analytics: context.analytics,
                notifications: context.notificationService,
                prompt: context.notificationPrompt,
                purchases: context.purchases
            )
            switch outcome {
            case .ignored:
                // Repo/UI mismatch (e.g. show already gone) — reconcile stars.
                await refresh(
                    repository: context.repository,
                    excludingPendingRemovalFrom: context.removalCoordinator,
                    analytics: context.analytics
                )
            case .paywallRequired:
                context.onPaywallRequired()
            default:
                apply(outcome, for: show.id, context: context)
            }
        } catch is CancellationError {
            return
        } catch {
            let errorContext =
                isTracked || isPendingRemoval
                ? "search_watchlist_tracking_lookup"
                : "watchlist_add_search"
            context.analytics.trackNonFatalError(error, context: errorContext)
            // Reconcile with persistence after a failed toggle.
            await refresh(
                repository: context.repository,
                excludingPendingRemovalFrom: context.removalCoordinator,
                analytics: context.analytics
            )
            throw error
        }
    }

    /// Applies a successful toggle to the local star set (and related UI hooks).
    private func apply(
        _ outcome: WatchlistTracking.ToggleOutcome,
        for showID: Int,
        context: Context
    ) {
        switch outcome {
        case .undidPendingRemoval:
            trackedShowIDs.insert(showID)
        case .removalRequested:
            trackedShowIDs.remove(showID)
        case .added:
            trackedShowIDs.insert(showID)
            context.onSearchResultsHintDismissed()
            context.onWatchlistChanged()
        case .paywallRequired, .ignored:
            break
        }
    }
}
