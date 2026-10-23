//
//  SearchView.swift
//  NextSeason
//

import SwiftUI

/// Guest search: type a title, browse matching shows, and track from the results list.
///
/// Search hits come from TheTVDB (paginated), then are filtered through the local
/// TVDB↔TVMaze show ID mapping so only actionable shows are listed. Title and
/// poster on each row come from that TVMaze snapshot. Selecting or tracking a
/// row still resolves through live TVMaze before the existing show-detail /
/// watchlist flow runs.
///
/// Lifecycle / refresh matrix:
/// - `.task(id: query)` drives `SearchViewModel.search()` (debounce + cancel on edit).
/// - `.task` and `.task(id: navigationPath.count)` refresh tracked IDs when the
///   screen appears or when returning from show detail.
/// - `.onChange(of: outcomeGeneration)` keeps row track-button state in sync when
///   a pending removal commits, is undone, or is cancelled.
/// - `.onChange(of: changeGeneration)` re-reads tracked IDs when a Plus lapse or
///   restore pauses or resumes shows (`WatchlistAccessReconciler`).
///
/// First-run AppStorage (independent flags):
/// - `hasCompletedFirstSearch` — retires the idle "Try an Example" button once the
///   user reaches `.results` or `.empty`.
/// - `searchResultsHintDismissed` — hides the results-list inset hint after the
///   user opens a show (or after an add-to-watchlist dismisses it).
struct SearchView: View {
    @Environment(\.watchlistRepository) private var repository
    @Environment(\.notificationService) private var notificationService
    @Environment(\.watchlistPendingRemoval) private var removalCoordinator
    @Environment(\.dismissSearch) private var dismissSearch
    @Environment(\.presentPlusStore) private var presentPlusStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(PurchaseService.self) private var purchases
    /// Optional so previews without the app composition still render.
    @Environment(WatchlistAccessReconciler.self) private var accessReconciler:
        WatchlistAccessReconciler?

    @Binding var navigationPath: NavigationPath
    private let searchService: any TheTVDBService
    private let tvMaze: any TVMazeService
    private let showIDMapping: any ShowIDMapping
    private let analytics: any AnalyticsTracking
    private let onWatchlistChanged: () -> Void
    @State private var viewModel: SearchViewModel
    @State private var watchlistTracking = SearchWatchlistTracking()
    @State private var notificationPrompt = WatchlistNotificationPromptState()
    @State private var isScrollDismissingKeyboard = false
    /// Persists dismissal of the results-list first-run inset (not the idle example CTA).
    @AppStorage(FirstRunPreferences.searchResultsHintDismissedKey)
    private var searchResultsHintDismissed = false
    /// Persists completion of the idle "Try an Example" affordance.
    @AppStorage(FirstRunPreferences.hasCompletedFirstSearchKey)
    private var hasCompletedFirstSearch = false

