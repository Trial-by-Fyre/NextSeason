//
//  PurchaseServiceEntitlementOrderingTests.swift
//  NextSeasonTests
//

import Foundation
import SwiftData
import Testing

@testable import NextSeason

/// Mutable complimentary-grant eligibility for tests that grant mid-read.
@MainActor
private final class EligibilityFlag {
    var value = false
}

/// Regression coverage for overlapping entitlement reads and caller-completion contracts.
///
/// Reads run concurrently; the stub holds each one until released (oldest first,
/// or newest first to model a stalled earlier scan), so ordering is explicit.
@MainActor
struct PurchaseServiceEntitlementOrderingTests {
    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "PurchaseServiceEntitlementOrdering.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makePurchases(
        store: StubPurchaseStoreClient,
        initial: StoreEntitlementState = .loading,
        simulationAvailable: Bool = false,
        complimentaryGrantEligibility: @escaping @MainActor () async -> Bool = { false }
    ) -> PurchaseService {
        PurchaseService(
            store: store,
            entitlementStore: PlusEntitlementStore(
                userDefaults: isolatedDefaults(),
                persistence: MemoryComplimentaryPlusPersistence()),
            initialStoreEntitlement: initial,
            complimentaryGrantEligibility: complimentaryGrantEligibility,
            simulationAvailability: { simulationAvailable }
        )
    }

    private func makeReconciler(
        repository: any WatchlistRepository,
        purchases: PurchaseService,
        defaults: UserDefaults
    ) -> WatchlistAccessReconciler {
        WatchlistAccessReconciler(
            repository: repository,
            userDefaults: defaults,
            access: { purchases.confirmedWatchlistAccess },
            waitForAccess: { await purchases.waitForInitialEntitlementResolution() }
        )
    }

    /// Waits until at least `count` entitlement reads are suspended in the stub.
    private func waitUntilHeldReads(_ store: StubPurchaseStoreClient, count: Int) async {
        for _ in 0..<200 {
            if store.entitlementWaiterCount >= count { return }
            await Task.yield()
        }
        Issue.record(
            "Expected \(count) suspended entitlement reads, saw \(store.entitlementWaiterCount)")
    }

    /// Lets a released read deliver its result before asserting it was discarded.
    private func settle() async {
        for _ in 0..<30 { await Task.yield() }
    }

    private func seedFiveShows(into repository: any WatchlistRepository) async throws {
        for id in 1...5 {
            try await repository.add(
                Show(
                    id: id, name: "Show \(id)", tvMazeURL: nil, summaryHTML: nil,
                    posterMediumURL: nil, posterOriginalURL: nil, status: .running,
                    premiered: nil, ended: nil, network: nil, genres: [], averageRuntime: nil,
                    seasons: [], nextEpisode: nil, updatedAt: .now))
        }
    }

    private func pausedIDs(_ repository: any WatchlistRepository) async throws -> Set<Int> {
        Set(try await repository.all().filter(\.isPaused).map(\.id))
    }

    // MARK: - Superseded results are discarded

    @Test("Superseded inactive read is discarded and cannot revoke Plus")
    func supersededInactiveCannotRevokePlus() async {
        let store = StubPurchaseStoreClient(isStoreEntitled: false)
        store.entitlementCheckScripts = [
            EntitlementCheckScript(delayed: true, result: .inactive),
            EntitlementCheckScript(delayed: true, result: .active),
        ]
        let purchases = makePurchases(store: store, initial: .resolved(isEntitled: true))

        let older = Task { await purchases.refreshEntitlements() }
        await waitUntilHeldReads(store, count: 1)
        let newer = Task { await purchases.refreshEntitlements() }
        await waitUntilHeldReads(store, count: 2)
        #expect(purchases.entitlementRefreshEpoch == 2)
        #expect(purchases.confirmedWatchlistAccess == true)

        store.releaseNextEntitlementResolution()
        await settle()
        #expect(purchases.confirmedWatchlistAccess == true)

        store.releaseNextEntitlementResolution()
        await newer.value
        await older.value
        #expect(purchases.isStoreEntitled)
    }

    @Test("Superseded active read is discarded and cannot restore stale Plus")
    func supersededActiveCannotRestoreStalePlus() async {
        let store = StubPurchaseStoreClient(isStoreEntitled: true)
        store.entitlementCheckScripts = [
            EntitlementCheckScript(delayed: true, result: .active),
            EntitlementCheckScript(delayed: true, result: .inactive),
        ]
        let purchases = makePurchases(store: store, initial: .resolved(isEntitled: false))

        let older = Task { await purchases.refreshEntitlements() }
        await waitUntilHeldReads(store, count: 1)
        let newer = Task { await purchases.refreshEntitlements() }
        await waitUntilHeldReads(store, count: 2)
        #expect(purchases.confirmedWatchlistAccess == false)

        store.releaseNextEntitlementResolution()
        await settle()
        #expect(purchases.confirmedWatchlistAccess == false)

        store.releaseNextEntitlementResolution()
        await newer.value
        await older.value
        #expect(purchases.isStoreEntitled == false)
    }

    @Test("Releasing a superseded inactive read does not temporarily pause saved shows")
    func supersededInactiveNeverPausesRows() async throws {
        let repository = InMemoryWatchlistRepository()
        try await seedFiveShows(into: repository)
        let defaults = isolatedDefaults()
        let store = StubPurchaseStoreClient(isStoreEntitled: false)
        store.entitlementCheckScripts = [
            EntitlementCheckScript(delayed: true, result: .inactive),
            EntitlementCheckScript(delayed: true, result: .active),
        ]
        let purchases = makePurchases(store: store, initial: .resolved(isEntitled: true))
        let reconciler = makeReconciler(
            repository: repository, purchases: purchases, defaults: defaults)

        let older = Task { await purchases.refreshEntitlements() }
        await waitUntilHeldReads(store, count: 1)
        let newer = Task { await purchases.refreshEntitlements() }
        await waitUntilHeldReads(store, count: 2)

        store.releaseNextEntitlementResolution()
        for _ in 0..<30 {
            #expect(purchases.confirmedWatchlistAccess != false)
            if purchases.confirmedWatchlistAccess == false {
                _ = await reconciler.reconcile()
                Issue.record("Confirmed free access during superseded lifecycle read")
            }
            await Task.yield()
        }
        #expect(try await pausedIDs(repository).isEmpty)

        store.releaseNextEntitlementResolution()
        await newer.value
        await older.value
        _ = await reconciler.reconcile()
        #expect(try await pausedIDs(repository).isEmpty)
    }

    @Test("Initial-resolution waiters stay pending until the latest read commits")
    func waitersPendingUntilLatestCommit() async {
        let store = StubPurchaseStoreClient(isStoreEntitled: true)
        store.entitlementCheckScripts = [
            EntitlementCheckScript(delayed: true, result: .inactive),
            EntitlementCheckScript(delayed: true, result: .active),
        ]
        let purchases = makePurchases(store: store, initial: .loading)

        let older = Task { await purchases.refreshEntitlements() }
        await waitUntilHeldReads(store, count: 1)
        let newer = Task { await purchases.refreshEntitlements() }
        await waitUntilHeldReads(store, count: 2)

        var waiterCompleted = false
        let waiter = Task {
            await purchases.waitForInitialEntitlementResolution()
            waiterCompleted = true
        }
        await settle()
        #expect(waiterCompleted == false)

        store.releaseNextEntitlementResolution()
        await settle()
        #expect(waiterCompleted == false)

        store.releaseNextEntitlementResolution()
        await newer.value
        await waiter.value
        await older.value
        #expect(purchases.isStoreEntitled)
    }

    @Test(
        "Cancelling the latest refresh caller still commits its read and resumes initial-resolution waiters"
    )
    func cancelledLatestCallerDoesNotStrandWaiters() async {
        let store = StubPurchaseStoreClient(isStoreEntitled: true)
        store.entitlementCheckScripts = [
            EntitlementCheckScript(delayed: true, result: .inactive),
            EntitlementCheckScript(delayed: true, result: .active),
        ]
        let purchases = makePurchases(store: store, initial: .loading)

        let older = Task { await purchases.refreshEntitlements() }
        await waitUntilHeldReads(store, count: 1)
        let newer = Task { await purchases.refreshEntitlements() }
        await waitUntilHeldReads(store, count: 2)
        // Cancel the caller whose read is the only one allowed to commit; no
        // later refresh exists to rescue the waiter if that commit were skipped.
        newer.cancel()

        let waiter = Task { await purchases.waitForInitialEntitlementResolution() }

        store.releaseNextEntitlementResolution()
        await settle()
        store.releaseNextEntitlementResolution()
        await newer.value
        await waiter.value
        await older.value
        #expect(purchases.isStoreEntitled)
    }

    // MARK: - Transaction and simulation callers

    @Test(
        "Transaction finish waits for the latest entitlement read when lifecycle read is superseded"
    )
    func transactionFinishWaitsForLatestRead() async throws {
        let store = StubPurchaseStoreClient(isStoreEntitled: true)
        store.entitlementCheckScripts = [
            EntitlementCheckScript(result: .active),
            EntitlementCheckScript(delayed: true, result: .inactive),
            EntitlementCheckScript(delayed: true, result: .active),
        ]
        let purchases = makePurchases(store: store, initial: .resolved(isEntitled: true))
        await purchases.start()

        let lifecycle = Task { await purchases.handleSceneBecameActive() }
        await waitUntilHeldReads(store, count: 1)

        var finishCount = 0
        var entitledAtFinish = false
        store.onFinish = {
            finishCount += 1
            entitledAtFinish = purchases.isStoreEntitled
        }
        let transaction = Task {
            await store.emitVerifiedTransaction(
                StoreTransaction(id: 1, productID: StoreProductID.plusMonthly.rawValue))
        }
        await waitUntilHeldReads(store, count: 2)
        #expect(store.startedEntitlementCheckCount == 3)
        #expect(finishCount == 0)

        store.releaseNextEntitlementResolution()
        await settle()
        #expect(purchases.confirmedWatchlistAccess != false)
        #expect(finishCount == 0)

        store.releaseNextEntitlementResolution()
        await transaction.value
        #expect(finishCount == 1)
        #expect(entitledAtFinish)
        await lifecycle.value
        #expect(purchases.isStoreEntitled)
    }

    @Test("Pending simulation ends only after the latest read confirms Plus")
    func simulationEndsAfterLatestReadConfirmsPlus() async {
        let store = StubPurchaseStoreClient(isStoreEntitled: false, purchaseOutcome: .pending)
        store.entitlementCheckScripts = [
            EntitlementCheckScript(result: .inactive),
            EntitlementCheckScript(delayed: true, result: .inactive),
            EntitlementCheckScript(delayed: true, result: .active),
        ]
        let purchases = makePurchases(
            store: store, initial: .loading, simulationAvailable: true)
        await purchases.start()
        purchases.setFreeTierSimulation(true)
        #expect(await purchases.purchase(StoreProduct(.plusMonthly)) == .pending)

        let lifecycle = Task { await purchases.refreshEntitlements() }
        await waitUntilHeldReads(store, count: 1)
        let completion = Task {
            await store.emitVerifiedTransaction(
                StoreTransaction(id: 2, productID: StoreProductID.plusMonthly.rawValue))
        }
        await waitUntilHeldReads(store, count: 2)
        #expect(purchases.isSimulatingFreeTier)

        store.releaseNextEntitlementResolution()
        await settle()
        #expect(purchases.isSimulatingFreeTier)

        store.releaseNextEntitlementResolution()
        await completion.value
        #expect(purchases.isSimulatingFreeTier == false)
        #expect(purchases.isStoreEntitled)
        await lifecycle.value
    }

    @Test(
        "Transaction update whose own read is superseded does not finish until the newer read commits"
    )
    func supersededTransactionReadDelaysFinishUntilLatestCommit() async {
        let store = StubPurchaseStoreClient(isStoreEntitled: false)
        store.entitlementCheckScripts = [
            EntitlementCheckScript(result: .inactive),
            EntitlementCheckScript(delayed: true, result: .active),
            EntitlementCheckScript(delayed: true, result: .active),
        ]
        let purchases = makePurchases(store: store, initial: .loading)
        await purchases.start()
        #expect(purchases.isStoreEntitled == false)

        var finishCount = 0
        var entitledAtFinish = false
        store.onFinish = {
            finishCount += 1
            entitledAtFinish = purchases.isStoreEntitled
        }
        let transaction = Task {
            await store.emitVerifiedTransaction(
                StoreTransaction(id: 1, productID: StoreProductID.plusMonthly.rawValue))
        }
        await waitUntilHeldReads(store, count: 1)
        let lifecycle = Task { await purchases.handleSceneBecameActive() }
        await waitUntilHeldReads(store, count: 2)

        // The transaction's read returns but is discarded; it must not finish yet.
        store.releaseNextEntitlementResolution()
        await settle()
        #expect(finishCount == 0)
        #expect(purchases.isStoreEntitled == false)

        store.releaseNextEntitlementResolution()
        await transaction.value
        #expect(finishCount == 1)
        #expect(entitledAtFinish)
        await lifecycle.value
        #expect(purchases.isStoreEntitled)
    }

    @Test("Superseded caller keeps waiting when a further refresh supersedes the read it awaited")
    func supersededCallerFollowsReplacedTail() async {
        let store = StubPurchaseStoreClient(isStoreEntitled: false)
        store.entitlementCheckScripts = [
            EntitlementCheckScript(result: .inactive),
            EntitlementCheckScript(delayed: true, result: .active),
            EntitlementCheckScript(delayed: true, result: .active),
            EntitlementCheckScript(delayed: true, result: .active),
        ]
        let purchases = makePurchases(store: store, initial: .loading)
        await purchases.start()

        var finishCount = 0
        var entitledAtFinish = false
        store.onFinish = {
            finishCount += 1
            entitledAtFinish = purchases.isStoreEntitled
        }
        let transaction = Task {
            await store.emitVerifiedTransaction(
                StoreTransaction(id: 1, productID: StoreProductID.plusMonthly.rawValue))
        }
        await waitUntilHeldReads(store, count: 1)
        let lifecycle = Task { await purchases.refreshEntitlements() }
        await waitUntilHeldReads(store, count: 2)

        // Transaction read discarded; the lifecycle read is now the newest.
        store.releaseNextEntitlementResolution()
        await settle()
        // A background refresh supersedes that read before it completes.
        let background = Task { await purchases.refreshEntitlements() }
        await waitUntilHeldReads(store, count: 2)

        // Lifecycle read discarded too; the transaction must still be unfinished.
        store.releaseNextEntitlementResolution()
        await settle()
        #expect(finishCount == 0)
        #expect(purchases.isStoreEntitled == false)

        store.releaseNextEntitlementResolution()
        await transaction.value
        #expect(finishCount == 1)
        #expect(entitledAtFinish)
        await lifecycle.value
        await background.value
        #expect(purchases.isStoreEntitled)
    }

    @Test(
        "Pending simulation ends when the completing update's read is superseded by a lifecycle read"
    )
    func simulationEndsWhenUpdateReadIsSuperseded() async {
        let store = StubPurchaseStoreClient(isStoreEntitled: false, purchaseOutcome: .pending)
        store.entitlementCheckScripts = [
            EntitlementCheckScript(result: .inactive),
            EntitlementCheckScript(delayed: true, result: .active),
            EntitlementCheckScript(delayed: true, result: .active),
        ]
        let purchases = makePurchases(
            store: store, initial: .loading, simulationAvailable: true)
        await purchases.start()
        purchases.setFreeTierSimulation(true)
        #expect(await purchases.purchase(StoreProduct(.plusMonthly)) == .pending)

        let completion = Task {
            await store.emitVerifiedTransaction(
                StoreTransaction(id: 2, productID: StoreProductID.plusMonthly.rawValue))
        }
        await waitUntilHeldReads(store, count: 1)
        let lifecycle = Task { await purchases.refreshEntitlements() }
        await waitUntilHeldReads(store, count: 2)

        store.releaseNextEntitlementResolution()
        await settle()
        #expect(purchases.isSimulatingFreeTier)

        store.releaseNextEntitlementResolution()
        await completion.value
        #expect(purchases.isSimulatingFreeTier == false)
        #expect(purchases.isStoreEntitled)
        await lifecycle.value
    }

    // MARK: - Stalled reads

    @Test("A stalled older read does not block a newer commit; releasing it later changes nothing")
    func stalledOlderReadDoesNotBlockNewerCommit() async throws {
        let container = try ModelContainer(
            for: TrackedShowEntity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let repository = SwiftDataWatchlistRepository(context: ModelContext(container))
        try await seedFiveShows(into: repository)
        let defaults = isolatedDefaults()
        let store = StubPurchaseStoreClient(isStoreEntitled: false)
        store.entitlementCheckScripts = [
            EntitlementCheckScript(delayed: true, result: .inactive),
            EntitlementCheckScript(delayed: true, result: .active),
        ]
        let purchases = makePurchases(store: store, initial: .loading)
        let reconciler = makeReconciler(
            repository: repository, purchases: purchases, defaults: defaults)

        var finishCount = 0
        var entitledAtFinish = false
        store.onFinish = {
            finishCount += 1
            entitledAtFinish = purchases.isStoreEntitled
        }
        let startup = Task { await purchases.start() }
        await waitUntilHeldReads(store, count: 1)
        var initialResolved = false
        let waiter = Task {
            await purchases.waitForInitialEntitlementResolution()
            initialResolved = true
        }
        let transaction = Task {
            await store.emitVerifiedTransaction(
                StoreTransaction(id: 1, productID: StoreProductID.plusMonthly.rawValue))
        }
        await waitUntilHeldReads(store, count: 2)
        await settle()
        #expect(initialResolved == false)

        // The startup read stays held; the newer transaction read confirms Plus.
        store.releaseNewestEntitlementResolution()
        await transaction.value
        #expect(finishCount == 1)
        #expect(entitledAtFinish)
        await waiter.value
        await startup.value
        #expect(store.entitlementWaiterCount == 1)
        _ = await reconciler.reconcile()
        #expect(try await pausedIDs(repository).isEmpty)

        // The stalled read finally returns inactive and must be discarded.
        store.releaseNextEntitlementResolution()
        await settle()
        #expect(purchases.isStoreEntitled)
        #expect(purchases.confirmedWatchlistAccess == true)
        #expect(finishCount == 1)
        #expect(store.finishedTransactionIDs == [1])
        _ = await reconciler.reconcile()
        #expect(try await pausedIDs(repository).isEmpty)
    }

    @Test("Known limit: callers wait on a stalled newest read until a later refresh commits")
    func stalledNewestReadParksCallersUntilLaterCommit() async {
        let store = StubPurchaseStoreClient(isStoreEntitled: false)
        store.entitlementCheckScripts = [
            EntitlementCheckScript(result: .inactive),
            EntitlementCheckScript(delayed: true, result: .active),
            EntitlementCheckScript(delayed: true, result: .inactive),
            EntitlementCheckScript(delayed: true, result: .active),
        ]
        let purchases = makePurchases(store: store, initial: .loading)
        await purchases.start()

        var finishCount = 0
        var entitledAtFinish = false
        store.onFinish = {
            finishCount += 1
            entitledAtFinish = purchases.isStoreEntitled
        }
        let transaction = Task {
            await store.emitVerifiedTransaction(
                StoreTransaction(id: 1, productID: StoreProductID.plusMonthly.rawValue))
        }
        await waitUntilHeldReads(store, count: 1)
        let lifecycle = Task { await purchases.handleSceneBecameActive() }
        await waitUntilHeldReads(store, count: 2)

        // The transaction's own read returns but the newer lifecycle read stalls.
        store.releaseNextEntitlementResolution()
        await settle()
        #expect(finishCount == 0)

        // A later refresh commits and unblocks everyone still waiting.
        let background = Task { await purchases.refreshEntitlements() }
        await waitUntilHeldReads(store, count: 2)
        store.releaseNewestEntitlementResolution()
        await transaction.value
        #expect(finishCount == 1)
        #expect(entitledAtFinish)
        await lifecycle.value
        await background.value

        store.releaseNextEntitlementResolution()
        await settle()
        #expect(purchases.isStoreEntitled)
    }

    @Test("A burst of overlapping refreshes resumes every caller once the newest read commits")
    func burstOfRefreshesResumesAllCallers() async {
        let store = StubPurchaseStoreClient(isStoreEntitled: true)
        store.entitlementCheckScripts =
            Array(repeating: EntitlementCheckScript(delayed: true, result: .inactive), count: 4)
            + [EntitlementCheckScript(delayed: true, result: .active)]
        let purchases = makePurchases(store: store, initial: .loading)

        var returnedCount = 0
        var callers: [Task<Void, Never>] = []
        for count in 1...5 {
            callers.append(
                Task {
                    await purchases.refreshEntitlements()
                    returnedCount += 1
                })
            await waitUntilHeldReads(store, count: count)
        }
        let waiter = Task { await purchases.waitForInitialEntitlementResolution() }

        for _ in 0..<4 { store.releaseNextEntitlementResolution() }
        await settle()
        #expect(returnedCount == 0)
        #expect(purchases.hasResolvedStoreEntitlement == false)

        store.releaseNextEntitlementResolution()
        for caller in callers { await caller.value }
        await waiter.value
        #expect(returnedCount == 5)
        #expect(purchases.isStoreEntitled)
    }

    // MARK: - Restore, verification failure, complimentary

    @Test("Restore completes while an older lifecycle read stays held")
    func restoreOverlappingHeldLifecycleRead() async {
        let store = StubPurchaseStoreClient(isStoreEntitled: false)
        store.entitlementCheckScripts = [
            EntitlementCheckScript(delayed: true, result: .inactive),
            EntitlementCheckScript(delayed: true, result: .active),
        ]
        let purchases = makePurchases(store: store, initial: .resolved(isEntitled: false))

        let lifecycle = Task { await purchases.refreshEntitlements() }
        await waitUntilHeldReads(store, count: 1)
        let restore = Task { await purchases.restorePurchases() }
        await waitUntilHeldReads(store, count: 2)
        #expect(purchases.isPurchasing)

        store.releaseNewestEntitlementResolution()
        #expect(await restore.value == .success)
        #expect(purchases.isStoreEntitled)
        #expect(purchases.isPurchasing == false)
        await lifecycle.value

        store.releaseNextEntitlementResolution()
        await settle()
        #expect(purchases.isStoreEntitled)
    }

    @Test("Newest unverified read keeps confirmed Plus after a discarded inactive read")
    func newestUnverifiedKeepsConfirmedPlus() async throws {
        let repository = InMemoryWatchlistRepository()
        try await seedFiveShows(into: repository)
        let store = StubPurchaseStoreClient(isStoreEntitled: false)
        store.entitlementCheckScripts = [
            EntitlementCheckScript(delayed: true, result: .inactive),
            EntitlementCheckScript(delayed: true, result: .unverified),
        ]
        let purchases = makePurchases(store: store, initial: .resolved(isEntitled: true))
        let reconciler = makeReconciler(
            repository: repository, purchases: purchases, defaults: isolatedDefaults())

        let older = Task { await purchases.refreshEntitlements() }
        await waitUntilHeldReads(store, count: 1)
        let newer = Task { await purchases.refreshEntitlements() }
        await waitUntilHeldReads(store, count: 2)

        store.releaseNextEntitlementResolution()
        await settle()
        store.releaseNextEntitlementResolution()
        await newer.value
        await older.value
        #expect(purchases.storeEntitlement == .resolved(isEntitled: true))
        _ = await reconciler.reconcile()
        #expect(try await pausedIDs(repository).isEmpty)
    }

    @Test("Newest unverified first read becomes unverified after a discarded active read")
    func newestUnverifiedFromLoadingIsUnverified() async throws {
        let repository = InMemoryWatchlistRepository()
        try await seedFiveShows(into: repository)
        let store = StubPurchaseStoreClient(isStoreEntitled: false)
        store.entitlementCheckScripts = [
            EntitlementCheckScript(delayed: true, result: .active),
            EntitlementCheckScript(delayed: true, result: .unverified),
        ]
        let purchases = makePurchases(store: store, initial: .loading)
        let reconciler = makeReconciler(
            repository: repository, purchases: purchases, defaults: isolatedDefaults())

        let older = Task { await purchases.refreshEntitlements() }
        await waitUntilHeldReads(store, count: 1)
        let newer = Task { await purchases.refreshEntitlements() }
        await waitUntilHeldReads(store, count: 2)
        let waiter = Task { await purchases.waitForInitialEntitlementResolution() }

        store.releaseNextEntitlementResolution()
        await settle()
        #expect(purchases.storeEntitlement == .loading)
        store.releaseNextEntitlementResolution()
        await newer.value
        await older.value
        await waiter.value
        #expect(purchases.storeEntitlement == .unverified)
        #expect(purchases.confirmedWatchlistAccess == nil)
        #expect(purchases.isUnlimitedWatchlist == false)
        _ = await reconciler.reconcile()
        #expect(try await pausedIDs(repository).isEmpty)
    }

    @Test("Complimentary grant during a held read resumes initial waiters but not refresh callers")
    func complimentaryGrantDuringHeldRead() async {
        let eligibility = EligibilityFlag()
        let store = StubPurchaseStoreClient(isStoreEntitled: false)
        store.entitlementCheckScripts = [EntitlementCheckScript(delayed: true, result: .inactive)]
        let purchases = makePurchases(
            store: store, initial: .loading,
            complimentaryGrantEligibility: { eligibility.value })

        var refreshReturned = false
        let refresh = Task {
            await purchases.refreshEntitlements()
            refreshReturned = true
        }
        await waitUntilHeldReads(store, count: 1)
        let waiter = Task { await purchases.waitForInitialEntitlementResolution() }
        await settle()

        eligibility.value = true
        await purchases.handleSceneBecameActive()
        await waiter.value
        #expect(purchases.isComplimentary)
        await settle()
        #expect(refreshReturned == false)

        store.releaseNextEntitlementResolution()
        await refresh.value
        #expect(purchases.storeEntitlement == .resolved(isEntitled: false))
        #expect(purchases.confirmedWatchlistAccess == true)
    }

    @Test("Confirmed Plus survives a superseded unverified read using SwiftData persistence")
    func supersededUnverifiedPreservesConfirmedPlusInSwiftData() async throws {
        let container = try ModelContainer(
            for: TrackedShowEntity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let repository = SwiftDataWatchlistRepository(context: ModelContext(container))
        try await seedFiveShows(into: repository)
        let defaults = isolatedDefaults()
        let store = StubPurchaseStoreClient(isStoreEntitled: true)
        store.entitlementCheckScripts = [
            EntitlementCheckScript(delayed: true, result: .unverified),
            EntitlementCheckScript(delayed: true, result: .active),
        ]
        let purchases = makePurchases(store: store, initial: .resolved(isEntitled: true))
        let reconciler = makeReconciler(
            repository: repository, purchases: purchases, defaults: defaults)

        let older = Task { await purchases.refreshEntitlements() }
        await waitUntilHeldReads(store, count: 1)
        let newer = Task { await purchases.refreshEntitlements() }
        await waitUntilHeldReads(store, count: 2)
        #expect(purchases.confirmedWatchlistAccess == true)

        store.releaseNextEntitlementResolution()
        for _ in 0..<30 {
            #expect(purchases.confirmedWatchlistAccess == true)
            await Task.yield()
        }

        store.releaseNextEntitlementResolution()
        await newer.value
        await older.value
        _ = await reconciler.reconcile()
        #expect(purchases.isStoreEntitled)
        #expect(try await pausedIDs(repository).isEmpty)
    }
}
