//
//  RefreshSchedulerTests.swift
//  NextSeasonTests
//

import Foundation
import Testing

@testable import NextSeason

@MainActor
struct RefreshSchedulerTests {
    @Test("Normal completion reports success once")
    func normalCompletionReportsSuccessOnce() {
        var outcomes: [Bool] = []
        let completion = BackgroundRefreshCompletion { outcomes.append($0) }

        completion.finish(success: true)
        completion.finish(success: false)

        #expect(outcomes == [true])
    }

    @Test("Expiration reports failure once")
    func expirationReportsFailureOnce() {
        var outcomes: [Bool] = []
        let completion = BackgroundRefreshCompletion { outcomes.append($0) }

        completion.finish(success: false)
        completion.finish(success: true)

        #expect(outcomes == [false])
    }

    @Test("Cancelled work finishes as failure and a later success is ignored")
    func cancelledWorkFinishesAsFailure() async {
        var outcomes: [Bool] = []
        let completion = BackgroundRefreshCompletion { outcomes.append($0) }
        let started = AsyncStream.makeStream(of: Void.self)

        let work = Task { @MainActor in
            started.continuation.yield()
            started.continuation.finish()
            try? await Task.sleep(for: .seconds(30))
            if Task.isCancelled {
                completion.finish(success: false)
            } else {
                completion.finish(success: true)
            }
        }
        defer { work.cancel() }

        for await _ in started.stream { break }

        work.cancel()
        completion.finish(success: false)
        await work.value

        #expect(work.isCancelled)
        #expect(outcomes == [false])
    }

    @Test("First finisher wins when expiration and normal completion race")
    func firstFinisherWinsWhenExpirationAndCompletionRace() async {
        var outcomes: [Bool] = []
        let firstFinish = AsyncStream.makeStream(of: Void.self)
        let completion = BackgroundRefreshCompletion { success in
            outcomes.append(success)
            firstFinish.continuation.yield()
            firstFinish.continuation.finish()
        }

        let work = Task { @MainActor in
            completion.finish(success: true)
        }
        RefreshScheduler.handleExpiredAppRefresh(work: work, completion: completion)

        for await _ in firstFinish.stream { break }
        await work.value

        #expect(outcomes.count == 1)
    }

    @Test("Expiration from a background queue hops to the main actor before completing")
    func expirationFromBackgroundQueueHopsToMainActorBeforeCompleting() async {
        let work: Task<Void, Never> = Task {
            try? await Task.sleep(for: .seconds(30))
        }
        defer { work.cancel() }

        let result = await withCheckedContinuation {
            (continuation: CheckedContinuation<(success: Bool, onMain: Bool), Never>) in
            let completion = BackgroundRefreshCompletion { success in
                continuation.resume(returning: (success, Thread.isMainThread))
            }
            DispatchQueue.global().async {
                RefreshScheduler.handleExpiredAppRefresh(work: work, completion: completion)
            }
        }

        #expect(result.success == false)
        #expect(result.onMain == true)
        #expect(work.isCancelled)
    }
}
