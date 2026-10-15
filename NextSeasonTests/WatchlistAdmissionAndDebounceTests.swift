//
//  WatchlistAdmissionAndDebounceTests.swift
//  NextSeasonTests
//

import CoreGraphics
import Foundation
import Testing
import UserNotifications

@testable import NextSeason

// MARK: - Fixtures

/// TVMaze stub that holds every detail fetch until `release(_:)`, and lets a test
/// wait until a given number of fetches have started. Main-actor isolated, so its
/// state needs no locking; witnesses are explicitly main-actor because the
/// protocol is `nonisolated` (an async requirement can have an isolated witness).
@MainActor
private final class HoldingTVMazeService: TVMazeService {
    var showByID: [Int: Show] = [:]
    var updates: [Int: Date] = [:]
    /// When false, fetches return immediately (refresh tests).
    var holdsFetches = true
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
        if holdsFetches {
            await withCheckedContinuation { held[id] = $0 }
        }
        guard let show = showByID[id] else { throw URLError(.notConnectedToInternet) }
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
    func deliver(_ content: SeasonNotificationContent) async -> NotificationDeliveryOutcome {
        delivered.append(content)
        return .accepted
    }
}

private let baseUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)

/// Full show with season 1 aired and ended: `.returningNoSeasonYet` by default,
/// `.announcedUndated` with an undated season 2, `.ended` with `status: .ended`.
private func show(
    _ id: Int, updatedAt: Date = baseUpdatedAt, status: ShowStatus = .running,
    undatedSeasonTwo: Bool = false
) -> Show {
    var seasons = [
        Season(
            id: id * 10 + 1, number: 1, premiereDate: TVMazeDate.dateOnly("2022-02-18"),
            endDate: TVMazeDate.dateOnly("2022-04-08"), episodeOrder: 9)
    ]
    if undatedSeasonTwo {
        seasons.append(
            Season(id: id * 10 + 2, number: 2, premiereDate: nil, endDate: nil, episodeOrder: nil))
    }
    return Show(
        id: id, name: "Show \(id)", tvMazeURL: nil, summaryHTML: nil,
        posterMediumURL: nil, posterOriginalURL: nil, status: status,
        premiered: nil, ended: nil, network: nil, genres: [], averageRuntime: nil,
        seasons: seasons, nextEpisode: nil, updatedAt: updatedAt)
}

/// A search hit: no seasons, so `WatchlistTracking.add` must fetch full details.
private func searchHit(_ id: Int) -> Show {
    Show(
        id: id, name: "Show \(id)", tvMazeURL: nil, summaryHTML: nil,
        posterMediumURL: nil, posterOriginalURL: nil, status: .running,
        premiered: nil, ended: nil, network: nil, genres: [], averageRuntime: nil,
        seasons: [], nextEpisode: nil, updatedAt: baseUpdatedAt)
}

