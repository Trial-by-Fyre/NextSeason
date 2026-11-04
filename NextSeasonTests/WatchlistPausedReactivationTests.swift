//
//  WatchlistPausedReactivationTests.swift
//  NextSeasonTests
//

import Foundation
import Testing
import UserNotifications

@testable import NextSeason

// MARK: - Fixtures

/// TVMaze stub with an optional hour-cache view and per-show held fetches.
///
/// `cachedShowByID` answers non-bypassing requests (the add path), so a test can
/// reactivate from stale cached data while refreshes (`bypassCache: true`) see
/// `showByID`. Main-actor isolated, so its state needs no locking.
@MainActor
private final class ReactivationTVMazeService: TVMazeService {
    var showByID: [Int: Show] = [:]
    var cachedShowByID: [Int: Show] = [:]
    var updates: [Int: Date] = [:]
    /// Shows whose next fetch throws (one failure each).
    var failNextFetch: Set<Int> = []
    /// Shows whose next fetch waits for `release(_:)`.
    var holdNextFetch: Set<Int> = []
    private(set) var fetchedShowIDs: [Int] = []
    private var held: [Int: CheckedContinuation<Void, Never>] = [:]
    private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func waitForStartedFetches(_ count: Int) async {
        if fetchedShowIDs.count >= count { return }
        await withCheckedContinuation { startWaiters.append((count, $0)) }
    }

    func release(_ showID: Int) {
        held.removeValue(forKey: showID)?.resume()
    }

    @MainActor func searchShows(matching query: String) async throws -> [Show] { [] }

    @MainActor func lookupShow(theTVDBID: Int) async throws -> Show {
        throw TVMazeError.notFound
    }

    @MainActor func show(id: Int, bypassCache: Bool) async throws -> Show {
        fetchedShowIDs.append(id)
        let ready = startWaiters.filter { $0.count <= fetchedShowIDs.count }
        startWaiters.removeAll { $0.count <= fetchedShowIDs.count }
        ready.forEach { $0.continuation.resume() }
        if holdNextFetch.remove(id) != nil {
            await withCheckedContinuation { held[id] = $0 }
        }
        if failNextFetch.remove(id) != nil { throw URLError(.notConnectedToInternet) }
        let response = bypassCache ? showByID[id] : (cachedShowByID[id] ?? showByID[id])
        guard let response else { throw URLError(.notConnectedToInternet) }
        return response
    }

    @MainActor func updatedShows(since period: TVMazeUpdatePeriod) async throws -> [Int: Date] {
        updates
    }

    @MainActor func allUpdatedShows() async throws -> [Int: Date] {
        updates
    }
}

@MainActor
private final class RecordingNotifications: NotificationDelivering {
    private(set) var delivered: [SeasonNotificationContent] = []
    func deliver(_ content: SeasonNotificationContent) async -> NotificationDeliveryOutcome {
        delivered.append(content)
        return .accepted
    }
    var showIDs: [Int] { delivered.map(\.showID) }
}

/// In-memory repository whose next `add` can throw, for persistence failures.
@MainActor
private final class FailingAddRepository: WatchlistRepository {
    let base = InMemoryWatchlistRepository()
    var failNextAdd = false

    func all() async throws -> [TrackedShow] { try await base.all() }
    func trackedShow(showID: Int) async throws -> TrackedShow? {
        try await base.trackedShow(showID: showID)
    }
    func trackedShowIDs() async throws -> Set<Int> { try await base.trackedShowIDs() }
    func contains(showID: Int) async throws -> Bool { try await base.contains(showID: showID) }
    func activeShowIDs() async throws -> Set<Int> { try await base.activeShowIDs() }
    func add(_ show: Show) async throws {
        if failNextAdd {
            failNextAdd = false
            throw CocoaError(.fileWriteUnknown)
        }
        try await base.add(show)
    }
    func remove(showID: Int) async throws { try await base.remove(showID: showID) }
    func updateAfterRefresh(_ tracked: TrackedShow) async throws {
        try await base.updateAfterRefresh(tracked)
    }
    func setPaused(_ isPaused: Bool, showIDs: Set<Int>) async throws {
        try await base.setPaused(isPaused, showIDs: showIDs)
    }
    func restoreRemoved(_ tracked: TrackedShow, isPaused: Bool) async throws {
        try await base.restoreRemoved(tracked, isPaused: isPaused)
    }
}

