//
//  ObservationWait.swift
//  NextSeasonTests
//

import Observation
import Synchronization

/// Suspends until `condition` is true, re-checking each time the observable state
/// it reads changes. Unlike a wall-clock deadline, a slow simulator cannot make it
/// give up early. Cancellation (for example the test's time limit) releases the
/// wait and throws, so a state that never arrives cannot leave it suspended.
@MainActor
func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
    while !condition() {
        try Task.checkCancellation()
        let resumer = OneShotResumer()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                resumer.store(continuation)
                withObservationTracking {
                    _ = condition()
                } onChange: {
                    resumer.resume()
                }
            }
        } onCancel: {
            resumer.resume()
        }
    }
}

/// Resumes a continuation exactly once, from whichever comes first: the state
/// change or cancellation. A resume that arrives before the continuation is
/// stored (cancellation already requested) is applied as soon as it is stored.
private final class OneShotResumer: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Void, Never>?
        var resumed = false
    }

    private let state = Mutex(State())

    func store(_ continuation: CheckedContinuation<Void, Never>) {
        let resumeNow = state.withLock { state in
            if state.resumed { return true }
            state.continuation = continuation
            return false
        }
        if resumeNow { continuation.resume() }
    }

    func resume() {
        let continuation = state.withLock { state in
            state.resumed = true
            defer { state.continuation = nil }
            return state.continuation
        }
        continuation?.resume()
    }
}
