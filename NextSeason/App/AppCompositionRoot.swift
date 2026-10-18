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
            modelContainer = try NextSeasonModelContainer.make()
            // Same defaults as `WatchlistRefreshService` (`.standard`), so the
            // refresh sees repair marks the repository records.
            repository = SwiftDataWatchlistRepository(
                context: ModelContext(modelContainer),
                rowMarks: WatchlistRowMarks(userDefaults: .standard),
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
            diagnostics: betaRefreshDiagnostics
        )
        watchlistPendingRemoval = WatchlistPendingRemoval(
            repository: repository,
            analytics: analyticsService,
            purchases: purchaseService
        )
        reviewPromptCoordinator = ReviewPromptCoordinator()
        let purchases = purchaseService
        let refresh = refreshService
        watchlistAccessReconciler = WatchlistAccessReconciler(
            repository: repository,
            access: { purchases.confirmedWatchlistAccess },
            waitForAccess: { await purchases.waitForInitialEntitlementResolution() },
            // Resumed shows may hold months-old status. Mark them first so any
            // refresh baselines them silently, then catch up only those IDs;
            // continuously active shows keep ordinary notification behavior.
            willResume: { shows in refresh.markForCatchUp(shows) },
            refreshAfterResume: { ids in await refresh.catchUp(showIDs: ids) }
        )
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

    /// Production-only launch wiring: MetricKit, notification routing,
    /// background refresh registration, and the launch analytics event.
    /// Skipped under `-UITesting` so XCUITests stay deterministic.
    /// Launch-attempt recording lives in `AppLaunchState.bootstrap` so crash
    /// loops can be detected before composition.
    func configureNonUITestRuntime() {
        MetricKitDiagnosticsSubscriber.installIfNeeded()

        // The coordinator that handles notification taps is attached from the view
        // layer (see ContentView). NotificationRouting is set up here and is able to
        // handle taps before ContentView is able to set the coordinator. Installing
        // the delegate here lets a launch-from-notification tap buffer until the
        // coordinator attaches.
        NotificationRouting.setAnalytics(analyticsService)
        NotificationRouting.setReviewPrompt(reviewPromptCoordinator)
        NotificationRouting.installDelegate()

        configureBackgroundRefresh()
        analyticsService.track(.appLaunched)
    }

    /// Opportunistic show ID mapping refresh; never blocks launch or Search.
    func refreshShowIDMappingIfNeeded() async {
        await showIDMappingRefresh?.refreshIfNeeded()
    }

    /// Registers the ~12h background watchlist refresh task and schedules the
    /// next run. Show ID mapping refresh stays foreground-only.
    private func configureBackgroundRefresh() {
        RefreshScheduler.registerBackgroundTask()
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
