import Foundation

/// Keeps uncertain local StoreKit updates unfinished until a later lifecycle
/// check can resolve them. No purchase or abandoned Add Show state is persisted.
@MainActor
final class StoreTransactionDelivery {
    struct Candidate {
        let transaction: StoreTransaction
        let validate: @MainActor () async -> PlusEntitlementCheck
        let finish: @MainActor () async -> Void
    }

    private struct Deferred {
        let token = UUID()
        let transaction: StoreTransaction
        let validate: @MainActor () async -> PlusEntitlementCheck
        let finish: @MainActor () async -> Void
    }

    private struct InFlight {
        let token = UUID()
        var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    }

    private var deferred: [UInt64: Deferred] = [:]
    private var generation: UInt = 0
    private var inFlight: [UInt64: InFlight] = [:]
    private var observer: (@MainActor (StoreTransaction) async -> Void)?
    private let sleep: @MainActor (Duration) async throws -> Void
    private(set) var automaticRetryTask: Task<Void, Never>?

    var waitingDeliveryCount: Int { inFlight.values.reduce(0) { $0 + $1.waiters.count } }

    init(
        sleep: @escaping @MainActor (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.sleep = sleep
    }

    func observe(_ onVerified: @escaping @MainActor (StoreTransaction) async -> Void) {
        stop()
        observer = onVerified
    }

    func stop() {
        generation &+= 1
        automaticRetryTask?.cancel()
        automaticRetryTask = nil
        observer = nil
        deferred.removeAll()
        let abandoned = inFlight
        inFlight.removeAll()
        for flight in abandoned.values {
            for waiter in flight.waiters.values { waiter.resume(returning: false) }
        }
    }

    @discardableResult
    func deliver(
        _ transaction: StoreTransaction,
        validate: @escaping @MainActor () async -> PlusEntitlementCheck,
        onVerified: @MainActor (StoreTransaction) async -> Void,
        finish: @escaping @MainActor () async -> Void
    ) async -> Bool {
        let currentGeneration = generation
        if let flight = inFlight[transaction.id] {
            return await waitForDelivery(id: transaction.id, token: flight.token)
        }
        let flight = InFlight()
        inFlight[transaction.id] = flight
        var delivered = false
        defer { completeFlight(id: transaction.id, token: flight.token, delivered: delivered) }
        let check = await validate()
        guard currentGeneration == generation else { return false }
        guard !Task.isCancelled, check != .unverified else {
            // A canceled caller must not strand an approved transaction. The
            // independent observer/retry will process it in the same generation.
            deferred[transaction.id] = Deferred(
                transaction: transaction, validate: validate, finish: finish)
            startAutomaticRetryIfNeeded()
            return false
        }
        // Claim any queued copy before suspending in application processing.
        deferred.removeValue(forKey: transaction.id)
        await onVerified(transaction)
        await finish()
        delivered = true
        return true
    }

    /// A local verified purchase may still need deferred status resolution. A
    /// shared observer delivery is also acknowledged to the purchasing caller,
    /// which records its own verified-purchase/simulation completion evidence.
    func completePurchase(
        _ candidate: Candidate,
        onVerified: @MainActor (StoreTransaction) async -> Void
    ) async throws -> PurchaseOutcome {
        let currentGeneration = generation
        var acknowledged = false
        let delivered = await deliver(
            candidate.transaction, validate: candidate.validate,
            onVerified: { transaction in
                acknowledged = true
                await onVerified(transaction)
            }, finish: candidate.finish)
        try Task.checkCancellation()
        guard currentGeneration == generation else { throw CancellationError() }
        guard delivered else { return .pending }
        if !acknowledged {
            // Content was already processed and finished by the shared flight;
            // acknowledge this purchase without delivering/finishing it again.
            await onVerified(candidate.transaction)
            try Task.checkCancellation()
            guard currentGeneration == generation else { throw CancellationError() }
        }
        return .success
    }

    private func waitForDelivery(id: UInt64, token: UUID) async -> Bool {
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled, inFlight[id]?.token == token else {
                    continuation.resume(returning: false)
                    return
                }
                inFlight[id]?.waiters[waiterID] = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.inFlight[id]?.token == token else { return }
                self?.inFlight[id]?.waiters.removeValue(forKey: waiterID)?.resume(returning: false)
            }
        }
    }

    private func completeFlight(id: UInt64, token: UUID, delivered: Bool) {
        guard inFlight[id]?.token == token, let flight = inFlight.removeValue(forKey: id) else {
            return
        }
        for waiter in flight.waiters.values { waiter.resume(returning: delivered) }
    }

    func retryDeferredTransactions() async {
        guard let observer else { return }
        let currentGeneration = generation
        let candidates = deferred
        for (id, pending) in candidates {
            guard currentGeneration == generation, !Task.isCancelled else { return }
            guard deferred[id]?.token == pending.token else { continue }
            await deliver(
                pending.transaction, validate: pending.validate,
                onVerified: observer, finish: pending.finish)
            guard currentGeneration == generation, !Task.isCancelled else { return }
        }
    }

    /// Rebuilds transient recovery state even when StoreKit does not redeliver a
    /// local unfinished transaction through its updates listener after launch.
    func recoverUnfinishedTransactions(load: () async -> [Candidate]) async {
        guard let observer else { return }
        let currentGeneration = generation
        let candidates = await load()
        guard currentGeneration == generation, !Task.isCancelled else { return }
        for candidate in candidates {
            guard currentGeneration == generation, !Task.isCancelled else { return }
            await deliver(
                candidate.transaction, validate: candidate.validate,
                onVerified: observer, finish: candidate.finish)
            // Application processing can itself stop/restart observation. Never
            // pass a later candidate to that now-obsolete observer.
            guard currentGeneration == generation, !Task.isCancelled else { return }
        }
        await retryDeferredTransactions()
    }

    /// Xcode can change approval status without delivering another transaction
    /// event. Re-read only the local candidates; the live adapter never places
    /// App Store/sandbox transactions here. A timer never substitutes for approval.
    private func startAutomaticRetryIfNeeded() {
        guard automaticRetryTask == nil, observer != nil, !deferred.isEmpty else { return }
        let currentGeneration = generation
        let sleep = sleep
        automaticRetryTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await sleep(.seconds(2))
                } catch {
                    if let self, self.generation == currentGeneration {
                        self.automaticRetryTask = nil
                    }
                    return
                }
                // Acquire self only after sleeping, so observation does not keep
                // its owner alive. Old cleanup must never clear a newer task.
                guard let self, self.generation == currentGeneration, !Task.isCancelled else {
                    return
                }
                await self.retryDeferredTransactions()
                guard self.generation == currentGeneration, !Task.isCancelled else { return }
                if self.deferred.isEmpty {
                    self.automaticRetryTask = nil
                    return
                }
            }
        }
    }

    isolated deinit {
        automaticRetryTask?.cancel()
    }
}