private func isolatedDefaults() -> UserDefaults {
    let suiteName = "WatchlistAdmissionAndDebounceTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

// MARK: - Free-limit admission at persistence

@MainActor
struct WatchlistAdmissionTests {
    private func makePurchases(
        _ store: StubPurchaseStoreClient, initial: StoreEntitlementState
    ) -> PurchaseService {
        PurchaseService(
            store: store,
            entitlementStore: PlusEntitlementStore(
                userDefaults: isolatedDefaults(),
                persistence: MemoryComplimentaryPlusPersistence()),
            initialStoreEntitlement: initial,
            simulationAvailability: { false }
        )
    }

    private func add(
        _ show: Show, repository: InMemoryWatchlistRepository, tvMaze: HoldingTVMazeService,
        purchases: PurchaseService
    ) async throws -> WatchlistTracking.ToggleOutcome {
        let analytics = RecordingAnalyticsService()
        return try await WatchlistTracking.add(
            show, source: .search, repository: repository, tvMaze: tvMaze,
            analytics: analytics,
            notifications: NotificationService(
                userDefaults: isolatedDefaults(), authorizationStatusForTesting: .denied,
                analytics: analytics),
            prompt: WatchlistNotificationPromptState(), purchases: purchases)
    }

    /// What this guarantees: both adds read a count of two and are suspended in
    /// their detail fetches before either saves — the stale-count condition the
    /// final admission check closes, whichever suspension made the count stale.
    ///
    /// What it does not guarantee: that both adds waited on entitlement
    /// resolution. StoreKit is released right after the tasks are scheduled, so
    /// an add may start after it resolves and skip that wait. Forcing the wait
    /// deterministically would need a waiter signal in `PurchaseService`.
    @Test("Two adds holding stale counts across their detail fetches cannot exceed the free limit")
    func concurrentAddsRespectLimit() async throws {
        let repository = InMemoryWatchlistRepository()
        for id in [1, 2] { try await repository.add(show(id)) }
        let store = StubPurchaseStoreClient(isStoreEntitled: false)
        store.delayEntitlementResolution = true
        let purchases = makePurchases(store, initial: .loading)
        let tvMaze = HoldingTVMazeService()
        tvMaze.showByID = [10: show(10), 11: show(11)]

        // Launch: StoreKit read in flight. Each add may or may not reach the
        // entitlement wait before the release below; either way it reads two.
        let entitlementRead = Task { await purchases.refreshEntitlements() }
        let addA = Task {
            try await add(
                searchHit(10), repository: repository, tvMaze: tvMaze, purchases: purchases)
        }
        let addB = Task {
            try await add(
                searchHit(11), repository: repository, tvMaze: tvMaze, purchases: purchases)
        }
        store.releaseEntitlementResolution()  // Resolves as Free.
        await entitlementRead.value

        // Both passed the initial check and are suspended fetching details.
        await tvMaze.waitForStartedFetches(2)
        tvMaze.release(10)
        let outcomeA = try await addA.value
        tvMaze.release(11)
        let outcomeB = try await addB.value

        #expect(outcomeA == .added)
        #expect(outcomeB == .paywallRequired, "Third slot already taken at persistence")
        #expect(try await repository.activeShowIDs() == [1, 2, 10])
    }

    @Test("An Undo that restores a show during an add's fetch takes the free slot")
    func undoDuringFetchTakesSlot() async throws {
        let repository = InMemoryWatchlistRepository()
        for id in [1, 2, 3] { try await repository.add(show(id)) }
        let purchases = makePurchases(
            StubPurchaseStoreClient(isStoreEntitled: false), initial: .resolved(isEntitled: false))
        let tvMaze = HoldingTVMazeService()
        tvMaze.showByID = [10: show(10)]

        // Swipe-delete show 1 (persisted immediately; undoable).
        let removal = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        let row = try #require(try await repository.trackedShow(showID: 1))
        await withCheckedContinuation { (committed: CheckedContinuation<Void, Never>) in
            removal.addOutcomeHandler { outcome in
                if case .committed(let id) = outcome, id == 1 { committed.resume() }
            }
            removal.requestImmediateRemoval(row, anchor: .zero, source: .watchlist)
        }

        // An add sees two active shows and suspends fetching details.
        let addTask = Task {
            try await add(
                searchHit(10), repository: repository, tvMaze: tvMaze, purchases: purchases)
        }
        await tvMaze.waitForStartedFetches(1)

        _ = await removal.undoRemoval()  // Show 1 is back: three active.
        tvMaze.release(10)

        #expect(try await addTask.value == .paywallRequired)
        #expect(try await repository.activeShowIDs() == [1, 2, 3])
        #expect(try await repository.contains(showID: 10) == false)
    }
}

// MARK: - Soft-change confirmation on ordinary refreshes

@MainActor
struct SoftChangeConfirmationTests {
    enum SoftChange: String, CaseIterable, CustomTestStringConvertible {
        case undatedAnnouncement
        case seriesEnded
        var testDescription: String { rawValue }
    }

    @Test(
        "A soft change confirms on the next non-forced refresh with an unchanged timestamp",
        arguments: SoftChange.allCases)
    func softChangeConfirmsWithoutServerUpdate(_ change: SoftChange) async throws {
        let repository = InMemoryWatchlistRepository()
        try await repository.add(show(1))  // Stored as returningNoSeasonYet.
        let tvMaze = HoldingTVMazeService()
        tvMaze.holdsFetches = false
        let notifications = RecordingNotifications()
        let refresh = WatchlistRefreshService(
            tvMaze: tvMaze, repository: repository, notifications: notifications,
            analytics: RecordingAnalyticsService(), userDefaults: isolatedDefaults())

        // One TVMaze update; its timestamp then stays the same for every later poll.
        let changedAt = baseUpdatedAt + 60
        switch change {
        case .undatedAnnouncement:
            tvMaze.showByID[1] = show(1, updatedAt: changedAt, undatedSeasonTwo: true)
        case .seriesEnded:
            tvMaze.showByID[1] = show(1, updatedAt: changedAt, status: .ended)
        }
        tvMaze.updates = [1: changedAt]

        await refresh.refreshAll()
        let pending = try #require(try await repository.trackedShow(showID: 1))
        #expect(pending.pendingChangeSignature != nil)
        #expect(notifications.delivered.isEmpty, "First sighting waits for confirmation")

        await refresh.refreshAll()
        #expect(notifications.delivered.map(\.showID) == [1], "Second poll confirms")

        await refresh.refreshAll()
        #expect(notifications.delivered.count == 1, "Delivered once")
    }
}
