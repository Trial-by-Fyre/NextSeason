//
//  FreeTierReconciliationTests.swift
//  NextSeasonTests
//

import Foundation
import SwiftData
import Testing

@testable import NextSeason

/// Free-tier pause counts with the production SwiftData repository, for real
/// lapses and Simulate Free Tier, and with a deferred removal still in its undo
/// window (the manual-test report: six shows → two active, four paused).
@MainActor
struct FreeTierReconciliationTests {
    enum Downgrade: CaseIterable {
        case realLapse
        case simulation
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "FreeTierReconciliationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeRepository() throws -> SwiftDataWatchlistRepository {
        let container = try NextSeasonModelContainer.make(
            configuration: ModelConfiguration(
                "free-tier-\(UUID().uuidString)", isStoredInMemoryOnly: true))
        return SwiftDataWatchlistRepository(
            context: ModelContext(container),
            rowMarks: WatchlistRowMarks(userDefaults: isolatedDefaults()))
    }

    private func show(_ id: Int) -> Show {
        Show(
            id: id, name: "Show \(id)", tvMazeURL: nil, summaryHTML: nil,
            posterMediumURL: nil, posterOriginalURL: nil, status: .running,
            premiered: nil, ended: nil, network: nil, genres: [], averageRuntime: nil,
            seasons: [], nextEpisode: nil, updatedAt: .now)
    }

    /// Saves shows with increasing `dateAdded`, so show 1 is the oldest.
    private func seed(_ ids: ClosedRange<Int>, into repository: SwiftDataWatchlistRepository)
        async throws
    {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        for id in ids {
            try await repository.restoreRemoved(
                TrackedShow(from: show(id), at: start.addingTimeInterval(Double(id) * 60)),
                isPaused: false)
        }
    }

    private func makePurchases(store: StubPurchaseStoreClient) -> PurchaseService {
        PurchaseService(
            store: store,
            entitlementStore: PlusEntitlementStore(
                userDefaults: isolatedDefaults(),
                persistence: MemoryComplimentaryPlusPersistence()),
            initialStoreEntitlement: .resolved(isEntitled: store.isStoreEntitled),
            simulationAvailability: { true }
        )
    }

    /// Same wiring as `AppCompositionRoot`, including the pending-removal exclusion.
    private func makeReconciler(
        repository: any WatchlistRepository,
        purchases: PurchaseService,
        removal: WatchlistPendingRemoval? = nil
    ) -> WatchlistAccessReconciler {
        WatchlistAccessReconciler(
            repository: repository,
            userDefaults: isolatedDefaults(),
            access: { purchases.confirmedWatchlistAccess },
            excludedShowIDs: { removal?.deferredRemovalShowID.map { [$0] } ?? [] }
        )
    }

    private func downgrade(
        _ kind: Downgrade, store: StubPurchaseStoreClient, purchases: PurchaseService
    ) async {
        switch kind {
        case .realLapse:
            store.isStoreEntitled = false
            await purchases.refreshEntitlements()
        case .simulation:
            purchases.setFreeTierSimulation(true)
        }
    }

    private func restore(
        _ kind: Downgrade, store: StubPurchaseStoreClient, purchases: PurchaseService
    ) async {
        switch kind {
        case .realLapse:
            store.isStoreEntitled = true
            await purchases.refreshEntitlements()
        case .simulation:
            purchases.setFreeTierSimulation(false)
        }
    }

    private func pausedIDs(_ repository: any WatchlistRepository) async throws -> Set<Int> {
        Set(try await repository.all().filter(\.isPaused).map(\.id))
    }

    @Test(
        "Six shows: a downgrade keeps the three oldest active; restoring resumes all",
        arguments: Downgrade.allCases)
    func sixShowsKeepThreeOldest(_ kind: Downgrade) async throws {
        let repository = try makeRepository()
        try await seed(1...6, into: repository)
        let store = StubPurchaseStoreClient(isStoreEntitled: true)
        let purchases = makePurchases(store: store)
        let reconciler = makeReconciler(repository: repository, purchases: purchases)

        await downgrade(kind, store: store, purchases: purchases)
        #expect(await reconciler.reconcile() == .paused([4, 5, 6]))
        #expect(await reconciler.reconcile() == .unchanged)
        #expect(try await repository.activeShowIDs() == [1, 2, 3])

        await restore(kind, store: store, purchases: purchases)
        #expect(await reconciler.reconcile() == .resumed([4, 5, 6]))
        #expect(try await repository.activeShowIDs() == [1, 2, 3, 4, 5, 6])
    }

    /// Regression: the pending row used to fill a free slot, leaving two active
    /// shows once its removal committed.
    @Test(
        "A show in its undo window does not take a free slot",
        arguments: Downgrade.allCases)
    func pendingRemovalDoesNotTakeFreeSlot(_ kind: Downgrade) async throws {
        let repository = try makeRepository()
        try await seed(1...7, into: repository)
        let store = StubPurchaseStoreClient(isStoreEntitled: true)
        let purchases = makePurchases(store: store)
        let removal = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService(), purchases: purchases)
        removal.undoWindowSecondsOverride = 60
        let reconciler = makeReconciler(
            repository: repository, purchases: purchases, removal: removal)

        // Star removal of the oldest show (deferred: still saved and active).
        removal.requestRemoval(
            try #require(try await repository.trackedShow(showID: 1)),
            source: .detail)
        await downgrade(kind, store: store, purchases: purchases)
        #expect(await reconciler.reconcile() == .paused([5, 6, 7]))

        await removal.commitPendingRemovalIfNeeded()
        #expect(try await repository.activeShowIDs() == [2, 3, 4])
        #expect(try await pausedIDs(repository) == [5, 6, 7])
    }

    @Test("Undoing an excluded removal applies the limit to the restored show")
    func undoAfterExclusionKeepsThreeOldest() async throws {
        let repository = try makeRepository()
        try await seed(1...7, into: repository)
        let purchases = makePurchases(store: StubPurchaseStoreClient(isStoreEntitled: true))
        let removal = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService(), purchases: purchases)
        removal.undoWindowSecondsOverride = 60
        let reconciler = makeReconciler(
            repository: repository, purchases: purchases, removal: removal)

        removal.requestRemoval(
            try #require(try await repository.trackedShow(showID: 1)),
            source: .detail)
        purchases.setFreeTierSimulation(true)
        _ = await reconciler.reconcile()

        _ = await removal.undoRemoval()
        // `AppCompositionRoot` reconciles after `.undone`, `.cancelled`, `.failed`.
        #expect(await reconciler.reconcile() == .paused([4]))
        #expect(try await repository.activeShowIDs() == [1, 2, 3])
    }
}
