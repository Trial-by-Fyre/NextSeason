//
//  AppCompositionRoot.swift
//  NextSeason
//

import SwiftData
import SwiftUI
import os

/// Owns long-lived app services and persistence so `NextSeasonApp` stays a thin
/// scene host.
///
/// Builds the SwiftData watchlist store, wires Search (TheTVDB + show ID
/// mapping) separately from detail/watchlist/refresh (TVMaze), and exposes
/// those dependencies for the SwiftUI environment. UI tests get an in-memory
/// store and mapping stub so they never touch the on-device watchlist.
///
/// Launch-attempt / crash-loop recording happens in `AppLaunchState.bootstrap`
/// *before* this type is created. `configureNonUITestRuntime()` is production
/// wiring only (MetricKit, notification routing, background refresh, analytics).
@MainActor
struct AppCompositionRoot {
    /// Watchlist SwiftData store (in-memory under `-UITesting`).
    let modelContainer: ModelContainer
    /// Persistence boundary injected into the SwiftUI environment.
    let watchlistRepository: any WatchlistRepository
    /// Foreground and background watchlist refresh.
    let refreshService: WatchlistRefreshService
    /// Shared undoable-removal coordinator for the root toast.
    let watchlistPendingRemoval: WatchlistPendingRemoval
    /// Local analytics and usage counters (no remote crash reporting).
    let analyticsService: AnalyticsService
    /// Notification permission and season-change delivery.
    let notificationService: NotificationService
    /// Beta/TestFlight refresh outcome samples for the Diagnostics screen.
    let betaRefreshDiagnostics: BetaRefreshDiagnostics
    /// Canonical show / season provider (detail, watchlist, refresh).
    let tvMaze: any TVMazeService
    /// Guest search provider (paginated series search only).
    let theTVDB: any TheTVDBService
    /// Offline TheTVDB → TVMaze filter and TVMaze title/poster overlay for Search.
    let showIDMapping: any ShowIDMapping
    /// False when the bundled mapping database could not be opened; Search must
    /// not treat the fallback empty map as "no matches."
    let isLocalShowIDMappingAvailable: Bool
    /// Opportunistic on-device mapping refresh; `nil` under UI tests.
    let showIDMappingRefresh: ShowIDMappingRefreshService?
    /// StoreKit purchases, Plus entitlement, and the free watchlist cap.
    let purchaseService: PurchaseService
    /// Per-version review request after the first show notification.
    let reviewPromptCoordinator: ReviewPromptCoordinator
    /// Pauses / resumes saved shows to match confirmed Plus access.
    let watchlistAccessReconciler: WatchlistAccessReconciler

