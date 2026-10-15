//
//  WatchlistPendingRemovalTests.swift
//  NextSeasonTests
//

import CoreGraphics
import Foundation
import Testing

@testable import NextSeason

@MainActor
struct WatchlistPendingRemovalTests {
    private var sampleShow: Show {
        Show(
            id: 44933,
            name: "Severance",
            tvMazeURL: URL(string: "https://www.tvmaze.com/shows/44933/severance"),
            summaryHTML: "<p>A workplace thriller.</p>",
            posterMediumURL: nil,
            posterOriginalURL: nil,
            status: .running,
            premiered: TVMazeDate.dateOnly("2022-02-18"),
            ended: nil,
            network: "Apple TV",
            genres: ["Drama"],
            averageRuntime: 49,
            seasons: [],
            nextEpisode: nil,
            updatedAt: .now
        )
    }

    private var secondShow: Show {
        Show(
            id: 82,
            name: "Game of Thrones",
            tvMazeURL: nil,
            summaryHTML: nil,
            posterMediumURL: nil,
            posterOriginalURL: nil,
            status: .ended,
            premiered: nil,
            ended: nil,
            network: "HBO",
            genres: [],
            averageRuntime: nil,
            seasons: [],
            nextEpisode: nil,
            updatedAt: .now
        )
    }

    @Test("Requesting removal defers persistence until commit")
    func requestRemovalDefersPersistence() async throws {
        let repository = InMemoryWatchlistRepository()
        let coordinator = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        try await repository.add(sampleShow)
        let tracked = try #require((try await repository.all()).first)

        var outcomes: [PendingRemovalOutcome] = []
        coordinator.addOutcomeHandler { outcomes.append($0) }
        coordinator.requestRemoval(
            tracked, anchor: CGRect(x: 10, y: 20, width: 44, height: 44), source: .watchlist
        )

        #expect(coordinator.pendingRemoval?.id == tracked.id)
        #expect(coordinator.toastAnchor == CGRect(x: 10, y: 20, width: 44, height: 44))
        #expect(try await repository.contains(showID: tracked.id))
        #expect(outcomes.isEmpty)

        await coordinator.commitPendingRemovalIfNeeded()

        #expect(try await repository.contains(showID: tracked.id) == false)
        #expect(coordinator.pendingRemoval == nil)
        #expect(outcomes == [.committed(showID: tracked.id)])
    }

    @Test("OK confirm dismisses the toast before persistence finishes", .timeLimit(.minutes(1)))
    func confirmPendingRemovalDismissesSynchronously() async throws {
        let repository = GatedCancellationAwareRemoveRepository()
        let coordinator = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        try await repository.add(sampleShow)
        let tracked = try #require((try await repository.all()).first)

        var outcomes: [PendingRemovalOutcome] = []
        coordinator.addOutcomeHandler { outcomes.append($0) }
        coordinator.requestRemoval(tracked, anchor: .zero, source: .watchlist)

        coordinator.confirmPendingRemoval()

        // Toast presentation must clear on the button-action turn, not after remove.
        #expect(coordinator.pendingRemoval == nil)
        #expect(coordinator.toastAnchor == nil)

        await repository.waitUntilRemoveBegan()
        repository.resumeRemove()

        // Persistence finishes on the coordinator's own task, which emits the
        // outcome after the remove is saved; wait for it, not a fixed time.
        try await waitUntil { coordinator.lastOutcome != nil }

        #expect(try await repository.contains(showID: tracked.id) == false)
        #expect(outcomes == [.committed(showID: tracked.id)])
    }

    @Test("Undo emits an explicit undone outcome")
    func undoEmitsUndoneOutcome() async throws {
        let repository = InMemoryWatchlistRepository()
        let coordinator = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        try await repository.add(sampleShow)
        let tracked = try #require((try await repository.all()).first)

        var outcomes: [PendingRemovalOutcome] = []
        coordinator.addOutcomeHandler { outcomes.append($0) }
        coordinator.requestRemoval(tracked, anchor: .zero, source: .watchlist)
        _ = await coordinator.undoRemoval()

        #expect(outcomes == [.undone(showID: tracked.id)])
    }

