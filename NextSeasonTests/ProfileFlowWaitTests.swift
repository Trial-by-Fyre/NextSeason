import Foundation
import Testing

@testable import NextSeason

@MainActor
struct ProfileFlowWaitTests {
    @Test("An already-delivered UI signal is not missed")
    func immediateSignal() async throws {
        try await ProfileFlowWait.until("search", timeout: .zero, isSatisfied: { true })
    }

    @Test("A missing signal reports the operation that timed out")
    func missingSignal() async {
        do {
            try await ProfileFlowWait.until("search", timeout: .zero, isSatisfied: { false })
            Issue.record("Missing signal must not succeed")
        } catch {
            #expect(error.localizedDescription.contains("search"))
        }
    }

    @Test("The next UI signal satisfies the same wait without a wall-clock sleep")
    func nextSignal() async throws {
        var ready = false
        var polls = 0
        try await ProfileFlowWait.until(
            "search", timeout: .seconds(15), isSatisfied: { ready },
            pause: {
                polls += 1
                ready = true
            })
        #expect(polls == 1)
    }

    @Test("Cancellation from the suspension point aborts polling")
    func cancellation() async {
        var polls = 0
        do {
            try await ProfileFlowWait.until(
                "search", timeout: .seconds(15), isSatisfied: { false },
                pause: {
                    polls += 1
                    throw CancellationError()
                })
            Issue.record("Cancelled wait must not succeed")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(polls == 1)
    }

    @Test("Identical queries get distinct task identities and preserve failure state")
    func repeatedRequestIdentity() {
        let coordinator = AppNavigationCoordinator()
        let first = coordinator.requestAutomationSearch("same query")
        let firstID = coordinator.automationSearchRequestID
        coordinator.notifyAutomationSearchSettled(error: "failed")
        #expect(coordinator.automationSearchError == "failed")
        let second = coordinator.requestAutomationSearch("same query")
        #expect(coordinator.automationSearchRequestID != firstID)
        #expect(second > first)
        #expect(coordinator.automationSearchError == nil)
    }
    @Test("Aborting a request cancels its task identity without signaling success")
    func cancelledRequestIdentity() {
        let coordinator = AppNavigationCoordinator()
        let baseline = coordinator.requestAutomationSearch("query")
        let request = coordinator.automationSearchRequestID
        coordinator.cancelAutomationSearch()
        #expect(coordinator.automationSearchQuery == nil)
        #expect(coordinator.automationSearchRequestID != request)
        #expect(coordinator.automationSearchSettledToken == baseline)
    }

}