    init() throws {
        // DEBUG recovery fixture only; a no-op otherwise.
        try RecoveryFixture.throwIfOpenFailureInjected()
        // Store-tied defaults (refresh watermark, catch-up marks, pause state).
        // Isolated under the recovery fixture so its disposable store never
        // advances or prunes state belonging to the real watchlist.
        let watchlistDefaults = RecoveryFixture.watchlistDefaults ?? .standard
        analyticsService = AnalyticsService()
        notificationService = NotificationService(analytics: analyticsService)
        betaRefreshDiagnostics = BetaRefreshDiagnostics()
        let liveTVMaze = TVMazeClient()  // same instance is passed into mapping refresh below
        tvMaze = liveTVMaze
        theTVDB = TheTVDBClient()

        let repository: any WatchlistRepository
        if UITestingConfiguration.isEnabled {
            // XCUITest: in-memory store + repository so runs stay isolated and don't
            // touch the developer's on-device watchlist. Purchases are stubbed as
            // unlimited so existing tests are not gated by the free-tier cap.
            modelContainer = try NextSeasonModelContainer.make(
                configuration: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            // Severance preview ids used by UI tests / PreviewTheTVDBService.
            showIDMapping = InMemoryShowIDMapping(map: [371980: 44933])
            isLocalShowIDMappingAvailable = true
            showIDMappingRefresh = nil
            // Never inherit a downgrade alert flag from an earlier simulator run.
            UserDefaults.standard.removeObject(
                forKey: WatchlistAccessReconciler.pausedAlertPendingKey)
            if let pausedShow = Self.uiTestPausedShowSeed() {
                // Paused-row UI test: Free access so reconciliation keeps the
                // seeded show paused (and shows no alert, since nothing newly pauses).
                repository = InMemoryWatchlistRepository(seed: [pausedShow])
                purchaseService = .stub(isStoreEntitled: false)
            } else {
                repository = InMemoryWatchlistRepository()
                purchaseService = .stub(isStoreEntitled: true)
            }
        } else {
            // The default configuration is the production store; the recovery
            // fixture substitutes a disposable one.
            modelContainer = try NextSeasonModelContainer.make(
                configuration: try RecoveryFixture.storeConfiguration() ?? ModelConfiguration()
            )
            // Same defaults as `WatchlistRefreshService`, so the refresh sees
            // repair marks the repository records.
            repository = SwiftDataWatchlistRepository(
                context: ModelContext(modelContainer),
                rowMarks: WatchlistRowMarks(userDefaults: watchlistDefaults),
                analytics: analyticsService)
            // Mapping already retries from the bundled baseline. If that still
            // fails, keep an empty in-memory map for export/reverse lookup but
            // mark Search unavailable so results are not mislabeled as misses.
            do {
                let database = try ShowIDMappingDatabase.openDefault()
                showIDMapping = database
                isLocalShowIDMappingAvailable = true
                showIDMappingRefresh = ShowIDMappingRefreshService(
                    database: database,
                    tvMaze: liveTVMaze
                )
            } catch {
                AppDiagnosticsLogger.breadcrumb("show_id_mapping_open_failed_using_empty_map")
                AppDiagnosticsLogger.logger(for: .cache).error(
                    "show_id_mapping_open_failed_using_empty_map error=\(String(describing: error), privacy: .public)"
                )
                showIDMapping = InMemoryShowIDMapping(map: [:])
                isLocalShowIDMappingAvailable = false
                showIDMappingRefresh = nil
            }
            purchaseService = PurchaseService()
        }

        watchlistRepository = repository
        refreshService = WatchlistRefreshService(
            tvMaze: tvMaze,
            repository: repository,
            notifications: notificationService,
            analytics: analyticsService,
            diagnostics: betaRefreshDiagnostics,
            userDefaults: watchlistDefaults
        )
        watchlistPendingRemoval = WatchlistPendingRemoval(
            repository: repository,
            analytics: analyticsService,
            purchases: purchaseService
        )
        reviewPromptCoordinator = ReviewPromptCoordinator()
        let purchases = purchaseService
        let refresh = refreshService
        let pendingRemoval = watchlistPendingRemoval
        watchlistAccessReconciler = WatchlistAccessReconciler(
            repository: repository,
            userDefaults: watchlistDefaults,
            access: { purchases.confirmedWatchlistAccess },
            waitForAccess: { await purchases.waitForInitialEntitlementResolution() },
            // A show in its undo window is about to be deleted; it must not take
            // one of the free slots (see `excludedShowIDs`).
            excludedShowIDs: { pendingRemoval.deferredRemovalShowID.map { [$0] } ?? [] },
            // Resumed shows may hold months-old status. Mark them first so any
            // refresh baselines them silently, then catch up only those IDs;
            // continuously active shows keep ordinary notification behavior.
            willResume: { shows in refresh.markForCatchUp(shows) },
            refreshAfterResume: { ids in await refresh.catchUp(showIDs: ids) }
        )
        // A row left out while its removal was pending stays saved if the
        // removal is undone, cancelled, or fails; apply the limit to it now.
        pendingRemoval.addOutcomeHandler { [weak watchlistAccessReconciler] outcome in
            switch outcome {
            case .undone, .cancelled, .failed:
                Task { await watchlistAccessReconciler?.reconcile() }
            case .committed, .replaced:
                break
            }
        }
    }

    /// A paused preview show when UI tests pass `-UITestingSeedPausedShow`.
    /// Always `nil` outside DEBUG builds.
    private static func uiTestPausedShowSeed() -> TrackedShow? {
        #if DEBUG
            guard UITestingConfiguration.seedsPausedShow else { return nil }
            var paused = TrackedShow(from: .preview)
            paused.isPaused = true
            return paused
        #else
            return nil
        #endif
    }

    /// Production-only wiring that needs the opened store: MetricKit,
    /// notification routing services, the background refresh handler and
    /// schedule, and the launch analytics event. Skipped under `-UITesting` so
    /// XCUITests stay deterministic.
    ///
    /// Runs on every successful composition, which can be after launch when a
    /// recovery Try Again or Reset Local Data succeeds. So it must not do
    /// launch-only system registration: `NextSeasonApp.init` registers the
    /// background task and installs the notification delegate before composing.
    /// Launch-attempt recording lives in `AppLaunchState.bootstrap` so crash
    /// loops can be detected before composition.
    func configureNonUITestRuntime() {
        MetricKitDiagnosticsSubscriber.installIfNeeded()

        // The delegate (installed at launch) buffers a launch-from-notification
        // tap until ContentView attaches the coordinator; these services let it
        // record analytics and the review prompt from now on.
        NotificationRouting.setAnalytics(analyticsService)
        NotificationRouting.setReviewPrompt(reviewPromptCoordinator)

        configureBackgroundRefresh()
        analyticsService.track(.appLaunched)
    }

    /// Opportunistic show ID mapping refresh; never blocks launch or Search.
    func refreshShowIDMappingIfNeeded() async {
        await showIDMappingRefresh?.refreshIfNeeded()
    }

    /// Attaches the ~12h background watchlist refresh to the task registered at
    /// launch, and schedules the next run. Show ID mapping refresh stays
    /// foreground-only.
    private func configureBackgroundRefresh() {
        let refreshServiceForBackground = refreshService
        let purchasesForBackground = purchaseService
        let reconcilerForBackground = watchlistAccessReconciler
        AppDiagnosticsLogger.breadcrumb("refresh_scheduler_configure")
        RefreshScheduler.configure(diagnostics: betaRefreshDiagnostics) {
            AppDiagnosticsLogger.logTaskStart("background_watchlist_refresh")
            // A background launch may not have read entitlements yet. Apply a
            // confirmed lapse first so paused shows are not refreshed or notified.
            await purchasesForBackground.refreshEntitlements()
            await reconcilerForBackground.reconcile()
            let outcome = await refreshServiceForBackground.refreshAll(recordDiagnostics: true)
            AppDiagnosticsLogger.logTaskComplete("background_watchlist_refresh")
            if Task.isCancelled { return false }
            return outcome?.succeededForBackgroundTask ?? false
        }
        RefreshScheduler.scheduleNextRefresh()
    }
}
