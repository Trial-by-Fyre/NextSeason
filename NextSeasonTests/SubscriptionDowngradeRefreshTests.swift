//
//  SubscriptionDowngradeRefreshTests.swift
//  NextSeasonTests
//

import CoreGraphics
import Foundation
import Testing
import UserNotifications

@testable import NextSeason

// MARK: - Shared fixtures

/// TVMaze stub that can hold one fetch of one show until the test releases it.
///
/// `waitUntilGatedFetchStarts()` returns once that fetch is suspended, so a test
/// can change state at a known point without sleeps or yield loops. Main-actor
/// isolated (like the refresh service), so its state needs no locking.
@MainActor
private final class GatedTVMazeService: TVMazeService {
    var showByID: [Int: Show] = [:]
    var updates: [Int: Date] = [:]
    /// Shows whose next fetch throws (one failure each).
    var failNextFetch: Set<Int> = []
    private(set) var fetchedShowIDs: [Int] = []

    private var gatedShowID: Int?
    private var gateRespondsAtRequestTime = false
    private var gateStarted = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var gateRelease: CheckedContinuation<Void, Never>?

    /// Holds the next fetch of `showID` until `releaseGatedFetch()`.
    ///
    /// - Parameter respondAtRequestTime: When true, the response is fixed when the
    ///   request is made (an already-received response delivered late). When false,
    ///   it is read on release (a request that reaches the server late).
    func gateNextFetch(of showID: Int, respondAtRequestTime: Bool = false) {
        gatedShowID = showID
        gateRespondsAtRequestTime = respondAtRequestTime
        gateStarted = false
    }

