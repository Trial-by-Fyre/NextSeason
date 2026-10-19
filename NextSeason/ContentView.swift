//
//  ContentView.swift
//  NextSeason
//

import SwiftUI

/// Root tab shell: Search and Watchlist, wired to `AppNavigationCoordinator` for
/// tab selection, navigation paths, watchlist reload tokens, and notification deep links.
struct ContentView: View {
    @Environment(\.watchlistRepository) private var repository
    @Environment(\.watchlistPendingRemoval) private var removalCoordinator
    @Environment(\.analytics) private var analytics
    /// Optional so previews without the app composition still render.
    @Environment(WatchlistAccessReconciler.self) private var accessReconciler:
        WatchlistAccessReconciler?
    @Bindable var coordinator: AppNavigationCoordinator

    private let searchService: any TheTVDBService
    private let tvMaze: any TVMazeService
    private let showIDMapping: any ShowIDMapping
    private let isLocalShowIDMappingAvailable: Bool

    init(
        coordinator: AppNavigationCoordinator,
        searchService: any TheTVDBService,
        tvMaze: any TVMazeService,
        showIDMapping: any ShowIDMapping,
        isLocalShowIDMappingAvailable: Bool = true
    ) {
        _coordinator = Bindable(coordinator)
        self.searchService = searchService
        self.tvMaze = tvMaze
        self.showIDMapping = showIDMapping
        self.isLocalShowIDMappingAvailable = isLocalShowIDMappingAvailable
    }

