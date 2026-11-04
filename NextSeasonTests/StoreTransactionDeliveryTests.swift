import Foundation
import Testing

@testable import NextSeason

@MainActor
struct StoreTransactionDeliveryTests {
    private let transaction = StoreTransaction(
        id: 6, productID: StoreProductID.plusMonthly.rawValue)

    @Test("Unknown transactions remain unprocessed and unfinished until same-ID approval")
    func unknownThenApproval() async {
        let delivery = StoreTransactionDelivery()
        var trace: [String] = []
        let check = MutableTestValue(PlusEntitlementCheck.unverified)
        delivery.observe { trace.append("process:\($0.id)") }
        let delivered = await delivery.deliver(
            transaction, validate: { check.value },
            onVerified: { trace.append("process:\($0.id)") },
            finish: { trace.append("finish:6") })
        #expect(!delivered)
        await delivery.retryDeferredTransactions()
        #expect(trace.isEmpty)
        check.value = .active
        await delivery.retryDeferredTransactions()
        await delivery.retryDeferredTransactions()
        #expect(trace == ["process:6", "finish:6"])
    }

    @Test("Known inactive transactions still process before finishing")
    func terminalDelivery() async {
        let delivery = StoreTransactionDelivery()
        var trace: [String] = []
        let delivered = await delivery.deliver(
            transaction, validate: { .inactive }, onVerified: { _ in trace.append("process") },
            finish: { trace.append("finish") })
        #expect(delivered)
        #expect(trace == ["process", "finish"])
    }

    @Test("Overlapping retries claim a queued transaction once")
    func overlappingRetries() async {
        let delivery = StoreTransactionDelivery()
        let gate = DeliveryValidationGate()
        var initial = true
        var processed = 0
        var finished = 0
        delivery.observe { _ in processed += 1 }
        await delivery.deliver(
            transaction,
            validate: {
                if initial {
                    initial = false
                    return .unverified
                }
                return await gate.wait()
            }, onVerified: { _ in processed += 1 }, finish: { finished += 1 })
        let first = Task { await delivery.retryDeferredTransactions() }
        await gate.waitForCount(1)
        let second = Task { await delivery.retryDeferredTransactions() }
        await waitForJoin(delivery)
        gate.resumeFirst(.active)
        await first.value
        await second.value
        #expect(processed == 1)
        #expect(finished == 1)
    }

    @Test("Observer delivery and a suspended retry cannot both consume a queued transaction")
    func observerDuringRetry() async {
        let delivery = StoreTransactionDelivery()
        let gate = DeliveryValidationGate()
        var initial = true
        var processed = 0
        var finished = 0
        delivery.observe { _ in processed += 1 }
        await delivery.deliver(
            transaction,
            validate: {
                if initial {
                    initial = false
                    return .unverified
                }
                return await gate.wait()
            }, onVerified: { _ in processed += 1 }, finish: { finished += 1 })
        let retry = Task { await delivery.retryDeferredTransactions() }
        await gate.waitForCount(1)
        let update = Task {
            await delivery.deliver(
                transaction, validate: { .active },
                onVerified: { _ in processed += 1 }, finish: { finished += 1 })
        }
        await waitForJoin(delivery)
        gate.resumeFirst(.active)
        await retry.value
        #expect(await update.value)
        #expect(processed == 1)
        #expect(finished == 1)
    }

    @Test("Stopping observation during validation prevents late processing or finish")
    func stopDuringDelivery() async {
        let delivery = StoreTransactionDelivery()
        let gate = DeliveryValidationGate()
        var effects = 0
        let task = Task {
            await delivery.deliver(
                transaction, validate: { await gate.wait() },
                onVerified: { _ in effects += 1 }, finish: { effects += 1 })
        }
        await gate.waitForCount(1)
        delivery.stop()
        gate.resumeFirst(.active)
        #expect(await task.value == false)
        #expect(effects == 0)
    }