    func waitUntilGatedFetchStarts() async {
        if gateStarted { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func releaseGatedFetch() {
        gateRelease?.resume()
        gateRelease = nil
    }

    // Witnesses are explicitly main-actor: the protocol is `nonisolated`, and an
    // async requirement can be satisfied by an isolated method (callers hop).
    @MainActor func searchShows(matching query: String) async throws -> [Show] { [] }

    @MainActor func lookupShow(theTVDBID: Int) async throws -> Show {
        throw TVMazeError.notFound
    }

    @MainActor func show(id: Int, bypassCache: Bool) async throws -> Show {
        fetchedShowIDs.append(id)
        var response: Show?
        if id == gatedShowID {
            gatedShowID = nil
            if gateRespondsAtRequestTime { response = showByID[id] }
            gateStarted = true
            startWaiter?.resume()
            startWaiter = nil
            await withCheckedContinuation { gateRelease = $0 }
        }
        if failNextFetch.remove(id) != nil { throw URLError(.notConnectedToInternet) }
        guard let show = response ?? showByID[id] else {
            throw URLError(.notConnectedToInternet)
        }
        return show
    }

    @MainActor func updatedShows(since period: TVMazeUpdatePeriod) async throws -> [Int: Date] {
        updates
    }

    /// A first refresh has no coverage watermark and asks for the full map.
    @MainActor func allUpdatedShows() async throws -> [Int: Date] {
        updates
    }
}

@MainActor
private final class RecordingNotifications: NotificationDelivering {
    private(set) var delivered: [SeasonNotificationContent] = []
    func deliver(_ content: SeasonNotificationContent) async { delivered.append(content) }
    var showIDs: [Int] { delivered.map(\.showID) }
}

/// Next-season shapes `NextSeasonCalculator` derives from season data.
private enum Shape {
    case returning
    case announced
    case scheduled(Date)
    case ended
}

private let baseUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)
private let upcomingPremiere = Calendar.current.date(byAdding: .day, value: 30, to: .now)!
private let laterPremiere = Calendar.current.date(byAdding: .day, value: 60, to: .now)!

private func show(_ id: Int, _ shape: Shape, updatedAt: Date = baseUpdatedAt) -> Show {
    var seasons = [
        Season(
            id: id * 10 + 1, number: 1, premiereDate: TVMazeDate.dateOnly("2022-02-18"),
            endDate: TVMazeDate.dateOnly("2022-04-08"), episodeOrder: 9)
    ]
    var status = ShowStatus.running
    switch shape {
    case .returning:
        break
    case .announced:
        seasons.append(
            Season(id: id * 10 + 2, number: 2, premiereDate: nil, endDate: nil, episodeOrder: nil))
    case .scheduled(let premiere):
        seasons.append(
            Season(
                id: id * 10 + 2, number: 2, premiereDate: premiere, endDate: nil,
                episodeOrder: nil))
    case .ended:
        status = .ended
    }
    return Show(
        id: id, name: "Show \(id)", tvMazeURL: nil, summaryHTML: nil,
        posterMediumURL: nil, posterOriginalURL: nil, status: status,
        premiered: nil, ended: nil, network: nil, genres: [], averageRuntime: nil,
        seasons: seasons, nextEpisode: nil, updatedAt: updatedAt)
}

private func isolatedDefaults() -> UserDefaults {
    let suiteName = "SubscriptionDowngradeRefreshTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

/// Repository, StoreKit stub, purchases, refresh, and reconciler wired as in
/// `AppCompositionRoot` (catch-up marks before resume; catch-up of resumed IDs).
@MainActor
private struct Harness {
    let repository = InMemoryWatchlistRepository()
    let store: StubPurchaseStoreClient
    let purchases: PurchaseService
    let tvMaze = GatedTVMazeService()
    let notifications = RecordingNotifications()
    let refresh: WatchlistRefreshService
    let reconciler: WatchlistAccessReconciler

    /// - Parameters:
    ///   - runsCatchUp: When false, the post-resume catch-up does nothing, as if
    ///     it had not run yet or had been interrupted.
    init(
        showIDs: [Int], plus: Bool, initial: StoreEntitlementState? = nil,
        runsCatchUp: Bool = true
    ) async throws {
        store = StubPurchaseStoreClient(isStoreEntitled: plus)
        let purchases = PurchaseService(
            store: store,
            entitlementStore: PlusEntitlementStore(
                userDefaults: isolatedDefaults(),
                persistence: MemoryComplimentaryPlusPersistence()),
            initialStoreEntitlement: initial ?? .resolved(isEntitled: plus),
            simulationAvailability: { true }
        )
        self.purchases = purchases
        let refresh = WatchlistRefreshService(
            tvMaze: tvMaze, repository: repository, notifications: notifications,
            analytics: RecordingAnalyticsService(), userDefaults: isolatedDefaults())
        self.refresh = refresh
        reconciler = WatchlistAccessReconciler(
            repository: repository,
            userDefaults: isolatedDefaults(),
            access: { purchases.confirmedWatchlistAccess },
            waitForAccess: { await purchases.waitForInitialEntitlementResolution() },
            willResume: { refresh.markForCatchUp($0) },
            refreshAfterResume: { ids in
                guard runsCatchUp else { return }
                await refresh.catchUp(showIDs: ids)
            }
        )
        // Saved in ID order, so ID order is `dateAdded` order (1 is oldest).
        for id in showIDs {
            try await repository.add(show(id, .returning))
            tvMaze.showByID[id] = show(id, .returning)
        }
    }

    func setPlus(_ entitled: Bool) async -> WatchlistAccessReconciler.Outcome {
        store.isStoreEntitled = entitled
        await purchases.refreshEntitlements()
        return await reconciler.reconcile()
    }

    /// Restores Plus and waits for the post-resume catch-up to finish.
    func restorePlusAndCatchUp() async -> WatchlistAccessReconciler.Outcome {
        let outcome = await setPlus(true)
        await reconciler.catchUpTask?.value
        return outcome
    }

    /// Publishes new TVMaze data for `id` and marks it changed on the updates map,
    /// so an ordinary (non-forced) refresh is eligible to fetch it.
    func publish(_ id: Int, _ shape: Shape) {
        let updatedAt = (tvMaze.showByID[id]?.updatedAt ?? baseUpdatedAt) + 60
        tvMaze.showByID[id] = show(id, shape, updatedAt: updatedAt)
        tvMaze.updates[id] = updatedAt
    }

    func row(_ id: Int) async throws -> TrackedShow? {
        try await repository.trackedShow(showID: id)
    }
}

// MARK: - In-flight refresh, catch-up baseline, catch-up scope

@MainActor
struct SubscriptionDowngradeRefreshTests {
    // Issue 1

    @Test("A show paused while its fetch is in flight is not updated or notified")
    func downgradeDuringInFlightFetch() async throws {
        let harness = try await Harness(showIDs: [1, 2, 3, 4, 5], plus: true)
        for id in 1...5 { harness.publish(id, .scheduled(upcomingPremiere)) }
        let before = try #require(try await harness.row(5))
        // Refresh visits newest first, so show 5 is fetched first and held.
        harness.tvMaze.gateNextFetch(of: 5)

        let refreshTask = Task { await harness.refresh.refreshAll(force: true) }
        await harness.tvMaze.waitUntilGatedFetchStarts()
        #expect(await harness.setPlus(false) == .paused([4, 5]))
        harness.tvMaze.releaseGatedFetch()
        _ = await refreshTask.value

        let after = try #require(try await harness.row(5))
        #expect(after.isPaused)
        #expect(after.nextSeason == before.nextSeason, "Paused mid-fetch: result not applied")
        #expect(after.lastCheckedAt == before.lastCheckedAt)
        #expect(after.lastNotifiedSignature == nil)
        #expect(harness.tvMaze.fetchedShowIDs == [5, 3, 2, 1], "Show 4 paused before its turn")
        #expect(Set(harness.notifications.showIDs) == [1, 2, 3])
    }

    @Test("Foreground refresh applies a confirmed lapse before fetching")
    func foregroundRefreshUsesReconciledState() async throws {
        let harness = try await Harness(showIDs: [1, 2, 3, 4, 5], plus: true)
        for id in 1...5 { harness.publish(id, .scheduled(upcomingPremiere)) }
        harness.store.isStoreEntitled = false

        // Production passes entitlement refresh + reconcileWhenAccessKnown.
        await harness.refresh.refreshAllIfNeeded {
            await harness.purchases.refreshEntitlements()
            await harness.reconciler.reconcileWhenAccessKnown()
        }

        #expect(Set(harness.tvMaze.fetchedShowIDs) == [1, 2, 3])
        #expect(Set(harness.notifications.showIDs) == [1, 2, 3])
    }

    @Test("Foreground refresh with unverifiable access pauses nothing")
    func foregroundRefreshWithUnknownAccess() async throws {
        let harness = try await Harness(
            showIDs: [1, 2, 3, 4, 5], plus: false, initial: .loading)
        for id in 1...5 { harness.publish(id, .scheduled(upcomingPremiere)) }
        harness.store.reportsUnverifiedEntitlement = true

        await harness.refresh.refreshAllIfNeeded {
            await harness.purchases.refreshEntitlements()
            await harness.reconciler.reconcileWhenAccessKnown()
        }

        #expect(harness.purchases.storeEntitlement == .unverified)
        #expect(try await harness.repository.activeShowIDs() == [1, 2, 3, 4, 5])
        #expect(Set(harness.notifications.showIDs) == [1, 2, 3, 4, 5])
    }

    // Issue 2

    @Test("Silent catch-up baselines a historical soft change; later changes still notify")
    func catchUpBaselinesHistoricalSoftChange() async throws {
        let harness = try await Harness(showIDs: [1, 2, 3, 4], plus: false)
        #expect(await harness.reconciler.reconcile() == .paused([4]))
        // While paused, show 4's next season was announced (a soft change).
        harness.publish(4, .announced)

        #expect(await harness.restorePlusAndCatchUp() == .resumed([4]))
        #expect(harness.tvMaze.fetchedShowIDs == [4], "Catch-up fetches only resumed shows")
        let baseline = try #require(try await harness.row(4))
        #expect(baseline.nextSeason == .announcedUndated(season: 2))
        #expect(baseline.pendingChangeSignature == nil)
        #expect(harness.notifications.delivered.isEmpty)

        // Two ordinary eligible refreshes: the historical change must not confirm.
        harness.publish(4, .announced)
        await harness.refresh.refreshAll()
        harness.publish(4, .announced)
        await harness.refresh.refreshAll()
        #expect(harness.notifications.delivered.isEmpty)

        // A genuinely new soft change after catch-up debounces, then notifies once.
        harness.publish(4, .ended)
        await harness.refresh.refreshAll()
        #expect(harness.notifications.delivered.isEmpty, "Soft change waits for a 2nd poll")
        harness.publish(4, .ended)
        await harness.refresh.refreshAll()
        #expect(harness.notifications.showIDs == [4])
        #expect(harness.notifications.delivered.first?.status == .ended)
    }

    @Test("A failed catch-up is retried silently by the next ordinary refresh")
    func failedCatchUpStaysSilent() async throws {
        let harness = try await Harness(showIDs: [1, 2, 3, 4], plus: false)
        _ = await harness.reconciler.reconcile()
        harness.publish(4, .scheduled(upcomingPremiere))
        harness.tvMaze.failNextFetch = [4]

        #expect(await harness.restorePlusAndCatchUp() == .resumed([4]))
        #expect(try await harness.row(4)?.isPaused == false, "Reactivated despite failure")
        #expect(harness.refresh.catchUpShowIDs == [4], "Still awaiting its baseline")

        await harness.refresh.refreshAll()
        #expect(harness.notifications.delivered.isEmpty)
        #expect(harness.refresh.catchUpShowIDs.isEmpty)
        let row = try #require(try await harness.row(4))
        #expect(row.nextSeason != .returningNoSeasonYet, "Baseline holds the fetched status")
        #expect(row.lastNotifiedSignature == StatusChangeDetector.signature(for: row.nextSeason))
        #expect(row.pendingChangeSignature == nil)
    }

    // Issue 3

    @Test("Catch-up is limited to resumed shows; an active show's new premiere notifies")
    func catchUpLeavesContinuouslyActiveShowsAlone() async throws {
        let harness = try await Harness(showIDs: [1, 2, 3, 4], plus: false)
        _ = await harness.reconciler.reconcile()
        // During the free period: show 1 (active) and show 4 (paused) both got
        // premiere dates. Show 1's is news; show 4's is history.
        harness.publish(1, .scheduled(upcomingPremiere))
        harness.publish(4, .scheduled(laterPremiere))

        #expect(await harness.restorePlusAndCatchUp() == .resumed([4]))
        #expect(harness.tvMaze.fetchedShowIDs == [4])
        #expect(try await harness.row(1)?.nextSeason == .returningNoSeasonYet, "Untouched")
        #expect(harness.notifications.delivered.isEmpty)

        await harness.refresh.refreshAll()
        #expect(harness.notifications.showIDs == [1])
    }

    @Test("A notifying refresh that reaches a resumed show before catch-up stays silent")
    func notifyingRefreshBeforeCatchUp() async throws {
        let harness = try await Harness(showIDs: [1, 2, 3, 4], plus: false, runsCatchUp: false)
        _ = await harness.reconciler.reconcile()
        harness.publish(1, .scheduled(upcomingPremiere))
        harness.publish(4, .scheduled(laterPremiere))

        #expect(await harness.restorePlusAndCatchUp() == .resumed([4]))
        #expect(harness.tvMaze.fetchedShowIDs.isEmpty, "Catch-up has not run")

        await harness.refresh.refreshAll()
        #expect(harness.notifications.showIDs == [1])
        #expect(harness.refresh.catchUpShowIDs.isEmpty)
        let row = try #require(try await harness.row(4))
        #expect(row.lastNotifiedSignature == StatusChangeDetector.signature(for: row.nextSeason))

        // The late catch-up, and later refreshes, still announce nothing for show 4.
        await harness.refresh.catchUp(showIDs: [4])
        harness.publish(4, .scheduled(laterPremiere))
        await harness.refresh.refreshAll()
        #expect(harness.notifications.showIDs == [1])
    }

    @Test("A refresh suspended on a resumed show while catch-up completes stays silent")
    func overlappingRefreshAndCatchUp() async throws {
        let harness = try await Harness(showIDs: [1, 2, 3, 4], plus: false, runsCatchUp: false)
        _ = await harness.reconciler.reconcile()
        harness.publish(1, .scheduled(upcomingPremiere))
        harness.publish(4, .scheduled(laterPremiere))
        #expect(await harness.restorePlusAndCatchUp() == .resumed([4]))

        // Ordinary refresh visits show 4 first (newest) and is held mid-fetch.
        harness.tvMaze.gateNextFetch(of: 4)
        let ordinary = Task { await harness.refresh.refreshAll() }
        await harness.tvMaze.waitUntilGatedFetchStarts()

        // Catch-up completes meanwhile and clears show 4's mark.
        await harness.refresh.catchUp(showIDs: [4])
        #expect(harness.refresh.catchUpShowIDs.isEmpty)

        harness.tvMaze.releaseGatedFetch()
        _ = await ordinary.value
        #expect(harness.notifications.showIDs == [1], "Show 4's history is not announced")
    }

    @Test("A delayed catch-up still announces a new update found after its mark was consumed")
    func delayedCatchUpAnnouncesNewUpdate() async throws {
        let harness = try await Harness(showIDs: [1, 2, 3, 4], plus: false, runsCatchUp: false)
        _ = await harness.reconciler.reconcile()
        harness.publish(4, .scheduled(upcomingPremiere))  // History while paused.
        #expect(await harness.restorePlusAndCatchUp() == .resumed([4]))

        // Catch-up's request is held; it reaches TVMaze only on release.
        harness.tvMaze.gateNextFetch(of: 4)
        let catchUp = Task { await harness.refresh.catchUp(showIDs: [4]) }
        await harness.tvMaze.waitUntilGatedFetchStarts()

        // An ordinary refresh baselines the history and consumes the mark.
        await harness.refresh.refreshAll()
        #expect(harness.refresh.catchUpShowIDs.isEmpty)
        #expect(harness.notifications.delivered.isEmpty)

        // A genuinely new premiere appears before the delayed catch-up's response.
        harness.publish(4, .scheduled(laterPremiere))
        harness.tvMaze.releaseGatedFetch()
        await catchUp.value

        #expect(harness.notifications.showIDs == [4], "New update is announced")
        let newer = try #require(harness.tvMaze.showByID[4])
        #expect(
            harness.notifications.delivered.first?.status == NextSeasonCalculator.status(for: newer)
        )
        await harness.refresh.refreshAll()
        #expect(harness.notifications.showIDs == [4], "Announced once")
    }

    @Test("An older response arriving late cannot overwrite a newer baseline")
    func staleResponseIsRejected() async throws {
        let harness = try await Harness(showIDs: [1, 2, 3, 4], plus: false, runsCatchUp: false)
        _ = await harness.reconciler.reconcile()
        #expect(await harness.restorePlusAndCatchUp() == .resumed([4]))

        // Response A (older premiere) is received by an ordinary refresh but held.
        harness.publish(4, .scheduled(upcomingPremiere))
        harness.tvMaze.gateNextFetch(of: 4, respondAtRequestTime: true)
        let ordinary = Task { await harness.refresh.refreshAll() }
        await harness.tvMaze.waitUntilGatedFetchStarts()

        // Response B (newer version, later premiere) is applied by catch-up.
        harness.publish(4, .scheduled(laterPremiere))
        await harness.refresh.catchUp(showIDs: [4])
        let baseline = try #require(try await harness.row(4))

        harness.tvMaze.releaseGatedFetch()
        _ = await ordinary.value

        let after = try #require(try await harness.row(4))
        #expect(after.nextSeason == baseline.nextSeason, "A did not overwrite B")
        #expect(after.sourceUpdatedAt == baseline.sourceUpdatedAt)
        #expect(after.lastNotifiedSignature == baseline.lastNotifiedSignature)
        #expect(harness.notifications.delivered.isEmpty, "No historical announcement")
    }

    // Catch-up marks follow the saved row's lifecycle.

    @Test("Deleting and re-adding a show drops its catch-up mark")
    func reAddedShowIsNotSilenced() async throws {
        let harness = try await Harness(showIDs: [1, 2, 3, 4], plus: false)
        _ = await harness.reconciler.reconcile()
        harness.publish(4, .scheduled(upcomingPremiere))
        harness.tvMaze.failNextFetch = [4]  // Catch-up fails; the mark remains.
        #expect(await harness.restorePlusAndCatchUp() == .resumed([4]))
        #expect(harness.refresh.catchUpShowIDs == [4])

        try await harness.repository.remove(showID: 4)
        try await harness.repository.add(show(4, .returning))
        harness.publish(4, .scheduled(laterPremiere))  // The new row's real update.

        await harness.refresh.refreshAll()
        #expect(harness.notifications.showIDs == [4], "New row's update is announced")
        #expect(harness.refresh.catchUpShowIDs.isEmpty)
    }

    @Test("Undoing a delete keeps the restored show's catch-up mark")
    func undoKeepsCatchUpMark() async throws {
        let harness = try await Harness(showIDs: [1, 2, 3, 4], plus: false)
        _ = await harness.reconciler.reconcile()
        harness.publish(4, .scheduled(upcomingPremiere))
        harness.tvMaze.failNextFetch = [4]
        #expect(await harness.restorePlusAndCatchUp() == .resumed([4]))

        let removal = WatchlistPendingRemoval(
            repository: harness.repository, analytics: RecordingAnalyticsService())
        let row = try #require(try await harness.row(4))
        await withCheckedContinuation { (committed: CheckedContinuation<Void, Never>) in
            removal.addOutcomeHandler { outcome in
                if case .committed(let id) = outcome, id == 4 { committed.resume() }
            }
            removal.requestImmediateRemoval(row, anchor: .zero, source: .watchlist)
        }
        _ = await removal.undoRemoval()
        #expect(try await harness.row(4)?.dateAdded == row.dateAdded)

        await harness.refresh.refreshAll()
        #expect(harness.notifications.delivered.isEmpty, "Restored row is still baselined")
        #expect(harness.refresh.catchUpShowIDs.isEmpty)
    }

    @Test("A refresh inside the undo window keeps the deleted show's catch-up mark")
    func refreshDuringUndoWindowKeepsMark() async throws {
        let harness = try await Harness(showIDs: [1, 2, 3, 4], plus: false)
        _ = await harness.reconciler.reconcile()
        harness.publish(4, .scheduled(upcomingPremiere))  // History while paused.
        harness.tvMaze.failNextFetch = [4]  // 1. Catch-up fails; show 4 stays marked.
        #expect(await harness.restorePlusAndCatchUp() == .resumed([4]))

        // 2. Swipe-delete (persisted immediately, undoable).
        let removal = WatchlistPendingRemoval(
            repository: harness.repository, analytics: RecordingAnalyticsService())
        let row = try #require(try await harness.row(4))
        await withCheckedContinuation { (committed: CheckedContinuation<Void, Never>) in
            removal.addOutcomeHandler { outcome in
                if case .committed(let id) = outcome, id == 4 { committed.resume() }
            }
            removal.requestImmediateRemoval(row, anchor: .zero, source: .watchlist)
        }

        // 3. An automatic refresh runs while the row is deleted.
        await harness.refresh.refreshAll()
        #expect(harness.refresh.catchUpShowIDs == [4], "Absent row's mark is kept")

        // 4. Undo restores the original row; 5. the next refresh stays silent.
        _ = await removal.undoRemoval()
        await harness.refresh.refreshAll()
        #expect(harness.notifications.delivered.isEmpty, "No historical announcement")
        #expect(harness.refresh.catchUpShowIDs.isEmpty, "Mark consumed by the baseline")
    }
}

// MARK: - Search / Detail star state while mounted (issue 4)

/// A mounted Search or Detail screen keeps its tracking model alive; the views
/// re-run these refreshes on `WatchlistAccessReconciler.changeGeneration`.
@MainActor
struct SubscriptionDowngradeStarStateTests {
    private func notificationService() -> NotificationService {
        NotificationService(
            userDefaults: isolatedDefaults(),
            authorizationStatusForTesting: .denied,
            analytics: RecordingAnalyticsService())
    }