    @Test("Navigation dismiss emits cancelled for deferred removals")
    func navigationDismissEmitsCancelledOutcome() async throws {
        let repository = InMemoryWatchlistRepository()
        let coordinator = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        try await repository.add(sampleShow)
        let tracked = try #require((try await repository.all()).first)

        var outcomes: [PendingRemovalOutcome] = []
        coordinator.addOutcomeHandler { outcomes.append($0) }
        coordinator.requestRemoval(tracked, anchor: .zero, source: .watchlist)
        coordinator.dismissPendingRemovalForNavigation()

        #expect(outcomes == [.cancelled(showID: tracked.id)])
        #expect(try await repository.contains(showID: tracked.id))
    }

    @Test("Replacing a pending removal emits replaced for the prior show", .timeLimit(.minutes(1)))
    func replacingPendingRemovalEmitsReplacedOutcome() async throws {
        let repository = InMemoryWatchlistRepository()
        let coordinator = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        try await repository.add(sampleShow)
        try await repository.add(secondShow)
        let first = try #require((try await repository.all()).first { $0.id == sampleShow.id })
        let second = try #require((try await repository.all()).first { $0.id == secondShow.id })

        var outcomes: [PendingRemovalOutcome] = []
        coordinator.addOutcomeHandler { outcomes.append($0) }
        coordinator.requestRemoval(first, anchor: .zero, source: .watchlist)
        coordinator.requestRemoval(second, anchor: .zero, source: .detail)

        // The replaced outcome is emitted by a task the coordinator starts itself;
        // wait for it rather than a fixed time.
        try await waitUntil { coordinator.lastOutcome == .replaced(showID: first.id) }

        #expect(outcomes == [.replaced(showID: first.id)])
    }

    @Test("Undo cancels a pending removal without touching persistence")
    func undoLeavesRepositoryUntouched() async throws {
        let repository = InMemoryWatchlistRepository()
        let coordinator = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        try await repository.add(sampleShow)
        let tracked = try #require((try await repository.all()).first)

        coordinator.requestRemoval(tracked, anchor: .zero, source: .watchlist)
        let restored = await coordinator.undoRemoval()

        #expect(restored?.id == tracked.id)
        #expect(coordinator.pendingRemoval == nil)
        #expect(coordinator.toastAnchor == nil)
        #expect(try await repository.contains(showID: tracked.id))
    }

