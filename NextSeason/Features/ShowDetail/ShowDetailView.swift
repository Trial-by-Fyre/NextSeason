//
//  ShowDetailView.swift
//  NextSeason
//

import SwiftUI

/// Show detail: artwork, metadata, the derived next-season status, and a
/// formatted summary, plus track / untrack.
///
/// Lifecycle: `.task(id:)` loads seasons. Pending-removal cancellation when
/// navigating *to* detail lives on the parent `navigationDestination` so tab
/// switches that re-show an existing detail screen do not abort a removal.
/// `.onAppear`, pending-removal outcomes, and Plus pause/resume changes
/// reconcile tracked state.
struct ShowDetailView: View {
    @Environment(\.watchlistPendingRemoval) private var removalCoordinator
    @Environment(\.onAutomationDetailLoaded) private var onAutomationDetailLoaded
    @Environment(\.presentPlusStore) private var presentPlusStore
    /// Optional so previews without the app composition still render.
    @Environment(WatchlistAccessReconciler.self) private var accessReconciler:
        WatchlistAccessReconciler?

    @State private var viewModel: ShowDetailViewModel

    private let analytics: any AnalyticsTracking
    private let onWatchlistChanged: () -> Void

    init(
        show: Show,
        service: any TVMazeService,
        repository: any WatchlistRepository,
        notifications: any NotificationManaging,
        analytics: any AnalyticsTracking,
        purchases: PurchaseService,
        isTracked: Bool = false,
        onWatchlistChanged: @escaping () -> Void = {}
    ) {
        _viewModel = State(
            initialValue: ShowDetailViewModel(
                show: show,
                service: service,
                repository: repository,
                notifications: notifications,
                analytics: analytics,
                purchases: purchases,
                initialIsTracked: isTracked
            )
        )
        self.analytics = analytics
        self.onWatchlistChanged = onWatchlistChanged
    }

    var body: some View {
        detailContent(viewModel: viewModel)
            .task(id: viewModel.initialShow.id) {
                await viewModel.load(removalCoordinator: removalCoordinator)
            }
            .onAppear {
                analytics.track(.showDetailViewed(showID: viewModel.initialShow.id))
                // Reconcile tracked state on reappear (e.g. returning to this screen
                // after the show was removed on the Watchlist tab).
                Task { await viewModel.refreshTrackedState(removalCoordinator: removalCoordinator) }
            }
            .onChange(of: removalCoordinator?.outcomeGeneration) { _, _ in
                guard removalCoordinator?.lastOutcome != nil else { return }
                Task {
                    await viewModel.handlePendingRemovalOutcome(
                        removalCoordinator: removalCoordinator
                    )
                }
            }
            // A Plus lapse or restore can pause / resume this show while the screen
            // stays mounted; re-read so the star (and its add vs. remove action)
            // matches. Pending-removal exclusion still applies.
            .onChange(of: accessReconciler?.changeGeneration) { _, _ in
                Task {
                    await viewModel.refreshTrackedState(removalCoordinator: removalCoordinator)
                }
            }
            .onChange(of: viewModel.loadState) { _, loadState in
                guard ProfileFlowConfiguration.isEnabled, loadState == .loaded else { return }
                onAutomationDetailLoaded?()
            }
    }