    @Test("An old retry cannot consume a new observation's same-ID candidate")
    func restartDuringRetry() async {
        let delivery = StoreTransactionDelivery()
        let gate = DeliveryValidationGate()
        var initial = true
        var oldEffects = 0
        var newEffects = 0
        delivery.observe { _ in oldEffects += 1 }
        await delivery.deliver(
            transaction,
            validate: {
                if initial {
                    initial = false
                    return .unverified
                }
                return await gate.wait()
            }, onVerified: { _ in oldEffects += 1 }, finish: { oldEffects += 1 })
        let retry = Task { await delivery.retryDeferredTransactions() }
        await gate.waitForCount(1)
        delivery.observe { _ in newEffects += 1 }
        let approved = MutableTestValue(false)
        await delivery.deliver(
            transaction, validate: { approved.value ? .active : .unverified },
            onVerified: { _ in newEffects += 1 }, finish: { newEffects += 1 })
        gate.resumeFirst(.active)
        await retry.value
        #expect(oldEffects == 0)
        #expect(newEffects == 0)
        approved.value = true
        await delivery.retryDeferredTransactions()
        #expect(newEffects == 2)
    }

    @Test(
        "Approval without an event restores Plus before automatic finish", .timeLimit(.minutes(1)))
    func silentApprovalAutomaticallyRecovers() async throws {
        let sleeper = DeliveryRetrySleeper()
        let delivery = StoreTransactionDelivery(sleep: { await sleeper.wait($0) })
        let store = StubPurchaseStoreClient()
        store.reportsUnverifiedEntitlement = true
        let defaults = try #require(UserDefaults(suiteName: "SilentApproval.\(UUID().uuidString)"))
        let purchases = PurchaseService(
            store: store,
            entitlementStore: PlusEntitlementStore(
                userDefaults: defaults, persistence: MemoryComplimentaryPlusPersistence()))
        await purchases.start()
        let approved = MutableTestValue(false)
        var finishedWithAccess = false
        delivery.observe { await store.emitVerifiedTransaction($0) }
        await delivery.deliver(
            transaction, validate: { approved.value ? .active : .unverified },
            onVerified: { await store.emitVerifiedTransaction($0) },
            finish: { finishedWithAccess = purchases.isUnlimitedWatchlist })
        await sleeper.waitForCalls(1)
        let task = try #require(delivery.automaticRetryTask)
        sleeper.resumeFirst()
        await sleeper.waitForCalls(2)
        #expect(!purchases.isUnlimitedWatchlist)
        #expect(store.finishedTransactionIDs.isEmpty)
        #expect(!finishedWithAccess)
        // No transaction event, foreground return or explicit retry is sent.
        approved.value = true
        store.isStoreEntitled = true
        store.reportsUnverifiedEntitlement = false
        sleeper.resumeFirst()
        await task.value
        #expect(purchases.isUnlimitedWatchlist)
        #expect(finishedWithAccess)
        #expect(store.finishedTransactionIDs == [6])
        #expect(sleeper.durations == [.seconds(2), .seconds(2)])
        #expect(delivery.automaticRetryTask == nil)
    }

    @Test(
        "Stopping during automatic sleep prevents even a fresh validation", .timeLimit(.minutes(1)))
    func stopDuringAutomaticSleep() async throws {
        let sleeper = DeliveryRetrySleeper()
        let delivery = StoreTransactionDelivery(sleep: { await sleeper.wait($0) })
        var validations = 0
        var effects = 0
        delivery.observe { _ in effects += 1 }
        await delivery.deliver(
            transaction,
            validate: {
                validations += 1
                return .unverified
            }, onVerified: { _ in effects += 1 }, finish: { effects += 1 })
        await sleeper.waitForCalls(1)
        let task = try #require(delivery.automaticRetryTask)
        delivery.stop()
        // This injected sleeper deliberately ignores cancellation until resumed.
        sleeper.resumeFirst()
        await task.value
        #expect(validations == 1)
        #expect(effects == 0)
        #expect(delivery.automaticRetryTask == nil)
    }