    @Test("Detail star empties when its show is paused and fills when resumed")
    func detailStarFollowsPauseAndResume() async throws {
        let harness = try await Harness(showIDs: [1, 2, 3, 4], plus: true)
        let removal = WatchlistPendingRemoval(
            repository: harness.repository, analytics: RecordingAnalyticsService())
        let viewModel = ShowDetailViewModel(
            show: show(4, .returning), service: harness.tvMaze,
            repository: harness.repository, notifications: notificationService(),
            analytics: RecordingAnalyticsService(), purchases: harness.purchases,
            initialIsTracked: true)
        await viewModel.load(removalCoordinator: removal)
        #expect(viewModel.isTracked)

        #expect(await harness.setPlus(false) == .paused([4]))
        await viewModel.refreshTrackedState(removalCoordinator: removal)
        #expect(viewModel.isTracked == false, "Paused: empty star")

        var paywallShown = false
        await viewModel.handleTrackButton(
            anchor: .zero, removalCoordinator: removal, onWatchlistChanged: {},
            onPaywallRequired: { paywallShown = true })
        #expect(paywallShown, "Three active shows: star leads to the paywall")
        #expect(try await harness.row(4)?.isPaused == true)

        #expect(await harness.setPlus(true) == .resumed([4]))
        await viewModel.refreshTrackedState(removalCoordinator: removal)
        #expect(viewModel.isTracked, "Resumed: filled star")

        // The star now removes (undoable), and a later access change keeps the
        // pending removal excluded.
        await viewModel.handleTrackButton(
            anchor: .zero, removalCoordinator: removal, onWatchlistChanged: {},
            onPaywallRequired: {})
        #expect(removal.pendingRemoval?.id == 4)
        await viewModel.refreshTrackedState(removalCoordinator: removal)
        #expect(viewModel.isTracked == false)
        _ = await removal.undoRemoval()
        await viewModel.refreshTrackedState(removalCoordinator: removal)
        #expect(viewModel.isTracked)
    }