    private func detailContent(viewModel: ShowDetailViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                header(viewModel: viewModel)
                nextSeasonSection(viewModel: viewModel)
                aboutSection(viewModel: viewModel)
                TVMazeAttributionView()
                    .frame(maxWidth: .infinity)
            }
            .padding(AppSpacing.screen)
        }
        .appScreenBackground()
        .scrollContentBackground(.hidden)
        .navigationTitle(viewModel.displayShow.name)
        .navigationBarTitleDisplayMode(.inline)
        .watchlistNotificationPromptAlerts(
            prompt: viewModel.notificationPrompt,
            notificationService: viewModel.notificationService
        )
        .alert(
            "Couldn't Update Watchlist",
            isPresented: Binding(
                get: { viewModel.watchlistActionErrorMessage != nil },
                set: { if !$0 { viewModel.clearWatchlistActionError() } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.clearWatchlistActionError()
            }
        } message: {
            Text(viewModel.watchlistActionErrorMessage ?? "")
        }
    }

    private func header(viewModel: ShowDetailViewModel) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.screen) {
            poster(viewModel: viewModel)
            VStack(alignment: .leading, spacing: AppSpacing.tight) {
                Text(viewModel.displayShow.name)
                    .font(.title2.bold())
                    .appAccentText()
                Text(viewModel.displayShow.status.displayLabel)
                    .font(.subheadline)
                    .appSecondaryText()
                if let network = viewModel.displayShow.network {
                    Text(network)
                        .font(.subheadline)
                        .appSecondaryText()
                }
                if !viewModel.displayShow.genres.isEmpty {
                    Text(viewModel.displayShow.genres.genreDisplayLine)
                        .font(.caption)
                        .appSecondaryText()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(headerAccessibilityLabel(for: viewModel))
            Spacer(minLength: AppSpacing.tight)
            ShowRowTrackButton(
                showID: viewModel.displayShow.id,
                showName: viewModel.displayShow.name,
                isTracked: viewModel.isTracked,
                isUpdating: viewModel.isUpdatingWatchlist,
                isPendingRemoval: removalCoordinator?.pendingRemoval?.id
                    == viewModel.displayShow.id,
                trackButtonIdentifier: AccessibilityID.ShowDetail.trackButton
            ) {
                Task { await handleTrackButtonTap(viewModel: viewModel) }
            }
        }
    }

    private func headerAccessibilityLabel(for viewModel: ShowDetailViewModel) -> String {
        var parts = [
            viewModel.displayShow.name,
            viewModel.displayShow.status.displayLabel,
        ]
        if let network = viewModel.displayShow.network {
            parts.append(network)
        }
        if !viewModel.displayShow.genres.isEmpty {
            parts.append(viewModel.displayShow.genres.genreDisplayLine)
        }
        return parts.joined(separator: ", ")
    }

    private func handleTrackButtonTap(viewModel: ShowDetailViewModel) async {
        await viewModel.handleTrackButton(
            removalCoordinator: removalCoordinator,
            onWatchlistChanged: onWatchlistChanged,
            onPaywallRequired: {
                presentPlusStore? {
                    // Finish the blocked add after Plus unlocks. Retry only while
                    // still untracked so the shared toggle can never remove the show.
                    guard !viewModel.isTracked else { return }
                    Task { await handleTrackButtonTap(viewModel: viewModel) }
                }
            }
        )
    }

    // Intentionally duplicated with ShowRowLabel.poster — see the comment there.
    private func poster(viewModel: ShowDetailViewModel) -> some View {
        AsyncImage(url: viewModel.displayShow.posterMediumURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .empty, .failure:
                Rectangle()
                    .fill(.quaternary)
                    .overlay { Image(systemName: "tv") }
            @unknown default:
                Rectangle().fill(.quaternary)
            }
        }
        .frame(width: 100, height: 150)
        .clipShape(.rect(cornerRadius: 10))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func nextSeasonSection(viewModel: ShowDetailViewModel) -> some View {
        let card = VStack(alignment: .leading, spacing: AppSpacing.tight) {
            Text("Next Season")
                .font(.headline)
                .appPrimaryText()

            switch viewModel.loadState {
            case .loading:
                HStack(spacing: AppSpacing.tight) {
                    ProgressView()
                    Text("Checking next season…")
                        .appSecondaryText()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .loaded:
                if let status = viewModel.nextSeasonStatus {
                    HStack(alignment: .top, spacing: AppSpacing.tight) {
                        Image(systemName: status.statusSymbolName)
                            .font(.subheadline)
                            .foregroundStyle(status.emphasisStyle())
                            .accessibilityHidden(true)
                        Text(status.headline)
                            .font(.body)
                            .appSecondaryText()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: AppSpacing.tight) {
                    Label {
                        Text(message)
                            .appSecondaryText()
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(AppColor.warning)
                    }
                    Button("Try Again") {
                        Task { await viewModel.load(removalCoordinator: removalCoordinator) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, AppSpacing.row)
        .appSurfaceCard()

        if case .failed = viewModel.loadState {
            card.accessibilityElement(children: .contain)
        } else {
            card
                .accessibilityElement(children: .combine)
                .accessibilityLabel(nextSeasonAccessibilityLabel(for: viewModel))
        }
    }

    private func nextSeasonAccessibilityLabel(for viewModel: ShowDetailViewModel) -> String {
        switch viewModel.loadState {
        case .loading:
            return String(localized: "Next Season, Checking next season status")
        case .loaded:
            if let status = viewModel.nextSeasonStatus {
                return String(localized: "Next Season, \(status.headline)")
            }
            return String(localized: "Next Season")
        case .failed(let message):
            return String(localized: "Next Season, \(message)")
        }
    }

    @ViewBuilder
    private func aboutSection(viewModel: ShowDetailViewModel) -> some View {
        let summary = SummaryFormatter.attributedSummary(from: viewModel.displayShow.summaryHTML)
        if summary != nil || viewModel.displayShow.tvMazeURL != nil {
            VStack(alignment: .leading, spacing: AppSpacing.tight) {
                if let summary {
                    Text("About")
                        .font(.headline)
                        .appPrimaryText()
                    Text(summary)
                        .font(.body)
                        .appSecondaryText()
                }
                if let url = viewModel.displayShow.tvMazeURL {
                    Link(destination: url) {
                        Label("View on TVMaze", systemImage: "arrow.up.right.square")
                            .frame(minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .font(.subheadline)
                    .padding(.top, AppSpacing.tight / 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if DEBUG
    #Preview("With summary") {
        NavigationStack {
            ShowDetailView(
                show: .preview,
                service: PreviewTVMazeService(stub: .preview),
                repository: InMemoryWatchlistRepository(),
                notifications: NotificationService(analytics: RecordingAnalyticsService()),
                analytics: RecordingAnalyticsService(),
                purchases: .preview
            )
        }
    }

    #Preview("Missing summary") {
        NavigationStack {
            ShowDetailView(
                show: .previewMissingSummary,
                service: PreviewTVMazeService(stub: .previewMissingSummary),
                repository: InMemoryWatchlistRepository(),
                notifications: NotificationService(analytics: RecordingAnalyticsService()),
                analytics: RecordingAnalyticsService(),
                purchases: .preview
            )
        }
    }
#endif