    @Test("Old automatic retry cleanup cannot clear the replacement task", .timeLimit(.minutes(1)))
    func replaceAutomaticRetryGeneration() async throws {
        let sleeper = DeliveryRetrySleeper()
        let delivery = StoreTransactionDelivery(sleep: { await sleeper.wait($0) })
        var oldEffects = 0
        var newEffects = 0
        delivery.observe { _ in oldEffects += 1 }
        await delivery.deliver(
            transaction, validate: { .unverified },
            onVerified: { _ in oldEffects += 1 }, finish: { oldEffects += 1 })
        await sleeper.waitForCalls(1)
        let oldTask = try #require(delivery.automaticRetryTask)
        delivery.observe { _ in newEffects += 1 }
        let approved = MutableTestValue(false)
        await delivery.deliver(
            transaction, validate: { approved.value ? .active : .unverified },
            onVerified: { _ in newEffects += 1 }, finish: { newEffects += 1 })
        await sleeper.waitForCalls(2)
        let newTask = try #require(delivery.automaticRetryTask)
        sleeper.resumeFirst()
        await oldTask.value
        #expect(delivery.automaticRetryTask != nil)
        approved.value = true
        sleeper.resumeFirst()
        await newTask.value
        #expect(oldEffects == 0)
        #expect(newEffects == 2)
        #expect(delivery.automaticRetryTask == nil)
    }

    @Test("Automatic retries release the queue between checks", .timeLimit(.minutes(1)))
    func automaticSleepDoesNotRetainQueue() async throws {
        let sleeper = DeliveryRetrySleeper()
        var delivery: StoreTransactionDelivery? = StoreTransactionDelivery(sleep: {
            await sleeper.wait($0)
        })
        weak let weakDelivery = delivery
        delivery?.observe { _ in Issue.record("Unknown transaction was delivered") }
        await delivery?.deliver(
            transaction, validate: { .unverified },
            onVerified: { _ in Issue.record("Unexpected delivery") },
            finish: { Issue.record("Unexpected finish") })
        await sleeper.waitForCalls(1)
        let task = try #require(delivery?.automaticRetryTask)
        sleeper.resumeFirst()
        await sleeper.waitForCalls(2)
        delivery = nil
        #expect(weakDelivery == nil)
        sleeper.resumeFirst()
        await task.value
    }

    @Test("An unfinished snapshot restores and finishes without any earlier update event")
    func recoverApprovedWithoutUpdate() async throws {
        let delivery = StoreTransactionDelivery()
        let store = StubPurchaseStoreClient()
        let defaults = try #require(
            UserDefaults(suiteName: "UnfinishedRecovery.\(UUID().uuidString)"))
        let purchases = PurchaseService(
            store: store,
            entitlementStore: PlusEntitlementStore(
                userDefaults: defaults, persistence: MemoryComplimentaryPlusPersistence()))
        await purchases.start()
        #expect(!purchases.isUnlimitedWatchlist)
        delivery.observe { await store.emitVerifiedTransaction($0) }
        store.isStoreEntitled = true
        var finishedWithAccess = false
        await delivery.recoverUnfinishedTransactions {
            [
                .init(
                    transaction: transaction, validate: { .active },
                    finish: { finishedWithAccess = purchases.isUnlimitedWatchlist })
            ]
        }
        #expect(purchases.isUnlimitedWatchlist)
        #expect(store.finishedTransactionIDs == [6])
        #expect(finishedWithAccess)
        #expect(delivery.automaticRetryTask == nil)
    }

    @Test(
        "Recovered pending transactions stay unfinished and recover on silent approval",
        .timeLimit(.minutes(1)))
    func recoverPendingWithoutUpdate() async throws {
        let sleeper = DeliveryRetrySleeper()
        let delivery = StoreTransactionDelivery(sleep: { await sleeper.wait($0) })
        let approved = MutableTestValue(false)
        var trace: [String] = []
        delivery.observe { trace.append("process:\($0.id)") }
        await delivery.recoverUnfinishedTransactions {
            [
                .init(
                    transaction: transaction, validate: { approved.value ? .active : .unverified },
                    finish: { trace.append("finish:6") })
            ]
        }
        await sleeper.waitForCalls(1)
        let task = try #require(delivery.automaticRetryTask)
        #expect(trace.isEmpty)
        approved.value = true
        sleeper.resumeFirst()
        await task.value
        #expect(trace == ["process:6", "finish:6"])
    }

    @Test("Stopping during unfinished loading rejects the old snapshot", .timeLimit(.minutes(1)))
    func stopDuringUnfinishedLoad() async {
        let delivery = StoreTransactionDelivery()
        let gate = UnfinishedSnapshotGate()
        var effects = 0
        delivery.observe { _ in effects += 1 }
        let task = Task {
            await delivery.recoverUnfinishedTransactions {
                await gate.wait()
                return [
                    .init(transaction: transaction, validate: { .active }, finish: { effects += 1 })
                ]
            }
        }
        await gate.waitForStart()
        delivery.stop()
        gate.resume()
        await task.value
        #expect(effects == 0)
        #expect(delivery.automaticRetryTask == nil)
    }

    @Test("Restart during one recovered callback cannot send later candidates to the old observer")
    func restartBetweenUnfinishedCandidates() async {
        let delivery = StoreTransactionDelivery()
        var trace: [String] = []
        delivery.observe { value in
            trace.append("old:\(value.id)")
            delivery.observe { trace.append("new:\($0.id)") }
        }
        let second = StoreTransaction(id: 7, productID: StoreProductID.plusMonthly.rawValue)
        await delivery.recoverUnfinishedTransactions {
            [
                .init(
                    transaction: transaction, validate: { .active },
                    finish: { trace.append("finish:6") }),
                .init(
                    transaction: second, validate: { .active },
                    finish: { trace.append("finish:old7") }),
            ]
        }
        #expect(trace == ["old:6", "finish:6"])
        await delivery.recoverUnfinishedTransactions {
            [
                .init(
                    transaction: second, validate: { .active },
                    finish: { trace.append("finish:new7") })
            ]
        }
        #expect(trace == ["old:6", "finish:6", "new:7", "finish:new7"])
    }

    @Test("A stopped recovery observer does not even load unfinished candidates")
    func noObserverSkipsUnfinishedLoad() async {
        let delivery = StoreTransactionDelivery()
        var loads = 0
        await delivery.recoverUnfinishedTransactions {
            loads += 1
            return []
        }
        #expect(loads == 0)
    }

    private func waitForJoin(_ delivery: StoreTransactionDelivery) async {
        for _ in 0..<1_000 {
            if delivery.waitingDeliveryCount == 1 { return }
            await Task.yield()
        }
        Issue.record("Delivery did not join the in-flight transaction")
    }
}

