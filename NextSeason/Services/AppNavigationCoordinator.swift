//
//  AppNavigationCoordinator.swift
//  NextSeason
//

import SwiftUI

/// Routes deep links from notifications into the correct tab and detail screen.
@Observable
@MainActor
final class AppNavigationCoordinator {
    enum Tab: Hashable {
        case search
        case watchlist

        /// Index in the root `TabView`, used when handling tab-bar reselection.
        var tabBarIndex: Int {
            switch self {
            case .search: 0
            case .watchlist: 1
            }
        }
    }

    var selectedTab: Tab = .search
    var watchlistPath = NavigationPath()
    var searchPath = NavigationPath()
    /// One-shot query injection for external automation (Instruments `ProfileFlowRunner`).
    /// `ContentView` binds this into the Search tab environment; the runner sets it
    /// directly. Unused in normal launches.
    var automationSearchQuery: String?
    /// Bumped when search reaches a settled outcome during an automated run.
    /// `ProfileFlowRunner` polls this token after setting `automationSearchQuery`.
    private(set) var automationSearchSettledToken = 0
    /// Bumped when show detail finishes loading during an automated run.
    /// `ProfileFlowRunner` polls this after pushing onto `searchPath`.
    private(set) var automationDetailLoadedToken = 0

    private(set) var automationSearchRequestID = 0
    private(set) var automationSearchError: String?

    @discardableResult
    func requestAutomationSearch(_ query: String) -> Int {
        let baseline = automationSearchSettledToken
        automationSearchError = nil
        automationSearchQuery = query
        automationSearchRequestID &+= 1
        return baseline
    }

    func cancelAutomationSearch() {
        automationSearchQuery = nil
        // The modifier's task is keyed by request identity, not query text.
        automationSearchRequestID &+= 1
    }

    func notifyAutomationSearchSettled(error: String? = nil) {
        automationSearchError = error
        automationSearchSettledToken &+= 1
    }

    func notifyAutomationDetailLoaded() {
        automationDetailLoadedToken &+= 1
    }

    private(set) var pendingShowID: Int?
    private(set) var watchlistReloadToken = 0

    /// A tracked show whose detail should be pushed onto the Watchlist tab once
    /// that tab's `NavigationStack` is on screen. The push is deferred (rather than
    /// appended immediately in `resolvePendingNavigation`) because pushing in the
    /// same update as the tab switch makes SwiftUI drop it and leave the user on
    /// the list. `WatchlistView` calls `applyPendingWatchlistDetail()` once mounted.
    private(set) var pendingWatchlistDetail: TrackedShow?

    /// Navigation request that owns `pendingWatchlistDetail`; stale detail is ignored.
    private var pendingWatchlistDetailRequestID: Int?

    /// Whether the pending deep-link push should animate. Determined by whether the
    /// app was already foreground-active when the notification was tapped: an in-app
    /// tap animates like normal navigation, while a launch/foreground tap does not
    /// (so the detail page is already in place rather than visibly sliding in).
    private var pendingWatchlistDetailAnimated = false

    /// Whether the queued navigation (`pendingShowID`) originated from an in-app tap.
    /// Applied when resolving to Search immediately and copied into
    /// `pendingWatchlistDetailAnimated` when the Watchlist push is deferred.
    private var pendingNavigationAnimated = false

    /// Monotonic id for notification deep links. Only the latest request may apply
    /// tab/path changes after an await (R14).
    private var navigationRequestID = 0

    /// Guards the one-time cold-launch tab decision so foreground returns keep the
    /// user on whatever tab they were last using.
    private var didResolveInitialTab = false

    /// - Parameter showID: TVMaze show ID to open on the detail screen.
    /// - Parameter animated: `true` when the tap happened while the app was already
    ///   foreground-active (in-app navigation), `false` for a launch/foreground tap.
    func queueShowNavigation(showID: Int, animated: Bool = false) {
        navigationRequestID &+= 1
        clearDeferredWatchlistDetail()
        pendingShowID = showID
        pendingNavigationAnimated = animated
    }