    init(
        navigationPath: Binding<NavigationPath>,
        searchService: any TheTVDBService,
        tvMaze: any TVMazeService,
        showIDMapping: any ShowIDMapping,
        isLocalShowIDMappingAvailable: Bool = true,
        analytics: any AnalyticsTracking,
        onWatchlistChanged: @escaping () -> Void = {}
    ) {
        _navigationPath = navigationPath
        self.searchService = searchService
        self.tvMaze = tvMaze
        self.showIDMapping = showIDMapping
        self.analytics = analytics
        self.onWatchlistChanged = onWatchlistChanged
        _viewModel = State(
            initialValue: SearchViewModel(
                searchService: searchService,
                tvMaze: tvMaze,
                showIDMapping: showIDMapping,
                isLocalShowIDMappingAvailable: isLocalShowIDMappingAvailable,
                analytics: analytics
            )
        )
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appScreenBackground()
                .navigationTitle("NextSeason")
                .appAboutToolbarButton()
                .navigationDestination(for: Show.self) { show in
                    ShowDetailView(
                        show: show,
                        service: tvMaze,
                        repository: repository,
                        notifications: notificationService,
                        analytics: analytics,
                        purchases: purchases,
                        isTracked: watchlistTracking.trackedShowIDs.contains(show.id),
                        onWatchlistChanged: onWatchlistChanged
                    )
                    .onAppear {
                        analytics.track(.searchResultOpened(showID: show.id))
                        // Push-only: tab switches that re-show detail must not cancel
                        // a pending removal started on another tab.
                        removalCoordinator?.dismissPendingRemovalForNavigation()
                    }
                }
                .searchable(
                    text: $viewModel.query,
                    placement: searchFieldPlacement,
                    prompt: "Search TV shows"
                )
                .modifier(ReturnToSearchResultsOnActivateModifier(navigationPath: $navigationPath))
                .onSubmit(of: .search) {
                    collapseSearchKeyboard(dismissSearch: dismissSearch)
                }
                .task(id: viewModel.query) {
                    // Profiling has a separate task so the same query can be
                    // requested repeatedly without racing this typing task.
                    guard !ProfileFlowConfiguration.isEnabled else { return }
                    await viewModel.search()
                }
                .onChange(of: viewModel.state) { _, newState in
                    markFirstSearchCompletedIfNeeded(for: newState)
                }
                .automationSearchHooks(viewModel: viewModel)
                .task {
                    await refreshTrackedShows()
                }
                .task(id: navigationPath.count) {
                    if navigationPath.count > 0 {
                        dismissSearchResultsHintIfNeeded()
                    }
                    await refreshTrackedShows()
                }
                .onChange(of: removalCoordinator?.outcomeGeneration) { _, _ in
                    guard let outcome = removalCoordinator?.lastOutcome else { return }
                    Task { await handlePendingRemovalOutcome(outcome) }
                }
                // Plus lapse / restore paused or resumed shows while results are on
                // screen: paused rows must show an empty star (add → reactivate or
                // paywall); resumed rows a filled one.
                .onChange(of: accessReconciler?.changeGeneration) { _, _ in
                    Task { await refreshTrackedShows() }
                }
                .watchlistNotificationPromptAlerts(
                    prompt: notificationPrompt,
                    notificationService: notificationService
                )
                .alert(
                    "Something Went Wrong",
                    isPresented: Binding(
                        get: { viewModel.resolveErrorMessage != nil },
                        set: { if !$0 { viewModel.clearResolveError() } }
                    )
                ) {
                    Button("OK", role: .cancel) {
                        viewModel.clearResolveError()
                    }
                } message: {
                    Text(viewModel.resolveErrorMessage ?? "")
                }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private func refreshTrackedShows() async {
        await watchlistTracking.refresh(
            repository: repository,
            excludingPendingRemovalFrom: removalCoordinator,
            analytics: analytics
        )
    }

    private func handlePendingRemovalOutcome(_ outcome: PendingRemovalOutcome) async {
        await refreshTrackedShows()
        switch outcome {
        case .committed, .replaced:
            onWatchlistChanged()
        case .undone, .cancelled, .failed:
            break
        }
    }

    /// `onPlusUnlocked` finishes the blocked add if the paywall unlocks Plus.
    private func watchlistTrackingContext(
        onPlusUnlocked: @escaping @MainActor () -> Void
    ) -> SearchWatchlistTracking.Context {
        SearchWatchlistTracking.Context(
            repository: repository,
            tvMaze: tvMaze,
            removalCoordinator: removalCoordinator,
            notificationService: notificationService,
            notificationPrompt: notificationPrompt,
            analytics: analytics,
            purchases: purchases,
            onWatchlistChanged: onWatchlistChanged,
            onSearchResultsHintDismissed: dismissSearchResultsHintIfNeeded,
            onPaywallRequired: { presentPlusStore?(onPlusUnlocked) }
        )
    }

    private func dismissSearchResultsHintIfNeeded() {
        guard !searchResultsHintDismissed else { return }
        searchResultsHintDismissed = true
    }

    /// Complete idle-state paragraph: first-run copy includes the example CTA;
    /// subsequent visits point only at the search field.
    private var searchIdleDescription: String {
        hasCompletedFirstSearch
            ? FirstRunCopy.searchIdleSubsequentDescription
            : FirstRunCopy.searchIdleDescription
    }

    /// Once the user reaches a real search outcome, they've demonstrated they
    /// know how to search, so retire the "Try an Example" affordance for good.
    private func markFirstSearchCompletedIfNeeded(for state: SearchViewModel.State) {
        guard !hasCompletedFirstSearch else { return }
        switch state {
        case .results, .empty:
            hasCompletedFirstSearch = true
        case .idle, .loading, .failed:
            break
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            scrollableState {
                ContentUnavailableView {
                    Label {
                        Text("Find Your Next Season")
                            .appAccentText()
                    } icon: {
                        Image(systemName: "magnifyingglass")
                            .appPrimaryText()
                    }
                } description: {
                    Text(searchIdleDescription)
                        .appSecondaryText()
                } actions: {
                    if !hasCompletedFirstSearch {
                        Button(FirstRunCopy.tryExampleButtonTitle) {
                            analytics.track(.exampleSearchUsed)
                            viewModel.query = FirstRunCopy.exampleSearchQuery
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier(AccessibilityID.Search.tryExampleButton)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(AccessibilityID.Search.idlePrompt)
            }
        case .loading:
            List {
                ForEach(0..<3, id: \.self) { _ in
                    ShowRowSkeleton()
                }
            }
            .appPlainListStyle()
            .scrollDismissesKeyboard(.immediately)
            .searchScrollKeyboardDismissGesture(
                isScrollDismissingKeyboard: $isScrollDismissingKeyboard,
                dismissSearch: dismissSearch
            )
        case .results(let page):
            List {
                Section {
                    if showsInlineResultsHint && !page.items.isEmpty && !searchResultsHintDismissed
                    {
                        SearchResultsHintView()
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    if page.items.isEmpty {
                        ContentUnavailableView {
                            Label {
                                Text("Still Looking…")
                                    .appAccentText()
                            } icon: {
                                Image(systemName: "magnifyingglass")
                                    .appPrimaryText()
                            }
                        } description: {
                            Text(FirstRunCopy.searchMoreAvailableDescription)
                                .appSecondaryText()
                        }
                        .listRowInsets(
                            EdgeInsets(
                                top: AppSpacing.section,
                                leading: AppSpacing.screen,
                                bottom: AppSpacing.section,
                                trailing: AppSpacing.screen
                            )
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(page.items) { result in
                            searchResultRow(result)
                        }
                    }
                    if page.hasMore {
                        SearchLoadMoreFooterView(isLoading: viewModel.isLoadingMore) {
                            Task { await viewModel.loadMore() }
                        }
                        .listRowInsets(
                            EdgeInsets(
                                top: AppSpacing.tight,
                                leading: AppSpacing.screen,
                                bottom: AppSpacing.section,
                                trailing: AppSpacing.screen
                            )
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                } footer: {
                    TheTVDBAttributionView()
                }
            }
            .appPlainListStyle()
            .scrollDismissesKeyboard(.immediately)
            .searchScrollKeyboardDismissGesture(
                isScrollDismissingKeyboard: $isScrollDismissingKeyboard,
                dismissSearch: dismissSearch
            )
            .searchResultsHintInset(
                isVisible: !showsInlineResultsHint && !page.items.isEmpty
                    && !searchResultsHintDismissed
            )
        case .empty:
            scrollableState {
                ContentUnavailableView {
                    Label {
                        Text("Can't Find Your Show?")
                            .appAccentText()
                    } icon: {
                        Image(systemName: "magnifyingglass")
                            .appPrimaryText()
                    }
                } description: {
                    Text(FirstRunCopy.searchEmptyDescription)
                        .appSecondaryText()
                }
                // Contain (not combine) so VoiceOver reads the guidance, not just the title.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(AccessibilityID.Search.noResults)
            }
        case .failed(let message):
            scrollableState {
                ContentUnavailableView {
                    Label {
                        Text("Something Went Wrong")
                            .appAccentText()
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .appPrimaryText()
                    }
                } description: {
                    Text(message)
                        .appSecondaryText()
                } actions: {
                    if viewModel.isSearchRetryAvailable {
                        Button("Try Again") {
                            Task { await viewModel.search() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    /// At accessibility sizes, hosts a non-list state in a scroll view so content
    /// taller than the screen can be reached; it stays centered when it fits.
    /// Smaller sizes keep the static layout: there, a scroll view would make the
    /// navigation bar hide the search field until the user pulls down.
    @ViewBuilder
    private func scrollableState(@ViewBuilder _ content: () -> some View) -> some View {
        let content = content()
        if dynamicTypeSize.isAccessibilitySize {
            GeometryReader { proxy in
                ScrollView {
                    content
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.immediately)
            }
        } else {
            content
        }
    }

    /// At accessibility sizes the tall large title collapses the search drawer
    /// until the user pulls down, which is easy to miss, so keep it visible.
    private var searchFieldPlacement: SearchFieldPlacement {
        dynamicTypeSize.isAccessibilitySize
            ? .navigationBarDrawer(displayMode: .always) : .automatic
    }

    /// At accessibility sizes the pinned results hint covers most of the list,
    /// so it scrolls with the results instead.
    private var showsInlineResultsHint: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    @ViewBuilder
    private func searchResultRow(_ result: TVDBSearchResult) -> some View {
        // Row identity stays on TheTVDB id so UI tests and VoiceOver remain stable
        // before TVMaze resolution. Tracked-star state uses the resolved TVMaze id.
        let resolvedID = viewModel.resolvedTVMazeID(for: result.id)
        let isTracked = resolvedID.map { watchlistTracking.trackedShowIDs.contains($0) } ?? false
        let isResolving = viewModel.resolvingResultIDs.contains(result.id)
        let isUpdating =
            isResolving
            || (resolvedID.map { watchlistTracking.updatingShowIDs.contains($0) } ?? false)

        HStack(spacing: AppSpacing.tight) {
            Button {
                Task { await openAndPresent(result) }
            } label: {
                // Expand inside the label, with a content shape, so blank space
                // up to the star opens detail too; the star stays its own button.
                ShowRowLabel(result: result)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .showDetailLinkAccessibility()
            .accessibilityIdentifier("\(AccessibilityID.Search.result).\(result.id)")
            .disabled(isResolving)

            ShowRowTrackButton(
                showID: result.id,
                showName: result.name,
                isTracked: isTracked,
                isUpdating: isUpdating,
                isPendingRemoval: resolvedID.map {
                    removalCoordinator?.pendingRemoval?.id == $0
                } ?? false
            ) {
                Task {
                    await trackResult(result)
                }
            }
        }
    }

    /// Resolve TheTVDB → TVMaze, then push the existing `Show` detail destination.
    private func openAndPresent(_ result: TVDBSearchResult) async {
        // End editing before the push. Otherwise UIKit restores the search field
        // as first responder on return, and the keyboard covers the results.
        // Resigning keeps the query and results.
        KeyboardEditing.dismissEditing()
        do {
            let show = try await viewModel.resolveShow(for: result)
            analytics.track(
                .searchResultSelected(
                    alreadyOnWatchlist: watchlistTracking.trackedShowIDs.contains(show.id)
                )
            )
            navigationPath.append(show)
        } catch is CancellationError {
            return
        } catch {
            analytics.trackNonFatalError(error, context: "search_resolve_open")
            await setResolveError(error.localizedDescription)
        }
    }

    /// Resolve TheTVDB → TVMaze, then reuse the shared watchlist toggle path.
    private func trackResult(_ result: TVDBSearchResult) async {
        let show: Show
        do {
            show = try await viewModel.resolveShow(for: result)
        } catch is CancellationError {
            return
        } catch {
            analytics.trackNonFatalError(error, context: "search_resolve_track")
            await setResolveError(error.localizedDescription)
            return
        }

        await toggleTracking(for: show)
    }

    private func toggleTracking(for show: Show) async {
        do {
            try await watchlistTracking.handleTrackButton(
                for: show,
                context: watchlistTrackingContext(onPlusUnlocked: {
                    // Retry only while still untracked: the shared toggle would
                    // otherwise remove a show that was resumed or added meanwhile.
                    guard !watchlistTracking.trackedShowIDs.contains(show.id) else { return }
                    Task { await toggleTracking(for: show) }
                })
            )
        } catch is CancellationError {
            return
        } catch {
            analytics.trackNonFatalError(error, context: "search_watchlist_track")
            await setResolveError(WatchlistTracking.updateFailedMessage)
        }
    }

    private func setResolveError(_ message: String) async {
        viewModel.presentResolveError(message)
    }
}

/// When search is activated from a pushed show-detail screen, pop back to the
/// results list while leaving the query in `SearchViewModel` untouched.
private struct ReturnToSearchResultsOnActivateModifier: ViewModifier {
    @Environment(\.isSearching) private var isSearching
    @Binding var navigationPath: NavigationPath
    @State private var lastNavigationPathChange = Date.distantPast

    /// Ignore search activation briefly after pushing detail; the searchable
    /// chrome can flip `isSearching` during that transition.
    private static let navigationSettlingInterval: TimeInterval = 0.35

    func body(content: Content) -> some View {
        content
            .onChange(of: navigationPath) { _, _ in
                lastNavigationPathChange = Date.now
            }
            .onChange(of: isSearching) { wasSearching, searching in
                guard searching, !wasSearching, navigationPath.count > 0 else { return }
                guard
                    Date.now.timeIntervalSince(lastNavigationPathChange)
                        > Self.navigationSettlingInterval
                else {
                    return
                }
                navigationPath = NavigationPath()
            }
    }
}

#if DEBUG
    #Preview {
        @Previewable @State var path = NavigationPath()
        let repository = InMemoryWatchlistRepository()
        SearchView(
            navigationPath: $path,
            searchService: PreviewTheTVDBService(stub: .previewSearchResult),
            tvMaze: PreviewTVMazeService(stub: .preview),
            showIDMapping: InMemoryShowIDMapping(
                map: [TVDBSearchResult.previewSearchResult.id: Show.preview.id]
            ),
            analytics: RecordingAnalyticsService()
        )
        .environment(\.watchlistRepository, repository)
        .environment(PurchaseService.preview)
        .environment(
            \.watchlistPendingRemoval,
            WatchlistPendingRemoval(
                repository: repository,
                analytics: RecordingAnalyticsService()
            ))
    }
#endif