    var body: some View {
        TabView(selection: tabBarSelection) {
            SearchView(
                navigationPath: $coordinator.searchPath,
                searchService: searchService,
                tvMaze: tvMaze,
                showIDMapping: showIDMapping,
                isLocalShowIDMappingAvailable: isLocalShowIDMappingAvailable,
                analytics: analytics,
                onWatchlistChanged: { coordinator.notifyWatchlistDataChanged() }
            )
            // Instruments / ProfileFlow automation is wired here—not inside
            // `SearchView` or `ShowDetailView`—so feature screens stay unaware
            // of profiling. The runner (`ProfileFlowRunner`) drives tabs, paths,
            // and repository work through `AppNavigationCoordinator`; it still
            // needs two async completion signals that only the Search tab can
            // observe:
            //
            // 1. Search settled — the profiling request task finishes and
            //    reports success or a failure message for that request.
            // 2. Detail loaded — a pushed `ShowDetailView` finishes its load task.
            //
            // Those signals travel through SwiftUI environment keys (see
            // `AutomationEnvironment`) so `ShowDetailView` inherits the detail
            // callback without taking a profiling parameter. Guards inside the
            // consumers (`ProfileFlowConfiguration.isEnabled`) keep normal
            // launches from bumping coordinator tokens even though the hooks
            // are always installed.
            .environment(
                \.automationSearchQuery,
                $coordinator.automationSearchQuery
            )
            .environment(\.automationSearchRequestID, coordinator.automationSearchRequestID)
            .environment(\.onAutomationSearchSettled) { error in
                coordinator.notifyAutomationSearchSettled(error: error)
            }
            .environment(\.onAutomationDetailLoaded) {
                coordinator.notifyAutomationDetailLoaded()
            }
            .accessibilityIdentifier(AccessibilityID.Tab.search)
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }
            .tag(AppNavigationCoordinator.Tab.search)

            WatchlistView(
                navigationPath: $coordinator.watchlistPath,
                tvMaze: tvMaze,
                selectedTab: coordinator.selectedTab,
                watchlistReloadToken: coordinator.watchlistReloadToken,
                pendingDetailToken: coordinator.pendingWatchlistDetail?.id,
                onApplyPendingDetail: {
                    coordinator.applyPendingWatchlistDetail()
                },
                onFindShow: {
                    coordinator.showSearchRoot()
                },
                onWatchlistChanged: {
                    coordinator.notifyWatchlistDataChanged()
                }
            )
            .accessibilityIdentifier(AccessibilityID.Tab.watchlist)
            .tabItem {
                Label("Watchlist", systemImage: "star")
            }
            .tag(AppNavigationCoordinator.Tab.watchlist)
        }
        .appScreenBackground()
        .background {
            TabBarReselectHandler(tabIndex: AppNavigationCoordinator.Tab.search.tabBarIndex) {
                coordinator.popSearchToRoot()
            }
        }
        .modifier(AppAboutPresentationModifier())
        .onChange(of: coordinator.selectedTab) { oldTab, tab in
            // Commit before other tab-side effects so a Search-stack detail screen
            // reappearing during the switch cannot cancel the removal first.
            Task { @MainActor in
                if oldTab == .watchlist, tab != .watchlist {
                    AppDiagnosticsLogger.logTaskStart("watchlist_commit_on_leave_tab")
                    await removalCoordinator?.commitPendingRemovalIfNeeded()
                    AppDiagnosticsLogger.logTaskComplete("watchlist_commit_on_leave_tab")
                }
                if tab == .search {
                    // Pops only for a user selection, and not if notification
                    // routing pushed a Search detail during the commit above.
                    coordinator.finishManualSearchSelection()
                }
                if tab == .watchlist {
                    coordinator.notifyWatchlistDataChanged()
                }
            }
        }
        .task {
            if !UITestingConfiguration.isEnabled {
                // Attach the exact coordinator SwiftUI observes so notification taps
                // route into this view's navigation state; this also flushes any
                // launch-time tap that NotificationRouting buffered before attach.
                NotificationRouting.setCoordinator(coordinator)
            }
            await coordinator.resolveInitialTab(repository: repository)
            await coordinator.resolvePendingNavigation(
                repository: repository,
                tvMaze: tvMaze,
                analytics: analytics,
                prepare: reconcileBeforeNavigation,
                willLeaveWatchlist: commitPendingRemovalBeforeLeavingWatchlist
            )
        }
        .onChange(of: coordinator.pendingShowID) { _, showID in
            guard showID != nil else { return }
            Task {
                await coordinator.resolvePendingNavigation(
                    repository: repository,
                    tvMaze: tvMaze,
                    analytics: analytics,
                    prepare: reconcileBeforeNavigation,
                    willLeaveWatchlist: commitPendingRemovalBeforeLeavingWatchlist
                )
            }
        }
    }

    /// TabView writes through this binding only when the user selects a tab, so
    /// manual return-to-root can be told apart from programmatic routing.
    private var tabBarSelection: Binding<AppNavigationCoordinator.Tab> {
        Binding(
            get: { coordinator.selectedTab },
            set: { coordinator.selectTabFromTabBar($0) }
        )
    }

    /// Ends a pending removal's undo window synchronously (persisting a deferred
    /// removal) before notification routing leaves Watchlist for Search detail.
    private func commitPendingRemovalBeforeLeavingWatchlist() {
        removalCoordinator?.confirmPendingRemoval()
    }

    /// Notification taps decide from reconciled pause state: wait for the first
    /// StoreKit answer and apply it before looking the show up.
    private func reconcileBeforeNavigation() async {
        await accessReconciler?.reconcileWhenAccessKnown()
    }
}

#if DEBUG
    #Preview {
        let repository = InMemoryWatchlistRepository()
        let showIDMapping = InMemoryShowIDMapping(
            map: [TVDBSearchResult.previewSearchResult.id: Show.preview.id]
        )
        ContentView(
            coordinator: AppNavigationCoordinator(),
            searchService: PreviewTheTVDBService(stub: .previewSearchResult),
            tvMaze: PreviewTVMazeService(stub: .preview),
            showIDMapping: showIDMapping
        )
        .environment(\.watchlistRepository, repository)
        .environment(\.showIDMapping, showIDMapping)
        .environment(PurchaseService.preview)
        .environment(
            \.watchlistPendingRemoval,
            WatchlistPendingRemoval(
                repository: repository,
                analytics: RecordingAnalyticsService()
            ))
    }
#endif