    @Test(
        "Immediate removal persists right away and undo restores the show",
        .timeLimit(.minutes(1)))
    func immediateRemovalPersistsThenUndoRestores() async throws {
        let repository = InMemoryWatchlistRepository()
        let analytics = RecordingAnalyticsService()
        let coordinator = WatchlistPendingRemoval(repository: repository, analytics: analytics)
        try await repository.add(sampleShow)
        let tracked = try #require((try await repository.all()).first)

        var outcomes: [PendingRemovalOutcome] = []
        coordinator.addOutcomeHandler { outcomes.append($0) }
        coordinator.requestImmediateRemoval(
            tracked, anchor: CGRect(x: 10, y: 40, width: 100, height: 44), source: .watchlist
        )

        // The immediate remove runs on the coordinator's own task, which emits
        // the outcome after the remove is saved; wait for it, not a fixed time.
        try await waitUntil { coordinator.lastOutcome != nil }

        #expect(try await repository.contains(showID: tracked.id) == false)
        #expect(outcomes == [.committed(showID: tracked.id)])
        #expect(coordinator.pendingRemoval?.id == tracked.id)
        #expect(coordinator.toastAnchor == CGRect(x: 10, y: 40, width: 100, height: 44))

        let restored = await coordinator.undoRemoval()
        #expect(restored?.id == tracked.id)
        #expect(coordinator.pendingRemoval == nil)
        #expect(try await repository.contains(showID: tracked.id))
        #expect(
            analytics.events.contains {
                if case .watchlistRemoved(let source, let showID) = $0 {
                    return source == .watchlist && showID == tracked.id
                }
                return false
            }
        )
    }

    @Test("Committing an immediate removal only dismisses the toast", .timeLimit(.minutes(1)))
    func commitImmediateRemovalDismissesToastOnly() async throws {
        let repository = InMemoryWatchlistRepository()
        let coordinator = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        try await repository.add(sampleShow)
        let tracked = try #require((try await repository.all()).first)

        coordinator.requestImmediateRemoval(tracked, anchor: .zero, source: .watchlist)

        // Wait for the immediate remove's emitted outcome, not a fixed time.
        try await waitUntil { coordinator.lastOutcome != nil }

        await coordinator.commitPendingRemovalIfNeeded()

        #expect(coordinator.pendingRemoval == nil)
        #expect(try await repository.contains(showID: tracked.id) == false)
    }

    @Test("A new pending removal commits the previous show", .timeLimit(.minutes(1)))
    func replacingPendingRemovalCommitsPrevious() async throws {
        let repository = InMemoryWatchlistRepository()
        let coordinator = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        try await repository.add(sampleShow)
        try await repository.add(secondShow)
        let first = try #require((try await repository.all()).first { $0.id == sampleShow.id })
        let second = try #require((try await repository.all()).first { $0.id == secondShow.id })

        coordinator.requestRemoval(first, anchor: .zero, source: .watchlist)
        coordinator.requestRemoval(second, anchor: .zero, source: .detail)

        #expect(coordinator.pendingRemoval?.id == second.id)

        // Replace commits the previous show via an unstructured Task, which emits
        // the replaced outcome after the remove is saved; wait for that outcome.
        try await waitUntil { coordinator.lastOutcome == .replaced(showID: first.id) }

        #expect(try await repository.contains(showID: first.id) == false)
        #expect(try await repository.contains(showID: second.id))
    }

    @Test("Undo after commit has begun cannot reverse an in-flight removal")
    func undoDuringPersistReturnsNilAndRemovalCompletes() async throws {
        let repository = UndoDuringRemoveRepository()
        let coordinator = WatchlistPendingRemoval(
            repository: repository, analytics: RecordingAnalyticsService())
        repository.undoProbe = { await coordinator.undoRemoval() }
        try await repository.add(sampleShow)
        let tracked = try #require((try await repository.all()).first)

        coordinator.requestRemoval(tracked, anchor: .zero, source: .watchlist)
        #expect(coordinator.pendingRemoval?.id == tracked.id)

        await coordinator.commitPendingRemovalIfNeeded()

        #expect(repository.undoDuringRemoveResult == .some(nil))
        #expect(coordinator.pendingRemoval == nil)
        #expect(try await repository.contains(showID: tracked.id) == false)
    }

    @Test("Deferred remove failure keeps the show and exposes a generic error")
    func removeFailureExposesErrorAndLeavesShowPersisted() async throws {
        let repository = FailingRemoveRepository()
        let analytics = RecordingAnalyticsService()
        let coordinator = WatchlistPendingRemoval(repository: repository, analytics: analytics)
        try await repository.add(sampleShow)
        let tracked = try #require((try await repository.all()).first)

        var outcomes: [PendingRemovalOutcome] = []
        coordinator.addOutcomeHandler { outcomes.append($0) }
        coordinator.requestRemoval(tracked, anchor: .zero, source: .watchlist)
        await coordinator.commitPendingRemovalIfNeeded()

        #expect(try await repository.contains(showID: tracked.id))
        #expect(outcomes == [.failed(showID: tracked.id)])
        #expect(coordinator.pendingRemoval == nil)
        #expect(coordinator.removalErrorMessage == WatchlistTracking.updateFailedMessage)
        #expect(
            analytics.events.contains {
                if case .nonFatalError(_, let context) = $0 {
                    return context == "watchlist_remove"
                }
                return false
            }
        )
        #expect(
            analytics.events.contains {
                if case .watchlistRemoved = $0 { return true }
                return false
            } == false
        )
    }

    @Test(
        "Timer expiry still removes when the repository checks cancellation",
        .timeLimit(.minutes(1)))
    func timerExpiryRemovesShowWithCancellationAwareRepository() async throws {
        let repository = CancellationCheckingRemoveRepository()
        let analytics = RecordingAnalyticsService()
        let coordinator = WatchlistPendingRemoval(repository: repository, analytics: analytics)
        coordinator.undoWindowSecondsOverride = 0.05
        try await repository.add(sampleShow)
        let tracked = try #require((try await repository.all()).first)

        var outcomes: [PendingRemovalOutcome] = []
        coordinator.addOutcomeHandler { outcomes.append($0) }
        coordinator.requestRemoval(tracked, anchor: .zero, source: .watchlist)

        // The undo timer commits on its own task, emitting the outcome after the
        // remove is saved; wait for that outcome rather than a fixed time.
        try await waitUntil { coordinator.lastOutcome != nil }

        #expect(try await repository.contains(showID: tracked.id) == false)
        #expect(coordinator.pendingRemoval == nil)
        #expect(outcomes == [.committed(showID: tracked.id)])
        #expect(
            analytics.events.contains {
                if case .watchlistRemoved(let source, let showID) = $0 {
                    return source == .watchlist && showID == tracked.id
                }
                return false
            }
        )
    }

    @Test("Cancelling an explicit commit task still finishes persistence")
    func cancelledCommitTaskStillPersistsRemoval() async throws {
        let repository = GatedCancellationAwareRemoveRepository()
        let analytics = RecordingAnalyticsService()
        let coordinator = WatchlistPendingRemoval(repository: repository, analytics: analytics)
        try await repository.add(sampleShow)
        let tracked = try #require((try await repository.all()).first)

        var outcomes: [PendingRemovalOutcome] = []
        coordinator.addOutcomeHandler { outcomes.append($0) }
        coordinator.requestRemoval(tracked, anchor: .zero, source: .watchlist)

        let commitTask = Task {
            await coordinator.commitPendingRemovalIfNeeded()
        }
        await repository.waitUntilRemoveBegan()
        commitTask.cancel()
        repository.resumeRemove()
        await commitTask.value

        #expect(try await repository.contains(showID: tracked.id) == false)
        #expect(outcomes == [.committed(showID: tracked.id)])
        #expect(coordinator.pendingRemoval == nil)
        #expect(coordinator.removalErrorMessage == nil)
        #expect(
            analytics.events.contains {
                if case .watchlistRemoved(let source, let showID) = $0 {
                    return source == .watchlist && showID == tracked.id
                }
                return false
            }
        )
    }
}