    /// Pushes a deferred notification deep link onto the Watchlist stack. Called by
    /// `WatchlistView` from `onAppear`/`onChange` so the push lands after that tab's
    /// `NavigationStack` is mounted. Safe to call repeatedly; it no-ops once the
    /// pending show has been consumed. The animation is decided by the tap context
    /// captured in `resolvePendingNavigation`, not by which callback triggers it.
    func applyPendingWatchlistDetail() {
        guard let tracked = pendingWatchlistDetail,
            let requestID = pendingWatchlistDetailRequestID,
            requestID == navigationRequestID
        else {
            clearDeferredWatchlistDetail()
            return
        }
        let animated = pendingWatchlistDetailAnimated
        clearDeferredWatchlistDetail()
        guard animated else {
            // Launch / foreground: push without animation so the detail page is
            // already in place, rather than visibly sliding in.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                watchlistPath = NavigationPath()
                watchlistPath.append(tracked)
            }
            return
        }
        // In-app deep link while the Watchlist is already on screen: animate the push.
        watchlistPath = NavigationPath()
        watchlistPath.append(tracked)
    }

    /// Cold-launch landing tab: Watchlist when it already has at least one show,
    /// otherwise Search. Runs once per launch; it does not override a notification
    /// deep link and is never re-run on a foreground return.
    func resolveInitialTab(repository: any WatchlistRepository) async {
        guard !didResolveInitialTab else { return }
        didResolveInitialTab = true

        // Profile flows drive navigation themselves; leave the default tab alone.
        guard !ProfileFlowConfiguration.isEnabled else { return }
        // A notification deep link picks the tab itself (see resolvePendingNavigation).
        guard pendingShowID == nil else { return }

        do {
            let trackedIDs = try await repository.trackedShowIDs()
            selectedTab = trackedIDs.isEmpty ? .search : .watchlist
        } catch {
            selectedTab = .search
        }
    }

    /// Pops the search navigation stack to its root without changing tabs.
    /// The search query lives in `SearchViewModel`, so it is preserved.
    func popSearchToRoot() {
        searchPath = NavigationPath()
    }

    /// Switches to the Search tab at its root, popping any detail screen the
    /// search stack was left on (e.g. a show viewed while adding to the
    /// watchlist) so the user lands on the search screen itself.
    func showSearchRoot() {
        popSearchToRoot()
        selectedTab = .search
    }

    /// Bumps a token `WatchlistView` observes so it reloads from persistence.
    func notifyWatchlistDataChanged(reloadWatchlist: Bool = true) {
        if reloadWatchlist {
            watchlistReloadToken &+= 1
        }
    }

    /// Turns a queued notification deep link (`pendingShowID`) into tab + detail
    /// navigation. Called from `ContentView` after attach and whenever a new
    /// `pendingShowID` arrives while the app is already running.
    ///
    /// Prefer Watchlist when the show is still tracked (deferred push so the
    /// tab's `NavigationStack` is mounted). A paused show opens the Watchlist
    /// root without detail. Otherwise (not saved) fall back to Search and
    /// push immediately, honoring `pendingNavigationAnimated` for launch vs
    /// in-app taps.
    ///
    /// - Parameters:
    ///   - repository: Saved-show lookup that decides Watchlist vs. Search.
    ///   - tvMaze: Loads the show for the Search fallback when it isn't saved.
    ///   - analytics: Records the notification open and lookup failures.
    ///   - prepare: Awaited before the saved-show lookup. Production passes
    ///     `WatchlistAccessReconciler.reconcileWhenAccessKnown`, so a cold
    ///     launch from an old notification decides using reconciled pause state
    ///     (a show that just lost Plus is paused before it could open detail).
    func resolvePendingNavigation(
        repository: any WatchlistRepository,
        tvMaze: any TVMazeService,
        analytics: any AnalyticsTracking,
        prepare: @MainActor () async -> Void = {}
    ) async {
        guard let showID = pendingShowID else { return }
        // Consume the queue up front so a concurrent resolve cannot process twice.
        pendingShowID = nil
        let requestID = navigationRequestID
        let animated = pendingNavigationAnimated
        await prepare()
        guard isCurrentNavigationRequest(requestID) else { return }

        do {
            if let tracked = try await repository.trackedShow(showID: showID) {
                guard isCurrentNavigationRequest(requestID) else { return }
                // A paused show (Plus lapsed) must not open detail — not even via
                // the Search fallback below. Land on the Watchlist root, where
                // the show appears in the Paused section.
                if tracked.isPaused {
                    clearDeferredWatchlistDetail()
                    selectedTab = .watchlist
                    watchlistPath = NavigationPath()
                    analytics.track(.appOpenedFromNotification(showID: showID))
                    return
                }
                // Defer the path append until WatchlistView appears — pushing in
                // the same update as the tab switch can drop the navigation.
                selectedTab = .watchlist
                pendingWatchlistDetail = tracked
                pendingWatchlistDetailRequestID = requestID
                pendingWatchlistDetailAnimated = animated
                analytics.track(.appOpenedFromNotification(showID: showID))
                return
            }
        } catch is CancellationError {
            return
        } catch {
            // Lookup failed; try the Search/TVMaze path below rather than giving up.
            analytics.trackNonFatalError(error, context: "notification_navigation_watchlist_lookup")
        }

        guard isCurrentNavigationRequest(requestID) else { return }

        // Not on the watchlist (or watchlist lookup failed): open via Search.
        do {
            let show = try await tvMaze.show(id: showID)
            guard isCurrentNavigationRequest(requestID) else { return }
            selectedTab = .search
            if animated {
                searchPath.append(show)
            } else {
                // Launch / foreground tap: land on detail without a slide-in.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    searchPath = NavigationPath()
                    searchPath.append(show)
                }
            }
            analytics.track(.appOpenedFromNotification(showID: showID))
        } catch is CancellationError {
            return
        } catch {
            analytics.trackNonFatalError(error, context: "notification_navigation_show_lookup")
        }
    }

    private func isCurrentNavigationRequest(_ requestID: Int) -> Bool {
        requestID == navigationRequestID
    }

    private func clearDeferredWatchlistDetail() {
        pendingWatchlistDetail = nil
        pendingWatchlistDetailRequestID = nil
    }
}