    @Test("Paused show in Detail reactivates into a free slot")
    func detailStarReactivatesIntoFreeSlot() async throws {
        let harness = try await Harness(showIDs: [1, 2, 3, 4], plus: false)
        _ = await harness.reconciler.reconcile()
        try await harness.repository.remove(showID: 1)
        let viewModel = ShowDetailViewModel(
            show: show(4, .returning), service: harness.tvMaze,
            repository: harness.repository, notifications: notificationService(),
            analytics: RecordingAnalyticsService(), purchases: harness.purchases)
        await viewModel.load(removalCoordinator: nil)
        #expect(viewModel.isTracked == false)

        await viewModel.handleTrackButton(
            anchor: .zero, removalCoordinator: nil, onWatchlistChanged: {},
            onPaywallRequired: {})
        #expect(viewModel.isTracked)
        #expect(try await harness.row(4)?.isPaused == false)
        #expect(try await harness.repository.all().count == 3, "Reactivated, not duplicated")
    }

    @Test("Search stars follow pause and resume; pending removals stay excluded")
    func searchStarsFollowPauseAndResume() async throws {
        let harness = try await Harness(showIDs: [1, 2, 3, 4], plus: true)
        let removal = WatchlistPendingRemoval(
            repository: harness.repository, analytics: RecordingAnalyticsService())
        let tracking = SearchWatchlistTracking()
        var paywallShown = false
        let context = SearchWatchlistTracking.Context(
            repository: harness.repository, tvMaze: harness.tvMaze,
            removalCoordinator: removal, notificationService: notificationService(),
            notificationPrompt: WatchlistNotificationPromptState(),
            analytics: RecordingAnalyticsService(), purchases: harness.purchases,
            onWatchlistChanged: {}, onSearchResultsHintDismissed: {},
            onPaywallRequired: { paywallShown = true })
        func refreshStars() async {
            await tracking.refresh(
                repository: harness.repository, excludingPendingRemovalFrom: removal,
                analytics: RecordingAnalyticsService())
        }
        await refreshStars()
        #expect(tracking.trackedShowIDs == [1, 2, 3, 4])

        // Pending removal of show 1 survives the access-change refreshes below.
        let showOne = try #require(try await harness.row(1))
        removal.requestRemoval(showOne, anchor: .zero, source: .search)

        #expect(await harness.setPlus(false) == .paused([4]))
        await refreshStars()
        #expect(tracking.trackedShowIDs == [2, 3], "Paused 4 empty; pending 1 excluded")

        // An undoable removal is not persisted yet, so show 1 still holds a slot:
        // tapping paused 4's empty star leads to the paywall, not reactivation.
        await tracking.handleTrackButton(for: show(4, .returning), anchor: .zero, context: context)
        #expect(paywallShown)
        #expect(try await harness.row(4)?.isPaused == true)

        #expect(await harness.setPlus(true) == .resumed([4]))
        await refreshStars()
        #expect(tracking.trackedShowIDs == [2, 3, 4], "Resumed 4 filled")
        _ = await removal.undoRemoval()
        await refreshStars()
        #expect(tracking.trackedShowIDs == [1, 2, 3, 4])
    }
}