/// Invokes an undo probe while suspended inside `remove`, so tests can observe
/// whether undo is still accepted after commit has begun.
@MainActor
private final class UndoDuringRemoveRepository: WatchlistRepository {
    private var shows: [Int: TrackedShow] = [:]
    var undoProbe: (() async -> TrackedShow?)?
    /// `nil` if `remove` never ran; `.some(nil)` if undo returned nil; `.some(show)` if undo restored.
    private(set) var undoDuringRemoveResult: TrackedShow??

    func all() async throws -> [TrackedShow] {
        shows.values.sorted { $0.dateAdded > $1.dateAdded }
    }

    func trackedShow(showID: Int) async throws -> TrackedShow? {
        shows[showID]
    }

    func trackedShowIDs() async throws -> Set<Int> {
        Set(shows.keys)
    }

    func contains(showID: Int) async throws -> Bool {
        shows[showID] != nil
    }

    func add(_ show: Show) async throws {
        guard shows[show.id] == nil else { return }
        shows[show.id] = TrackedShow(from: show)
    }

    func remove(showID: Int) async throws {
        undoDuringRemoveResult = .some(await undoProbe?())
        shows.removeValue(forKey: showID)
    }

    func updateAfterRefresh(_ tracked: TrackedShow) async throws {
        shows[tracked.id] = tracked
    }

    func setPaused(_ isPaused: Bool, showIDs: Set<Int>) async throws {
        for id in showIDs { shows[id]?.isPaused = isPaused }
    }
}

/// Stores shows normally but throws from `remove`.
@MainActor
private final class FailingRemoveRepository: WatchlistRepository {
    private var shows: [Int: TrackedShow] = [:]