private enum Shape {
    case returning
    case scheduled(Date)
}

private let baseUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)
private let upcomingPremiere = Calendar.current.date(byAdding: .day, value: 30, to: .now)!
private let laterPremiere = Calendar.current.date(byAdding: .day, value: 60, to: .now)!

private func show(_ id: Int, _ shape: Shape = .returning, updatedAt: Date = baseUpdatedAt)
    -> Show
{
    var seasons = [
        Season(
            id: id * 10 + 1, number: 1, premiereDate: TVMazeDate.dateOnly("2022-02-18"),
            endDate: TVMazeDate.dateOnly("2022-04-08"), episodeOrder: 9)
    ]
    if case .scheduled(let premiere) = shape {
        seasons.append(
            Season(
                id: id * 10 + 2, number: 2, premiereDate: premiere, endDate: nil,
                episodeOrder: nil))
    }
    return Show(
        id: id, name: "Show \(id)", tvMazeURL: nil, summaryHTML: nil,
        posterMediumURL: nil, posterOriginalURL: nil, status: .running,
        premiered: nil, ended: nil, network: nil, genres: [], averageRuntime: nil,
        seasons: seasons, nextEpisode: nil, updatedAt: updatedAt)
}

private func isolatedDefaults() -> UserDefaults {
    let suiteName = "WatchlistPausedReactivationTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

/// Lapsed free user with shows 1…5 (1 oldest): 1–3 active, 4–5 paused. Wired
/// like `AppCompositionRoot` (reconciler marks before resume and catches up).
@MainActor
private struct Harness {
    let repository: any WatchlistRepository
    let store: StubPurchaseStoreClient
    let purchases: PurchaseService
    let tvMaze = ReactivationTVMazeService()
    let notifications = RecordingNotifications()
    let refresh: WatchlistRefreshService
    let reconciler: WatchlistAccessReconciler
    let removal: WatchlistPendingRemoval
    let viewModel: WatchlistViewModel
    let analytics = RecordingAnalyticsService()

    init(
        repository: any WatchlistRepository = InMemoryWatchlistRepository(),
        initial: StoreEntitlementState? = nil
    ) async throws {
        self.repository = repository
        store = StubPurchaseStoreClient(isStoreEntitled: false)
        let purchases = PurchaseService(
            store: store,
            entitlementStore: PlusEntitlementStore(
                userDefaults: isolatedDefaults(),
                persistence: MemoryComplimentaryPlusPersistence()),
            initialStoreEntitlement: initial ?? .resolved(isEntitled: false),
            simulationAvailability: { true }
        )
        self.purchases = purchases
        let refresh = WatchlistRefreshService(
            tvMaze: tvMaze, repository: repository, notifications: notifications,
            analytics: analytics, userDefaults: isolatedDefaults())
        self.refresh = refresh
        let removal = WatchlistPendingRemoval(
            repository: repository, analytics: analytics, purchases: purchases)
        self.removal = removal
        reconciler = WatchlistAccessReconciler(
            repository: repository,
            userDefaults: isolatedDefaults(),
            access: { purchases.confirmedWatchlistAccess },
            waitForAccess: { await purchases.waitForInitialEntitlementResolution() },
            excludedShowIDs: { removal.deferredRemovalShowID.map { [$0] } ?? [] },
            willResume: { refresh.markForCatchUp($0) },
            refreshAfterResume: { ids in await refresh.catchUp(showIDs: ids) }
        )
        viewModel = WatchlistViewModel(
            repository: repository, refreshService: refresh, removalCoordinator: removal,
            analytics: analytics, accessReconciler: reconciler)
        // Saved in ID order, so ID order is `dateAdded` order.
        for id in 1...5 {
            try await repository.add(show(id))
            tvMaze.showByID[id] = show(id)
        }
        try await repository.setPaused(true, showIDs: [4, 5])
    }

    func row(_ id: Int) async throws -> TrackedShow? {
        try await repository.trackedShow(showID: id)
    }

    func pausedIDs() async throws -> Set<Int> {
        Set(try await repository.all().filter(\.isPaused).map(\.id))
    }

    /// Frees a slot by deleting show 2 directly (as a committed removal).
    func freeOneSlot() async throws {
        try await repository.remove(showID: 2)
        await viewModel.reload()
    }

    /// The row's tap action, recording whether the paywall was requested.
    func tap(_ id: Int, paywall: inout Bool) async throws -> Bool {
        let tracked = try #require(try await row(id))
        var requested = false
        let result = await viewModel.reactivate(
            tracked, tvMaze: tvMaze,
            notifications: NotificationService(
                userDefaults: isolatedDefaults(), authorizationStatusForTesting: .denied,
                analytics: analytics),
            purchases: purchases,
            onPaywallRequired: { requested = true })
        paywall = requested
        return result
    }

    func tap(_ id: Int) async throws -> Bool {
        var paywall = false
        return try await tap(id, paywall: &paywall)
    }

    /// Publishes new TVMaze data and marks it changed on the updates map.
    func publish(_ id: Int, _ shape: Shape) {
        let updatedAt = (tvMaze.showByID[id]?.updatedAt ?? baseUpdatedAt) + 60
        tvMaze.showByID[id] = show(id, shape, updatedAt: updatedAt)
        tvMaze.updates[id] = updatedAt
    }

    func waitForImmediateRemoval(of id: Int) async throws {
        var attempts = 0
        while try await repository.contains(showID: id), attempts < 50 {
            attempts += 1
            await Task.yield()
        }
        #expect(try await repository.contains(showID: id) == false)
    }
}

// MARK: - Tests

@MainActor
struct WatchlistPausedReactivationTests {
    @Test("Tapping a paused show with an open slot reactivates exactly that show")
    func reactivatesTappedShow() async throws {
        let harness = try await Harness()
        try await harness.freeOneSlot()
        let original = try #require(try await harness.row(4))

        var paywall = false
        #expect(try await harness.tap(4, paywall: &paywall))
        #expect(paywall == false)

        let reactivated = try #require(try await harness.row(4))
        #expect(reactivated.isPaused == false)
        #expect(reactivated.dateAdded == original.dateAdded, "Same saved row")
        #expect(try await harness.repository.all().count == 4, "No duplicate")
        #expect(try await harness.repository.activeShowIDs() == [1, 3, 4])
        #expect(try await harness.pausedIDs() == [5], "Other paused shows stay paused")
        #expect(harness.viewModel.filteredPausedShows.map(\.id) == [5])
        #expect(harness.viewModel.filteredSectionGroups.flatMap(\.shows).contains { $0.id == 4 })
        #expect(harness.viewModel.isReactivating(original) == false)
    }

    @Test("At capacity, the tap requests the paywall and leaves the show paused")
    func atCapacityRequestsPaywall() async throws {
        let harness = try await Harness()
        await harness.viewModel.reload()

        var paywall = false
        #expect(try await harness.tap(4, paywall: &paywall) == false)
        #expect(paywall)
        #expect(try await harness.pausedIDs() == [4, 5])
        #expect(harness.tvMaze.fetchedShowIDs.isEmpty, "Blocked before the detail fetch")
        #expect(harness.refresh.catchUpShowIDs.isEmpty)
        #expect(harness.viewModel.reactivationFailure == nil)
    }

    @Test("Deleting an active show from the Watchlist does not promote a paused show")
    func deletionDoesNotPromote() async throws {
        let harness = try await Harness()
        await harness.viewModel.reload()
        let showTwo = try #require(try await harness.row(2))

        harness.viewModel.deleteImmediately(showTwo)
        try await harness.waitForImmediateRemoval(of: 2)
        await harness.viewModel.reload()

        #expect(try await harness.repository.activeShowIDs() == [1, 3])
        #expect(try await harness.pausedIDs() == [4, 5])
    }

    @Test("A repeated tap while reactivation is in flight is ignored")
    func repeatedTapIgnored() async throws {
        let harness = try await Harness()
        try await harness.freeOneSlot()
        harness.tvMaze.holdNextFetch = [4]

        let first = Task { try await harness.tap(4) }
        await harness.tvMaze.waitForStartedFetches(1)
        #expect(try await harness.tap(4) == false, "Second tap ignored")
        #expect(harness.tvMaze.fetchedShowIDs == [4], "No second detail fetch")
        let showFour = try #require(try await harness.row(4))
        #expect(harness.viewModel.isReactivating(showFour))
        harness.tvMaze.release(4)

        #expect(try await first.value)
        await harness.viewModel.catchUpTask?.value
        #expect(harness.tvMaze.fetchedShowIDs == [4, 4], "One add fetch, one catch-up fetch")
        #expect(try await harness.repository.activeShowIDs() == [1, 3, 4])
    }

    @Test("Two reactivations competing for one slot cannot exceed the free limit")
    func competingReactivationsRespectLimit() async throws {
        let harness = try await Harness()
        try await harness.freeOneSlot()
        harness.tvMaze.holdNextFetch = [4, 5]

        var paywallFive = false
        let tapFour = Task { try await harness.tap(4) }
        let tapFive = Task { () -> (Bool, Bool) in
            var paywall = false
            let result = try await harness.tap(5, paywall: &paywall)
            return (result, paywall)
        }
        await harness.tvMaze.waitForStartedFetches(2)
        harness.tvMaze.release(4)
        #expect(try await tapFour.value)
        harness.tvMaze.release(5)
        let (reactivatedFive, paywall) = try await tapFive.value
        paywallFive = paywall

        #expect(reactivatedFive == false)
        #expect(paywallFive, "Slot taken at persistence: paywall")
        #expect(try await harness.repository.activeShowIDs() == [1, 3, 4])
        #expect(try await harness.pausedIDs() == [5])
        #expect(harness.refresh.catchUpShowIDs.contains(5) == false, "Loser is never marked")
    }

    @Test("An add from Search that fills the slot during the fetch wins")
    func competingAddTakesSlot() async throws {
        let harness = try await Harness()
        try await harness.freeOneSlot()
        harness.tvMaze.holdNextFetch = [4]

        let tap = Task { () -> (Bool, Bool) in
            var paywall = false
            let result = try await harness.tap(4, paywall: &paywall)
            return (result, paywall)
        }
        await harness.tvMaze.waitForStartedFetches(1)
        try await harness.repository.add(show(10))
        harness.tvMaze.release(4)

        let (reactivated, paywall) = try await tap.value
        #expect(reactivated == false)
        #expect(paywall)
        #expect(try await harness.repository.activeShowIDs() == [1, 3, 10])
        #expect(try await harness.pausedIDs() == [4, 5])
        #expect(harness.refresh.catchUpShowIDs.isEmpty)
    }

    @Test("A pending star removal still holds its slot")
    func deferredRemovalHoldsSlot() async throws {
        let harness = try await Harness()
        await harness.viewModel.reload()
        harness.removal.undoWindowSecondsOverride = 60
        let showOne = try #require(try await harness.row(1))
        harness.viewModel.requestRemoval(showOne)
        #expect(harness.removal.deferredRemovalShowID == 1)

        var paywall = false
        #expect(try await harness.tap(4, paywall: &paywall) == false)
        #expect(paywall)
        #expect(try await harness.pausedIDs() == [4, 5])
        _ = await harness.removal.undoRemoval()
    }

    @Test("Undo after the freed slot was filled restores the deleted show paused")
    func undoAfterSlotFilledRestoresPaused() async throws {
        let harness = try await Harness()
        await harness.viewModel.reload()
        let showTwo = try #require(try await harness.row(2))
        harness.viewModel.deleteImmediately(showTwo)
        try await harness.waitForImmediateRemoval(of: 2)

        #expect(try await harness.tap(4))
        _ = await harness.removal.undoRemoval()

        #expect(try await harness.row(2)?.isPaused == true)
        #expect(try await harness.repository.activeShowIDs() == [1, 3, 4])
    }

    @Test("A row is not removable while its reactivation is in flight")
    func removalBlockedDuringReactivation() async throws {
        let harness = try await Harness()
        try await harness.freeOneSlot()
        harness.tvMaze.holdNextFetch = [4]
        let showFour = try #require(try await harness.row(4))

        let tap = Task { try await harness.tap(4) }
        await harness.tvMaze.waitForStartedFetches(1)
        harness.viewModel.deleteImmediately(showFour)
        harness.viewModel.requestRemoval(showFour)
        #expect(harness.removal.pendingRemoval == nil)
        #expect(harness.viewModel.shows.contains { $0.id == 4 })
        harness.tvMaze.release(4)

        #expect(try await tap.value)
        #expect(try await harness.row(4)?.isPaused == false)
    }

    @Test("A show deleted elsewhere during the fetch is not re-created")
    func deletedDuringFetchNotRecreated() async throws {
        let harness = try await Harness()
        try await harness.freeOneSlot()
        harness.tvMaze.holdNextFetch = [4]

        let tap = Task { try await harness.tap(4) }
        await harness.tvMaze.waitForStartedFetches(1)
        try await harness.repository.remove(showID: 4)  // e.g. un-starred in Search
        harness.tvMaze.release(4)

        #expect(try await tap.value == false)
        #expect(try await harness.repository.contains(showID: 4) == false)
        #expect(harness.refresh.catchUpShowIDs.isEmpty)
    }

    @Test("A show resumed elsewhere during the fetch gets no unmarked catch-up")
    func resumedElsewhereSkipsCatchUp() async throws {
        let harness = try await Harness()
        try await harness.freeOneSlot()
        harness.tvMaze.holdNextFetch = [4]

        let tap = Task { try await harness.tap(4) }
        await harness.tvMaze.waitForStartedFetches(1)
        try await harness.repository.add(show(4))  // Search reactivation finished first
        harness.tvMaze.release(4)

        #expect(try await tap.value == false)
        #expect(harness.viewModel.catchUpTask == nil)
        #expect(harness.refresh.catchUpShowIDs.isEmpty)
        #expect(try await harness.repository.activeShowIDs() == [1, 3, 4])
    }

    @Test("A network failure keeps the show paused and can be retried")
    func networkFailureRetry() async throws {
        let harness = try await Harness()
        try await harness.freeOneSlot()
        harness.tvMaze.failNextFetch = [4]

        #expect(try await harness.tap(4) == false)
        #expect(harness.viewModel.reactivationFailure?.id == 4)
        #expect(try await harness.pausedIDs() == [4, 5])
        #expect(harness.refresh.catchUpShowIDs.isEmpty, "Not marked before the write")

        #expect(try await harness.tap(4), "Retry succeeds")
        #expect(harness.viewModel.reactivationFailure == nil)
        #expect(try await harness.repository.activeShowIDs() == [1, 3, 4])
    }

    @Test("A persistence failure keeps the show paused, without a duplicate, and can be retried")
    func persistenceFailureRetry() async throws {
        let repository = FailingAddRepository()
        let harness = try await Harness(repository: repository)
        try await harness.freeOneSlot()
        repository.failNextAdd = true

        #expect(try await harness.tap(4) == false)
        #expect(harness.viewModel.reactivationFailure?.id == 4)
        #expect(try await harness.pausedIDs() == [4, 5])
        #expect(try await harness.repository.all().count == 4)

        #expect(try await harness.tap(4))
        #expect(try await harness.repository.all().count == 4)
        #expect(try await harness.repository.activeShowIDs() == [1, 3, 4])
    }

    @Test("Reactivation waits for the first entitlement read before deciding")
    func waitsForUnknownEntitlement() async throws {
        let harness = try await Harness(initial: .loading)
        try await harness.freeOneSlot()
        harness.store.delayEntitlementResolution = true

        let read = Task { await harness.purchases.refreshEntitlements() }
        for _ in 0..<200 where harness.store.entitlementWaiterCount == 0 { await Task.yield() }
        #expect(harness.store.entitlementWaiterCount > 0, "StoreKit read is held")

        var finished = false
        let tap = Task { () -> Bool in
            let result = try await harness.tap(4)
            finished = true
            return result
        }
        for _ in 0..<50 { await Task.yield() }
        #expect(finished == false, "Waits while entitlement is unknown")
        #expect(harness.tvMaze.fetchedShowIDs.isEmpty)
        #expect(try await harness.pausedIDs() == [4, 5])

        harness.store.releaseEntitlementResolution()  // Resolves as Free.
        await read.value

        #expect(try await tap.value)
        #expect(try await harness.repository.activeShowIDs() == [1, 3, 4])
    }

    @Test("Catch-up baselines a change from the paused period; later and active changes notify")
    func catchUpProtectsNotifications() async throws {
        let harness = try await Harness()
        try await harness.freeOneSlot()
        // While 4 was paused its season 2 was scheduled; the add reads an older
        // cached body that predates it.
        harness.tvMaze.cachedShowByID[4] = show(4)
        harness.publish(4, .scheduled(upcomingPremiere))
        // A continuously active show also changes in the same period.
        harness.publish(1, .scheduled(upcomingPremiere))

        #expect(try await harness.tap(4))
        await harness.viewModel.catchUpTask?.value
        #expect(harness.notifications.delivered.isEmpty, "Catch-up is silent")
        #expect(harness.refresh.catchUpShowIDs.isEmpty, "Mark consumed")
        #expect(
            try await harness.row(4)?.nextSeason
                == .scheduled(season: 2, premiere: upcomingPremiere))

        // An ordinary refresh: active show 1's change still notifies; 4's
        // historical change does not.
        await harness.refresh.refreshAll()
        #expect(harness.notifications.showIDs == [1])

        // A genuinely new change for 4 after catch-up notifies.
        harness.publish(4, .scheduled(laterPremiere))
        await harness.refresh.refreshAll()
        #expect(harness.notifications.showIDs == [1, 4])
    }

    @Test("Restoring Plus after a reactivation still resumes the remaining paused shows")
    func plusRestoreResumesRemaining() async throws {
        let harness = try await Harness()
        try await harness.freeOneSlot()
        #expect(try await harness.tap(4))
        // Its trailing reload also reconciles; finish it before access changes.
        await harness.viewModel.catchUpTask?.value

        harness.store.isStoreEntitled = true
        await harness.purchases.refreshEntitlements()
        // Fail 5's catch-up so its mark must still be present afterwards.
        harness.tvMaze.failNextFetch = [5]
        #expect(await harness.reconciler.reconcile() == .resumed([5]))
        await harness.reconciler.catchUpTask?.value
        #expect(try await harness.pausedIDs().isEmpty)
        #expect(harness.refresh.catchUpShowIDs == [5], "Resumed show marked for catch-up")
    }

    @Test("A paywall retry after Plus resumed the show is a no-op without a fetch")
    func retryAfterResumeIsNoOp() async throws {
        let harness = try await Harness()
        await harness.viewModel.reload()
        let stalePausedRow = try #require(try await harness.row(4))
        harness.store.isStoreEntitled = true
        await harness.purchases.refreshEntitlements()
        #expect(await harness.reconciler.reconcile() == .resumed([4, 5]))
        await harness.reconciler.catchUpTask?.value
        let fetchesBefore = harness.tvMaze.fetchedShowIDs.count

        let result = await harness.viewModel.reactivate(
            stalePausedRow, tvMaze: harness.tvMaze,
            notifications: NotificationService(
                userDefaults: isolatedDefaults(), authorizationStatusForTesting: .denied,
                analytics: harness.analytics),
            purchases: harness.purchases, onPaywallRequired: {})
        #expect(result == false)
        #expect(harness.tvMaze.fetchedShowIDs.count == fetchesBefore)
        #expect(harness.viewModel.catchUpTask == nil)
    }
}
