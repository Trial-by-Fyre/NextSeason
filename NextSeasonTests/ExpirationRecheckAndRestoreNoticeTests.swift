//
//  ExpirationRecheckAndRestoreNoticeTests.swift
//  NextSeasonTests
//

import Foundation
import Testing

@testable import NextSeason

/// Controllable stand-in for `Task.sleep`: records each requested delay and
/// suspends until the test fires it. Cancellation resumes with `CancellationError`.
@MainActor
final class ManualSleeper {
    private(set) var requests: [Duration] = []
    private var waiters: [Int: CheckedContinuation<Void, any Error>] = [:]

    /// Sleeps that are still waiting (neither fired nor cancelled).
    var pendingCount: Int { waiters.count }

    func sleep(_ duration: Duration) async throws {
        let index = requests.count
        requests.append(duration)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters[index] = continuation
            }
        } onCancel: {
            Task { @MainActor in self.cancel(index) }
        }
    }

    /// Lets the most recently requested, still-pending sleep finish.
    func fireLatest() {
        guard let index = waiters.keys.max() else { return }
        waiters.removeValue(forKey: index)?.resume()
    }

    private func cancel(_ index: Int) {
        waiters.removeValue(forKey: index)?.resume(throwing: CancellationError())
    }
}

/// Re-check at subscription expiration while the app stays open, and the
/// Restore Purchases notice. Behavior matrix:
/// `Documentation/Reviews/ExpirationRecheckAndRestoreFeedback-2026-10-21.md`.
@MainActor
struct ExpirationRecheckAndRestoreNoticeTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let margin = PurchaseService.expirationRecheckMargin

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "ExpirationRecheckAndRestoreNoticeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makePurchases(
        store: StubPurchaseStoreClient,
        sleeper: ManualSleeper,
        complimentary: Bool = false
    ) -> PurchaseService {
        let defaults = isolatedDefaults()
        if complimentary { defaults.set(true, forKey: PlusEntitlementStore.complimentaryKey) }
        let fixedNow = start
        return PurchaseService(
            store: store,
            entitlementStore: PlusEntitlementStore(
                userDefaults: defaults, persistence: MemoryComplimentaryPlusPersistence()),
            initialStoreEntitlement: .loading,
            simulationAvailability: { false },
            now: { fixedNow },
            sleep: { try await sleeper.sleep($0) }
        )
    }

    private func makeReconciler(
        repository: any WatchlistRepository, purchases: PurchaseService
    ) -> WatchlistAccessReconciler {
        WatchlistAccessReconciler(
            repository: repository,
            userDefaults: isolatedDefaults(),
            access: { purchases.confirmedWatchlistAccess }
        )
    }

    /// Active Plus expiring an hour after `start`.
    private func activeStore() -> StubPurchaseStoreClient {
        let store = StubPurchaseStoreClient(isStoreEntitled: true)
        store.plusExpirationDate = start.addingTimeInterval(3600)
        return store
    }

    private func seedFiveShows(into repository: InMemoryWatchlistRepository) async throws {
        for id in 1...5 {
            try await repository.add(
                Show(
                    id: id, name: "Show \(id)", tvMazeURL: nil, summaryHTML: nil,
                    posterMediumURL: nil, posterOriginalURL: nil, status: .running,
                    premiered: nil, ended: nil, network: nil, genres: [], averageRuntime: nil,
                    seasons: [], nextEpisode: nil, updatedAt: .now))
        }
    }

    /// Yields until `condition` holds (the fired timer's read commits asynchronously).
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("Condition not reached")
    }

    // MARK: - Scheduling

    @Test("An active read schedules one re-check at expiration plus the margin")
    func activeReadSchedulesRecheck() async {
        let sleeper = ManualSleeper()
        let purchases = makePurchases(store: activeStore(), sleeper: sleeper)

        await purchases.start()

        #expect(sleeper.requests == [.seconds(3600) + margin])
        #expect(sleeper.pendingCount == 1)
        #expect(purchases.hasPendingExpirationRecheck)
    }

    @Test(
        "No re-check without a future deadline (unknown date, or elapsed margin)",
        arguments: [nil, -300.0, -360.0])
    func noFutureDeadlineSchedulesNothing(_ offset: TimeInterval?) async {
        let sleeper = ManualSleeper()
        let store = StubPurchaseStoreClient(isStoreEntitled: true)
        store.plusExpirationDate = offset.map { start.addingTimeInterval($0) }
        let purchases = makePurchases(store: store, sleeper: sleeper)

        await purchases.start()

        #expect(purchases.isStoreEntitled, "Grace period is still entitled")
        #expect(sleeper.requests.isEmpty, "A past date must not loop")
        #expect(purchases.hasPendingExpirationRecheck == false)
    }

    @Test("A slightly fast clock preserves the re-check within the five-minute margin")
    func pastExpirationWithinMarginSchedulesRecheck() async {
        let sleeper = ManualSleeper()
        let store = StubPurchaseStoreClient(isStoreEntitled: true)
        // StoreKit still confirms Plus, but the device clock sees expiration a
        // minute in the past. The complete re-check deadline is four minutes away.
        store.plusExpirationDate = start.addingTimeInterval(-60)
        let purchases = makePurchases(store: store, sleeper: sleeper)

        await purchases.start()

        #expect(purchases.isStoreEntitled)
        #expect(sleeper.requests == [.seconds(240)])
        #expect(sleeper.pendingCount == 1)
        #expect(purchases.hasPendingExpirationRecheck)

        store.isStoreEntitled = false
        sleeper.fireLatest()
        await settle { purchases.storeEntitlement == .resolved(isEntitled: false) }

        #expect(purchases.hasPendingExpirationRecheck == false)
        #expect(sleeper.requests.count == 1)
    }

    // MARK: - Expiration while open

    @Test("Expiration while open pauses all but the three oldest shows, without deleting")
    func expirationWhileOpenPausesShows() async throws {
        let sleeper = ManualSleeper()
        let store = activeStore()
        let purchases = makePurchases(store: store, sleeper: sleeper)
        let repository = InMemoryWatchlistRepository()
        try await seedFiveShows(into: repository)
        let reconciler = makeReconciler(repository: repository, purchases: purchases)
        await purchases.start()
        #expect(await reconciler.reconcile() == .unchanged)

        store.isStoreEntitled = false  // Auto-renew was off; the period ends.
        sleeper.fireLatest()
        await settle { purchases.storeEntitlement == .resolved(isEntitled: false) }

        #expect(await reconciler.reconcile() == .paused([4, 5]))
        #expect(try await repository.all().count == 5)
        #expect(reconciler.shouldPresentPausedAlert)
        #expect(purchases.hasPendingExpirationRecheck == false, "Nothing left to watch")
        #expect(sleeper.requests.count == 1)
    }

    @Test("A late renewal after a re-check pause resumes every show")
    func renewalAfterRecheckResumes() async throws {
        let sleeper = ManualSleeper()
        let store = activeStore()
        let purchases = makePurchases(store: store, sleeper: sleeper)
        let repository = InMemoryWatchlistRepository()
        try await seedFiveShows(into: repository)
        let reconciler = makeReconciler(repository: repository, purchases: purchases)
        await purchases.start()

        // Renewal not yet visible when the re-check runs.
        store.isStoreEntitled = false
        sleeper.fireLatest()
        await settle { purchases.storeEntitlement == .resolved(isEntitled: false) }
        #expect(await reconciler.reconcile() == .paused([4, 5]))

        store.isStoreEntitled = true
        store.plusExpirationDate = start.addingTimeInterval(7200)
        await store.emitVerifiedTransaction(
            StoreTransaction(
                id: 900, productID: StoreProductID.plusMonthly.rawValue,
                isCustomerPurchase: false))

        #expect(await reconciler.reconcile() == .resumed([4, 5]))
        #expect(reconciler.shouldPresentPausedAlert == false)
        #expect(sleeper.requests.last == .seconds(7200) + margin)
    }

    @Test("A renewal before expiration replaces the pending re-check")
    func renewalReplacesPendingRecheck() async {
        let sleeper = ManualSleeper()
        let store = activeStore()
        let purchases = makePurchases(store: store, sleeper: sleeper)
        await purchases.start()

        store.plusExpirationDate = start.addingTimeInterval(7200)
        await store.emitVerifiedTransaction(
            StoreTransaction(
                id: 901, productID: StoreProductID.plusMonthly.rawValue,
                isCustomerPurchase: false))
        await settle { sleeper.pendingCount == 1 }

        #expect(sleeper.requests == [.seconds(3600) + margin, .seconds(7200) + margin])
        #expect(sleeper.pendingCount == 1, "The earlier sleep was cancelled")
        #expect(purchases.isStoreEntitled)
    }

    @Test("The re-check's own read reschedules when it finds a renewal")
    func recheckReadReschedulesItself() async {
        let sleeper = ManualSleeper()
        let store = activeStore()
        let purchases = makePurchases(store: store, sleeper: sleeper)
        await purchases.start()

        store.plusExpirationDate = start.addingTimeInterval(7200)
        sleeper.fireLatest()
        await settle { sleeper.requests.count == 2 }
        // Let the fired task finish; it must not clear the new schedule.
        for _ in 0..<30 { await Task.yield() }

        #expect(purchases.hasPendingExpirationRecheck)
        #expect(sleeper.pendingCount == 1)
        #expect(purchases.isStoreEntitled)
    }

    @Test("An unverified read keeps confirmed Plus and the pending re-check")
    func unverifiedKeepsRecheck() async {
        let sleeper = ManualSleeper()
        let store = activeStore()
        let purchases = makePurchases(store: store, sleeper: sleeper)
        await purchases.start()

        store.reportsUnverifiedEntitlement = true
        await purchases.refreshEntitlements()

        #expect(purchases.storeEntitlement == .resolved(isEntitled: true))
        #expect(purchases.hasPendingExpirationRecheck)
        #expect(sleeper.pendingCount == 1)
        #expect(sleeper.requests.count == 1)
    }

    @Test("The margin is the owner's five minutes")
    func marginIsFiveMinutes() {
        #expect(PurchaseService.expirationRecheckMargin == .seconds(300))
    }

    @Test("An unverified answer to the re-check keeps Plus and leaves nothing scheduled")
    func unverifiedRecheckReadLeavesNothingScheduled() async {
        let sleeper = ManualSleeper()
        let store = activeStore()
        let purchases = makePurchases(store: store, sleeper: sleeper)
        await purchases.start()

        store.reportsUnverifiedEntitlement = true
        sleeper.fireLatest()
        await settle { purchases.lastCommittedCheck == .unverified }

        #expect(purchases.storeEntitlement == .resolved(isEntitled: true))
        #expect(purchases.hasPendingExpirationRecheck == false)
        #expect(sleeper.requests.count == 1)
    }

    @Test("A confirmed lapse cancels the pending re-check")
    func lapseCancelsRecheck() async {
        let sleeper = ManualSleeper()
        let store = activeStore()
        let purchases = makePurchases(store: store, sleeper: sleeper)
        await purchases.start()

        store.isStoreEntitled = false
        await purchases.handleSceneBecameActive()
        await settle { sleeper.pendingCount == 0 }

        #expect(purchases.hasPendingExpirationRecheck == false)
        #expect(sleeper.requests.count == 1)
    }

    // MARK: - Restore Purchases notice

    @Test("Restore with no purchases explains that no subscription was found")
    func restoreNoticeWhenNothingFound() async throws {
        let purchases = makePurchases(
            store: StubPurchaseStoreClient(isStoreEntitled: false), sleeper: ManualSleeper())
        await purchases.start()

        #expect(await purchases.restorePurchases() == .success)
        let notice = try #require(purchases.restoreNotice)
        #expect(notice.contains("No active NextSeason Plus subscription"))
        #expect(purchases.isUnlimitedWatchlist == false)
    }

    @Test("A free user whose restore read is unverified is told it couldn't be verified")
    func restoreNoticeWhenUnverified() async {
        let store = StubPurchaseStoreClient(isStoreEntitled: false)
        let purchases = makePurchases(store: store, sleeper: ManualSleeper())
        await purchases.start()

        store.reportsUnverifiedEntitlement = true
        #expect(await purchases.restorePurchases() == .success)

        #expect(purchases.storeEntitlement == .resolved(isEntitled: false), "No grant")
        #expect(purchases.restoreNotice?.contains("couldn't verify") == true)
    }

    @Test("No notice when restore finds Plus, or the user has complimentary Plus")
    func noRestoreNoticeWithPlus() async {
        let store = StubPurchaseStoreClient(isStoreEntitled: false)
        let purchases = makePurchases(store: store, sleeper: ManualSleeper())
        await purchases.start()
        store.isStoreEntitled = true
        #expect(await purchases.restorePurchases() == .success)
        #expect(purchases.restoreNotice == nil)

        let complimentary = makePurchases(
            store: StubPurchaseStoreClient(isStoreEntitled: false), sleeper: ManualSleeper(),
            complimentary: true)
        await complimentary.start()
        #expect(await complimentary.restorePurchases() == .success)
        #expect(complimentary.restoreNotice == nil)
    }
}