    func all() async throws -> [TrackedShow] {
        shows.values.sorted { $0.dateAdded > $1.dateAdded }
    }

    func trackedShow(showID: Int) async throws -> TrackedShow? {
        shows[showID]
    }

    func trackedShowIDs() async throws -> Set<Int> {
        Set(shows.keys)
    }

    func contains(showID: Int) async throws -> Bool {
        shows[showID] != nil
    }

    func add(_ show: Show) async throws {
        guard shows[show.id] == nil else { return }
        shows[show.id] = TrackedShow(from: show)
    }

    func remove(showID: Int) async throws {
        throw URLError(.cannotConnectToHost)
    }

    func updateAfterRefresh(_ tracked: TrackedShow) async throws {
        shows[tracked.id] = tracked
    }

    func setPaused(_ isPaused: Bool, showIDs: Set<Int>) async throws {
        for id in showIDs { shows[id]?.isPaused = isPaused }
    }
}

/// Removes shows only after checking task cancellation (and yielding so a
/// self-cancelled timer would be observed).
@MainActor
private final class CancellationCheckingRemoveRepository: WatchlistRepository {
    private var shows: [Int: TrackedShow] = [:]

    func all() async throws -> [TrackedShow] {
        shows.values.sorted { $0.dateAdded > $1.dateAdded }
    }

    func trackedShow(showID: Int) async throws -> TrackedShow? {
        shows[showID]
    }

    func trackedShowIDs() async throws -> Set<Int> {
        Set(shows.keys)
    }

    func contains(showID: Int) async throws -> Bool {
        shows[showID] != nil
    }

    func add(_ show: Show) async throws {
        guard shows[show.id] == nil else { return }
        shows[show.id] = TrackedShow(from: show)
    }

    func remove(showID: Int) async throws {
        try Task.checkCancellation()
        await Task.yield()
        try Task.checkCancellation()
        shows.removeValue(forKey: showID)
    }

    func updateAfterRefresh(_ tracked: TrackedShow) async throws {
        shows[tracked.id] = tracked
    }

    func setPaused(_ isPaused: Bool, showIDs: Set<Int>) async throws {
        for id in showIDs { shows[id]?.isPaused = isPaused }
    }
}

/// Suspends inside `remove` until released, then checks task cancellation.
@MainActor
private final class GatedCancellationAwareRemoveRepository: WatchlistRepository {
    private var shows: [Int: TrackedShow] = [:]
    private var removeBeganContinuation: CheckedContinuation<Void, Never>?
    private var removeGateContinuation: CheckedContinuation<Void, Never>?

    func waitUntilRemoveBegan() async {
        await withCheckedContinuation { continuation in
            if removeGateContinuation != nil {
                continuation.resume()
                return
            }
            removeBeganContinuation = continuation
        }
    }

    func resumeRemove() {
        removeGateContinuation?.resume()
        removeGateContinuation = nil
    }

    func all() async throws -> [TrackedShow] {
        shows.values.sorted { $0.dateAdded > $1.dateAdded }
    }

    func trackedShow(showID: Int) async throws -> TrackedShow? {
        shows[showID]
    }

    func trackedShowIDs() async throws -> Set<Int> {
        Set(shows.keys)
    }

    func contains(showID: Int) async throws -> Bool {
        shows[showID] != nil
    }

    func add(_ show: Show) async throws {
        guard shows[show.id] == nil else { return }
        shows[show.id] = TrackedShow(from: show)
    }

    func remove(showID: Int) async throws {
        removeBeganContinuation?.resume()
        removeBeganContinuation = nil
        await withCheckedContinuation { continuation in
            removeGateContinuation = continuation
        }
        try Task.checkCancellation()
        shows.removeValue(forKey: showID)
    }

    func updateAfterRefresh(_ tracked: TrackedShow) async throws {
        shows[tracked.id] = tracked
    }

    func setPaused(_ isPaused: Bool, showIDs: Set<Int>) async throws {
        for id in showIDs { shows[id]?.isPaused = isPaused }
    }
}
