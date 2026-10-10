//
//  WatchlistView.swift
//  NextSeason
//

import SwiftUI

/// Local watchlist: status-grouped tracked shows, optional in-list search (toolbar
/// toggle), pull-to-refresh, star (deferred) and swipe (immediate) undoable
/// removal, and notification deep-link push into Show Detail.
///
/// Lifecycle:
/// - `.task(id: watchlistReloadToken)` creates the view model and reloads when the
///   tab is selected (token bump from `ContentView` / the navigation coordinator).
/// - `.onAppear` applies a buffered deep link and, after the first load, refreshes
///   on later tab returns without double-fetching the initial presentation.
/// - Pending-removal outcomes from `WatchlistPendingRemoval` keep the list in
///   sync across commit, undo, replace, and failure paths.
struct WatchlistView: View {
    @Environment(\.watchlistRepository) private var repository
    @Environment(\.watchlistRefreshService) private var refreshService
    @Environment(\.notificationService) private var notificationService
    @Environment(\.watchlistPendingRemoval) private var removalCoordinator
    @Environment(\.analytics) private var analytics
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PurchaseService.self) private var purchases
    /// Optional so previews without the app composition still render.
    @Environment(WatchlistAccessReconciler.self) private var accessReconciler:
        WatchlistAccessReconciler?

    @Binding var navigationPath: NavigationPath
    private let tvMaze: any TVMazeService
    /// Root tab selection so in-list search can dismiss when leaving Watchlist.
    private let selectedTab: AppNavigationCoordinator.Tab
    /// Called when the user taps "Find a Show" from the empty state, so the host
    /// can switch to the Search tab.
    private let onFindShow: () -> Void
    /// Called after a watchlist removal is persisted (not on undo).
    private let onWatchlistChanged: () -> Void
    /// Bumped when the user selects the Watchlist tab so the list reloads.
    private let watchlistReloadToken: Int
    /// Identifies a pending notification deep link so this view can push its detail
    /// once its `NavigationStack` is on screen. Changes when a new deep link arrives.
    private let pendingDetailToken: Int?
    /// Applies the pending notification deep link (see `pendingDetailToken`). The
    /// coordinator decides whether the push animates based on the tap context.
    private let onApplyPendingDetail: () -> Void
    @State private var viewModel: WatchlistViewModel?
    @State private var notificationStatus = NotificationStatusModel()
    /// True after `.task(id:)` finishes its first (or token-driven) reload, so
    /// `.onAppear` only refreshes on later tab returns — not during first load.
    @State private var hasCompletedInitialLoad = false
    /// Sections the user has collapsed. Missing IDs are treated as expanded.
    /// Restored from UserDefaults on first appearance; saved whenever it changes.
    @State private var collapsedSections: Set<WatchlistSection>
    /// Global frames for watchlist rows, used to anchor the swipe-delete toast
    /// near the deleted row instead of the bottom of the screen.
    @State private var rowFrames: [Int: CGRect] = [:]
    /// Whether the navigation-bar search drawer is visible (toggled from the toolbar).
    @State private var isSearchPresented = false

    init(
        navigationPath: Binding<NavigationPath>,
        tvMaze: any TVMazeService,
        selectedTab: AppNavigationCoordinator.Tab = .watchlist,
        watchlistReloadToken: Int = 0,
        pendingDetailToken: Int? = nil,
        onApplyPendingDetail: @escaping () -> Void = {},
        onFindShow: @escaping () -> Void = {},
        onWatchlistChanged: @escaping () -> Void = {}
    ) {
        _navigationPath = navigationPath
        self.tvMaze = tvMaze
        self.selectedTab = selectedTab
        self.watchlistReloadToken = watchlistReloadToken
        self.pendingDetailToken = pendingDetailToken
        self.onApplyPendingDetail = onApplyPendingDetail
        self.onFindShow = onFindShow
        self.onWatchlistChanged = onWatchlistChanged
        _collapsedSections = State(initialValue: WatchlistPreferences().collapsedSections)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if let viewModel {
                    content(for: viewModel)
                } else {
                    ProgressView("Loading watchlist…")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appScreenBackground()
            .navigationTitle("Watchlist")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    watchlistSearchToolbarButton
                }
            }
            .appAboutToolbarButton()
            .modifier(
                WatchlistSearchPresentationModifier(
                    isPresented: $isSearchPresented,
                    searchText: watchlistSearchTextBinding
                )
            )
            .onChange(of: selectedTab) { _, tab in
                if tab != .watchlist {
                    dismissWatchlistSearch(animated: false)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    dismissWatchlistSearch(animated: false)
                }
            }
            .onChange(of: isSearchPresented) { _, isPresented in
                if !isPresented {
                    viewModel?.searchText = ""
                }
            }
            .onChange(of: collapsedSections) { _, sections in
                WatchlistPreferences().collapsedSections = sections
            }
            .navigationDestination(for: TrackedShow.self) { tracked in
                ShowDetailView(
                    show: Show(tracked: tracked),
                    service: tvMaze,
                    repository: repository,
                    notifications: notificationService,
                    analytics: analytics,
                    purchases: purchases,
                    isTracked: true,
                    onWatchlistChanged: onWatchlistChanged
                )
                .onAppear {
                    analytics.track(.watchlistItemOpened(showID: tracked.id))
                    // Push-only: tab switches that re-show detail must not cancel
                    // a pending removal started on another tab.
                    removalCoordinator?.dismissPendingRemovalForNavigation()
                }
            }
            .task(id: watchlistReloadToken) {
                await prepareAndReload()
            }
            .onAppear {
                analytics.track(.watchlistViewed)
                // Apply a deep link that arrived while this tab was off screen; the
                // stack is now mounted so the push lands instead of being dropped.
                onApplyPendingDetail()
                // First presentation is owned by `.task(id:)`. Refresh here only
                // after that initial load has finished (tab return / reappear).
                guard hasCompletedInitialLoad else { return }
                Task { await reloadScreen() }
            }
            .onChange(of: pendingDetailToken) { _, token in
                // A deep link arrived while the watchlist is already on screen.
                guard token != nil else { return }
                onApplyPendingDetail()
            }
            .refreshNotificationStatus(notificationStatus)
        }
    }

    /// Creates the view model on first need, then reloads list + notification status.
    private func prepareAndReload() async {
        guard let removalCoordinator else { return }
        if viewModel == nil {
            viewModel = WatchlistViewModel(
                repository: repository,
                refreshService: refreshService,
                removalCoordinator: removalCoordinator,
                analytics: analytics,
                accessReconciler: accessReconciler
            )
        }
        await reloadScreen()
        hasCompletedInitialLoad = true
    }

    private func reloadScreen() async {
        await viewModel?.reload()
        await notificationStatus.refresh(using: notificationService)
    }

    private func enableNotificationsFromBanner() async {
        await notificationService.enableNotificationsFromSettingsEntryPoint()
        await notificationStatus.refresh(using: notificationService)
    }

    private var watchlistSearchTextBinding: Binding<String> {
        Binding(
            get: { viewModel?.searchText ?? "" },
            set: { viewModel?.searchText = $0 }
        )
    }

    private var watchlistSearchToolbarButton: some View {
        Button {
            toggleWatchlistSearch()
        } label: {
            Image(systemName: isSearchPresented ? "xmark" : "magnifyingglass")
                .accessibilityHidden(true)
        }
        .accessibilityLabel(
            isSearchPresented
                ? String(localized: "Close watchlist search")
                : String(localized: "Search watchlist")
        )
        .accessibilityIdentifier(AccessibilityID.Watchlist.searchButton)
    }

    private func toggleWatchlistSearch() {
        if isSearchPresented {
            dismissWatchlistSearch(animated: true)
        } else {
            presentWatchlistSearch()
        }
    }

    /// Shows the drawer search field below the large title. Omitting `isPresented`
    /// on `.searchable` keeps the field in the drawer instead of animating into
    /// the navigation bar.
    private func presentWatchlistSearch() {
        guard viewModel != nil else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            isSearchPresented = true
        }
    }

    private func dismissWatchlistSearch(animated: Bool = true) {
        guard isSearchPresented else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                isSearchPresented = false
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isSearchPresented = false
            }
        }
    }

    @ViewBuilder
    private func watchlistRow(for tracked: TrackedShow, viewModel: WatchlistViewModel) -> some View
    {
        let isPending = viewModel.isPendingRemoval(tracked)
        HStack(spacing: AppSpacing.tight) {
            Group {
                if isPending {
                    ShowRowLabel(tracked: tracked)
                        .accessibilityIdentifier(
                            "\(AccessibilityID.Watchlist.row).\(tracked.id)"
                        )
                        .accessibilityAction(named: String(localized: "Undo removal")) {
                            Task { await viewModel.undoPendingRemoval() }
                        }
                } else if tracked.isPaused {
                    // Paused (Plus lapsed): no NavigationLink, so Show Details
                    // cannot be opened. Removal stays available.
                    ShowRowLabel(tracked: tracked)
                        .accessibilityIdentifier(
                            "\(AccessibilityID.Watchlist.row).\(tracked.id)"
                        )
                        .accessibilityAction(named: String(localized: "Remove from watchlist")) {
                            deleteImmediately(tracked, viewModel: viewModel)
                        }
                } else {
                    NavigationLink(value: tracked) {
                        ShowRowLabel(tracked: tracked)
                    }
                    .buttonStyle(.plain)
                    .showDetailLinkAccessibility()
                    .accessibilityIdentifier(
                        "\(AccessibilityID.Watchlist.row).\(tracked.id)"
                    )
                    // VoiceOver cannot use the list swipe gesture, so expose the
                    // same immediate-delete path as `.onDelete` as a rotor action.
                    .accessibilityAction(named: String(localized: "Remove from watchlist")) {
                        deleteImmediately(tracked, viewModel: viewModel)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ShowRowTrackButton(
                showID: tracked.id,
                showName: tracked.name,
                isTracked: !isPending,
                isUpdating: false,
                isPendingRemoval: isPending,
                trackButtonIdentifier: AccessibilityID.Watchlist.trackButton
            ) { anchor in
                if isPending {
                    Task { await viewModel.undoPendingRemoval() }
                } else {
                    viewModel.requestRemoval(
                        tracked,
                        anchor: anchor,
                        source: .watchlist
                    )
                }
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        updateRowFrame(tracked.id, from: geometry)
                    }
                    .onChange(of: geometry.frame(in: .global)) { _, _ in
                        updateRowFrame(tracked.id, from: geometry)
                    }
            }
        }
    }

    /// VoiceOver row action: same immediate-delete path as swipe-to-delete.
    private func deleteImmediately(_ tracked: TrackedShow, viewModel: WatchlistViewModel) {
        withAnimation(.easeInOut(duration: 0.35)) {
            viewModel.deleteImmediately(
                tracked,
                rowAnchor: rowFrames[tracked.id] ?? .zero
            )
        }
        rowFrames[tracked.id] = nil
    }

    /// Swipe-to-delete for one rendered section's rows.
    private func deleteRows(
        at offsets: IndexSet,
        in shows: [TrackedShow],
        viewModel: WatchlistViewModel
    ) {
        // Avoid notifyWatchlistDataChanged here — bumping the
        // reload token mid-delete jumps list scroll position.
        viewModel.deleteImmediately(at: offsets, in: shows, rowAnchors: rowFrames)
        for index in offsets {
            guard shows.indices.contains(index) else { continue }
            rowFrames[shows[index].id] = nil
        }
    }

    @ViewBuilder
    private func content(for viewModel: WatchlistViewModel) -> some View {
        @Bindable var viewModel = viewModel

        switch viewModel.state {
        case .loading:
            ProgressView("Loading watchlist…")
                .controlSize(.large)
        case .loaded:
            // The List is kept mounted even when empty (empty state is an overlay)
            // so removing the last row doesn't tear the List down mid-animation,
            // which crashes UICollectionView with "invalid number of items".
            let presentation = WatchlistLoadedPresentation(
                viewModel: viewModel,
                showsNotificationBanner: notificationStatus.showsDisabledBanner
            )
            List {
                if presentation.showsNotificationBanner {
                    NotificationsDisabledBanner(
                        buttonTitle: notificationStatus.enablementButtonTitle
                    ) {
                        Task { await enableNotificationsFromBanner() }
                    }
                }
                // Keeps the list scroll-backed so the large navigation title renders
                // when there are no rows to show (empty watchlist or no search
                // matches, and no banner).
                if presentation.showsTitlePreservingSpacer {
                    Color.clear
                        .frame(height: 1)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .accessibilityHidden(true)
                }
                ForEach(viewModel.filteredSectionGroups) { group in
                    WatchlistCollapsibleSection(
                        section: group.section,
                        shows: group.shows,
                        isExpanded: expansionBinding(for: group.section),
                        onDelete: { offsets in
                            deleteRows(at: offsets, in: group.shows, viewModel: viewModel)
                        }
                    ) { tracked in
                        watchlistRow(for: tracked, viewModel: viewModel)
                    }
                }
                let pausedShows = viewModel.filteredPausedShows
                if !pausedShows.isEmpty {
                    PausedWatchlistSection(
                        shows: pausedShows,
                        onDelete: { offsets in
                            deleteRows(at: offsets, in: pausedShows, viewModel: viewModel)
                        }
                    ) { tracked in
                        watchlistRow(for: tracked, viewModel: viewModel)
                    }
                }
                // Omit attribution when the empty/no-results overlay is up — a List
                // footer behind ContentUnavailableView clips, overlaps the star, and
                // leaves a misaligned white strip (same pattern as Search idle/empty).
                if presentation.showsAttribution {
                    Section {
                    } footer: {
                        TVMazeAttributionView()
                    }
                }
            }
            .animation(
                .easeInOut(duration: 0.35),
                value: viewModel.filteredShows.map {
                    "\($0.id):\($0.nextSeason.headline):\($0.isPaused)"
                }
            )
            .appPlainListStyle()
            // Plain lists still insert default spacing between sections, but not
            // before the first header or after the last row. Collapse that gap
            // so later headers sit as tightly as the first one under the title.
            .listSectionSpacing(0)
            .refreshable {
                await viewModel.refreshFromNetwork()
                await notificationStatus.refresh(using: notificationService)
            }
            .overlay {
                switch presentation.overlay {
                case .none:
                    EmptyView()
                case .emptyWatchlist:
                    emptyState
                case .noSearchResults:
                    noSearchResults(query: viewModel.searchText)
                }
            }
        case .failed(let message):
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
                Button("Try Again") {
                    Task { await viewModel.reload() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("No Tracked Shows")
                    .appAccentText()
            } icon: {
                Image(systemName: "star")
                    .appPrimaryText()
            }
        } description: {
            Text(FirstRunCopy.watchlistEmptyDescription)
                .appSecondaryText()
        } actions: {
            Button("Find a Show") {
                onFindShow()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Watchlist.emptyState)
        .onAppear {
            analytics.track(.emptyWatchlistShown)
        }
    }

    private func noSearchResults(query: String) -> some View {
        ContentUnavailableView {
            Label {
                Text("No Matches")
                    .appAccentText()
            } icon: {
                Image(systemName: "magnifyingglass")
                    .appPrimaryText()
            }
        } description: {
            Text(
                String(
                    localized:
                        "No tracked shows match “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”."
                )
            )
            .appSecondaryText()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(AccessibilityID.Watchlist.noResults)
    }

    private func expansionBinding(for section: WatchlistSection) -> Binding<Bool> {
        Binding(
            get: { !collapsedSections.contains(section) },
            set: { isExpanded in
                if isExpanded {
                    collapsedSections.remove(section)
                } else {
                    collapsedSections.insert(section)
                }
            }
        )
    }

    private func updateRowFrame(_ showID: Int, from geometry: GeometryProxy) {
        let frame = geometry.frame(in: .global)
        guard frame.width > 0, frame.height > 0 else { return }
        rowFrames[showID] = frame
    }
}

/// Applies `.searchable` only while watchlist search is open. The field stays in the
/// navigation-bar drawer (below the large title) because no `isPresented` binding is
/// passed to `.searchable`, which avoids UIKit's active-search jump into the bar.
private struct WatchlistSearchPresentationModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var searchText: String

    func body(content: Content) -> some View {
        if isPresented {
            content.searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search Watchlist"
            )
        } else {
            content
        }
    }
}

/// A status section the user can collapse.
private struct WatchlistCollapsibleSection<Row: View>: View {
    let section: WatchlistSection
    let shows: [TrackedShow]
    @Binding var isExpanded: Bool
    var onDelete: ((IndexSet) -> Void)?
    @ViewBuilder let row: (TrackedShow) -> Row

    private var displayedTitle: String {
        section.headerTitle(showCount: shows.count, isExpanded: isExpanded)
    }

    /// Default `.headline` line height; scales with Dynamic Type so hit spacing
    /// shrinks once the title itself already meets the 44pt tap target.
    @ScaledMetric(relativeTo: .headline) private var headlineLineHeight: CGFloat = 30

    /// Extra vertical hit area so a text-sized header still meets Apple's 44pt
    /// minimum without adding visible padding.
    private var headerVerticalHitSpacing: CGFloat {
        max(0, (44 - headlineLineHeight) / 2)
    }

    var body: some View {
        Section(isExpanded: $isExpanded) {
            ForEach(shows) { tracked in
                row(tracked)
            }
            .onDelete(perform: onDelete)
        } header: {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: AppSpacing.tight) {
                    Text(displayedTitle)
                        .font(.headline)
                        .appPrimaryText()
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColor.background)
                .padding(.vertical, headerVerticalHitSpacing)
                .contentShape(Rectangle())
                .padding(.vertical, -headerVerticalHitSpacing)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(displayedTitle)
            .accessibilityInputLabels([section.title])
            .accessibilityHint(
                isExpanded
                    ? String(localized: "Collapse section")
                    : String(localized: "Expand section")
            )
            .accessibilityAddTraits(.isHeader)
        }
    }
}

#if DEBUG
    #Preview {
        @Previewable @State var path = NavigationPath()
        let repository = InMemoryWatchlistRepository()
        let analytics = RecordingAnalyticsService()
        WatchlistView(navigationPath: $path, tvMaze: PreviewTVMazeService(stub: .preview))
            .environment(\.watchlistRepository, repository)
            .environment(\.analytics, analytics)
            .environment(\.notificationService, NotificationService(analytics: analytics))
            .environment(PurchaseService.preview)
            .environment(
                \.watchlistPendingRemoval,
                WatchlistPendingRemoval(
                    repository: repository,
                    analytics: analytics
                ))
    }
#endif
