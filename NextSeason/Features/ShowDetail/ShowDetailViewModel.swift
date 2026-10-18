//
//  ShowDetailViewModel.swift
//  NextSeason
//

import Foundation

/// Loads full show details from TVMaze and drives track/untrack through shared
/// watchlist helpers so the star matches search and the watchlist list.
@Observable
@MainActor
final class ShowDetailViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// Header data carried over from search for instant display.
    let initialShow: Show
    private(set) var fullShow: Show?
    private(set) var loadState: LoadState = .loading
    private(set) var isTracked = false
    private(set) var isUpdatingWatchlist = false
    /// User-visible watchlist toggle failure; kept separate from `loadState` so a
    /// save error does not replace already-loaded next-season content.
    private(set) var watchlistActionErrorMessage: String?

    /// Shared state driving the post-track notification prompt alerts, reused
    /// verbatim by the search flow via `watchlistNotificationPromptAlerts`.
    let notificationPrompt = WatchlistNotificationPromptState()

    private let service: any TVMazeService
    private let repository: any WatchlistRepository
    private let notifications: any NotificationManaging
    private let analytics: any AnalyticsTracking
    /// Enforces the free watchlist cap before persisting a new track from detail.
    private let purchases: PurchaseService

    /// Notification service used by the shared prompt alerts modifier.
    var notificationService: any NotificationManaging { notifications }

    init(
        show: Show,
        service: any TVMazeService,
        repository: any WatchlistRepository,
        notifications: any NotificationManaging,
        analytics: any AnalyticsTracking,
        purchases: PurchaseService,
        initialIsTracked: Bool = false
    ) {
        self.initialShow = show
        self.service = service
        self.repository = repository
        self.notifications = notifications
        self.analytics = analytics
        self.purchases = purchases
        self.isTracked = initialIsTracked
    }

    /// Best available show data: the fully-loaded show once fetched, else the
    /// lighter version passed from search.
    var displayShow: Show { fullShow ?? initialShow }

    /// Next-season status, available only once seasons have been loaded.
    var nextSeasonStatus: NextSeasonStatus? {
        fullShow.map { NextSeasonCalculator.status(for: $0) }
    }

    /// Loads full show details (seasons + next episode) and tracked status.
    /// Tracked status is fetched in parallel with the network request so the
    /// toolbar reflects search-row changes without waiting on TVMaze.
    func load(removalCoordinator: WatchlistPendingRemoval?) async {
        loadState = .loading
        AppDiagnosticsLogger.breadcrumb("show_detail_load:\(initialShow.id)")
        async let trackedRefresh: Void = refreshTrackedState(removalCoordinator: removalCoordinator)

        do {
            fullShow = try await service.show(id: initialShow.id)
            guard !Task.isCancelled else {
                AppDiagnosticsLogger.logTaskCancel("show_detail_load")
                return
            }
            loadState = .loaded
            await trackedRefresh
        } catch is CancellationError {
            AppDiagnosticsLogger.logTaskCancel("show_detail_load")
            return
        } catch {
            loadState = .failed(error.localizedDescription)
            analytics.trackNonFatalError(error, context: "show_detail_load")
            await trackedRefresh
        }
    }

    /// Re-reads effective tracked status (persisted, excluding a pending undoable
    /// removal) so the Track control matches search and other surfaces when this
    /// screen reappears. Skipped mid-toggle to avoid clobbering an in-flight
    /// optimistic update.
    func refreshTrackedState(removalCoordinator: WatchlistPendingRemoval?) async {
        guard !isUpdatingWatchlist else { return }
        do {
            isTracked = try await WatchlistTrackingState.isTracked(
                showID: initialShow.id,
                repository: repository,
                removalCoordinator: removalCoordinator
            )
        } catch is CancellationError {
            return
        } catch {
            analytics.trackNonFatalError(error, context: "show_detail_refresh_tracked_state")
        }
    }

    func clearWatchlistActionError() {
        watchlistActionErrorMessage = nil
    }

    /// Reconciles the track star when a shared pending removal commits, is
    /// undone, cancelled, or fails. Does not notify the watchlist tab — callers
    /// opened from Search already handle that at the parent level.
    func handlePendingRemovalOutcome(
        removalCoordinator: WatchlistPendingRemoval?
    ) async {
        await refreshTrackedState(removalCoordinator: removalCoordinator)
    }

    /// Shared track/untrack orchestration; local star state updates from the outcome.
    ///
    /// When the free-tier cap blocks an add, invokes `onPaywallRequired` so the
    /// view can present the Plus store.
    func handleTrackButton(
        removalCoordinator: WatchlistPendingRemoval?,
        onWatchlistChanged: @escaping () -> Void,
        onPaywallRequired: @escaping () -> Void
    ) async {
        guard !isUpdatingWatchlist else { return }

        let show = fullShow ?? initialShow
        let wasTracked = isTracked
        let isPendingRemoval = removalCoordinator?.pendingRemoval?.id == show.id
        // Lock only during add. Undoable removal stays tappable so the user can
        // undo while the toast window is open.
        let shouldLockForAdd = !wasTracked && !isPendingRemoval
        watchlistActionErrorMessage = nil

        if shouldLockForAdd {
            isUpdatingWatchlist = true
        }
        defer {
            if shouldLockForAdd {
                isUpdatingWatchlist = false
            }
        }

        do {
            let outcome = try await WatchlistTracking.toggle(
                show,
                isTracked: wasTracked,
                source: .detail,
                repository: repository,
                tvMaze: service,
                removalCoordinator: removalCoordinator,
                analytics: analytics,
                notifications: notifications,
                prompt: notificationPrompt,
                purchases: purchases
            )
            switch outcome {
            case .undidPendingRemoval:
                await refreshTrackedState(removalCoordinator: removalCoordinator)
            case .removalRequested:
                isTracked = false
            case .added:
                isTracked = true
                onWatchlistChanged()
            case .paywallRequired:
                onPaywallRequired()
            case .ignored:
                // Repo/UI mismatch (e.g. show already gone) — reconcile the star.
                await refreshTrackedState(removalCoordinator: removalCoordinator)
            }
        } catch is CancellationError {
            return
        } catch {
            let errorContext =
                wasTracked || isPendingRemoval
                ? "show_detail_watchlist_lookup"
                : "watchlist_add_detail"
            analytics.trackNonFatalError(error, context: errorContext)
            // Thrown failures (add or removal lookup) get a generic alert.
            // Benign `.ignored` above stays silent after reconcile.
            watchlistActionErrorMessage = WatchlistTracking.updateFailedMessage
            if shouldLockForAdd {
                // Keep `loadState` intact — watchlist failures are not fetch failures.
                // Skip refresh while `isUpdatingWatchlist` is true; restore prior star.
                isTracked = wasTracked
            } else {
                // Removal/lookup failure: re-read persistence now that we are not locked.
                await refreshTrackedState(removalCoordinator: removalCoordinator)
            }
        }
    }
}