/// Test input changed after a `@MainActor` (implicitly `Sendable`) closure
/// captures it; a captured `var` would be flagged as mutated after capture.
@MainActor
private final class MutableTestValue<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

@MainActor
private final class DeliveryValidationGate {
    private var waiters: [CheckedContinuation<PlusEntitlementCheck, Never>] = []

    func wait() async -> PlusEntitlementCheck {
        await withCheckedContinuation { waiters.append($0) }
    }

    func waitForCount(_ count: Int) async {
        for _ in 0..<1_000 {
            if waiters.count == count { return }
            await Task.yield()
        }
        Issue.record("Validation did not suspend as expected")
    }

    func resumeFirst(_ check: PlusEntitlementCheck) {
        guard !waiters.isEmpty else {
            Issue.record("No suspended validation")
            return
        }
        waiters.removeFirst().resume(returning: check)
    }
}

@MainActor
private final class DeliveryRetrySleeper {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var durations: [Duration] = []

    func wait(_ duration: Duration) async {
        durations.append(duration)
        await withCheckedContinuation { waiters.append($0) }
    }

    func waitForCalls(_ count: Int) async {
        for _ in 0..<1_000 {
            if durations.count == count, !waiters.isEmpty { return }
            await Task.yield()
        }
        Issue.record("Automatic retry did not reach the expected sleep")
    }

    func resumeFirst() {
        guard !waiters.isEmpty else {
            Issue.record("No suspended retry sleep")
            return
        }
        waiters.removeFirst().resume()
    }
}

@MainActor
private final class UnfinishedSnapshotGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func waitForStart() async {
        for _ in 0..<1_000 {
            if continuation != nil { return }
            await Task.yield()
        }
        Issue.record("Unfinished snapshot did not suspend")
    }

    func resume() {
        guard let continuation else {
            Issue.record("No suspended snapshot")
            return
        }
        self.continuation = nil
        continuation.resume()
    }
}
