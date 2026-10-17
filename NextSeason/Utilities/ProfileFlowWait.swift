import Foundation

/// Cancellation-aware waits for profiling UI signals. A timeout is a failed
/// scenario, never an implicit success followed by the next operation.
@MainActor
enum ProfileFlowWait {
    enum Failure: Error, LocalizedError {
        case timedOut(String)

        var errorDescription: String? {
            switch self {
            case .timedOut(let operation): "Profiling timed out waiting for " + operation
            }
        }
    }

    static func until(
        _ operation: String,
        timeout: Duration,
        isSatisfied: () -> Bool,
        pause: () async throws -> Void = { try await Task.sleep(for: .milliseconds(50)) }
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while true {
            try Task.checkCancellation()
            if isSatisfied() { return }
            guard clock.now < deadline else { throw Failure.timedOut(operation) }
            try await pause()
        }
    }
}
