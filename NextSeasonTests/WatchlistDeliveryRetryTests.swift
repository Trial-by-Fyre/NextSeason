//
//  WatchlistDeliveryRetryTests.swift
//  NextSeasonTests
//

import Foundation
import SwiftData
import Synchronization
import Testing
import UserNotifications

@testable import NextSeason

// Review finding R03: a notification used to be recorded as sent before the
// system accepted it, so a scheduling failure lost it for good. Scenario numbers
// refer to the R03 section of
// Documentation/Reviews/2026-10-12-r03-r13-behavior-matrix.md (revision 4).

// MARK: - Fixtures

@MainActor
private final class RetryTVMaze: TVMazeService {
    var updates: [Int: Date] = [:]
    var shows: [Int: Show] = [:]
    private(set) var fetchedShowIDs: [Int] = []

    @MainActor func searchShows(matching query: String) async throws -> [Show] { [] }

    @MainActor func lookupShow(theTVDBID: Int) async throws -> Show {
        throw TVMazeError.notFound
    }

    @MainActor func show(id: Int, bypassCache: Bool) async throws -> Show {
        fetchedShowIDs.append(id)
        guard let show = shows[id] else { throw TVMazeError.notFound }
        return show
    }

    @MainActor func updatedShows(since period: TVMazeUpdatePeriod) async throws -> [Int: Date] {
        updates
    }

    @MainActor func allUpdatedShows() async throws -> [Int: Date] { updates }
}

/// Returns scripted outcomes (then `.accepted`) and can hold one delivery until
/// released. The held delivery's outcome is taken after release, so a test can
/// decide it while the attempt is in flight.
@MainActor
private final class ScriptedDelivery: NotificationDelivering {
    var outcomes: [NotificationDeliveryOutcome] = []
    /// When true, the next delivery waits until `release()`.
    var holdNext = false
    private(set) var attempts: [SeasonNotificationContent] = []
    private(set) var accepted: [SeasonNotificationContent] = []
    private var held: CheckedContinuation<Void, Never>?
    private var heldStarted: CheckedContinuation<Void, Never>?

    func deliver(_ content: SeasonNotificationContent) async -> NotificationDeliveryOutcome {
        attempts.append(content)
        if holdNext {
            holdNext = false
            await withCheckedContinuation { continuation in
                held = continuation
                heldStarted?.resume()
                heldStarted = nil
            }
        }
        let outcome = outcomes.isEmpty ? .accepted : outcomes.removeFirst()
        if outcome == .accepted { accepted.append(content) }
        return outcome
    }

    func waitUntilHeld() async {
        if held != nil { return }
        await withCheckedContinuation { heldStarted = $0 }
    }

    func release() {
        held?.resume()
        held = nil
    }
}

private let now = TVMazeDate.dateOnly("2026-06-14")!
private let day: TimeInterval = 86_400

/// Next-season shapes the fixtures produce at `now`.
private enum Shape {
    case undated, scheduled, rescheduled, airing, ended, returning
}

/// Season 1 aired in 2024; season 2 (if any) decides the status.
private func show(_ id: Int, _ shape: Shape, updatedAt: Date = now - day) -> Show {
    var seasons = [
        Season(
            id: id * 10 + 1, number: 1, premiereDate: TVMazeDate.dateOnly("2024-01-10"),
            endDate: TVMazeDate.dateOnly("2024-03-10"), episodeOrder: 8)
    ]
    let seasonTwoPremiere: String?? =
        switch shape {
        case .undated: .some(nil)
        case .scheduled: "2026-09-01"
        case .rescheduled: "2026-10-01"
        case .airing: "2026-06-01"
        case .ended, .returning: nil
        }
    if let premiere = seasonTwoPremiere {
        seasons.append(
            Season(
                id: id * 10 + 2, number: 2, premiereDate: TVMazeDate.dateOnly(premiere),
                endDate: nil, episodeOrder: nil))
    }
    return Show(
        id: id, name: "Show \(id)", tvMazeURL: nil, summaryHTML: nil,
        posterMediumURL: nil, posterOriginalURL: nil,
        status: shape == .ended ? .ended : .running,
        premiered: TVMazeDate.dateOnly("2024-01-10"), ended: nil, network: nil,
        genres: [], averageRuntime: nil, seasons: seasons, nextEpisode: nil,
        updatedAt: updatedAt)
}

private func status(_ shape: Shape) -> NextSeasonStatus {
    NextSeasonCalculator.status(for: show(1, shape), at: now)
}

private func signature(_ shape: Shape) -> String {
    StatusChangeDetector.signature(for: status(shape))
}

/// A saved row already told about season 2 being announced without a date (A).
private func row(_ id: Int) -> TrackedShow {
    var row = TrackedShow(from: show(id, .undated, updatedAt: now - 10 * day), at: now - 10 * day)
    row.lastNotifiedSignature = signature(.undated)
    row.dateAdded = now - Double(60 + id) * day
    return row
}

@MainActor
private func isolatedDefaults() -> UserDefaults {
    let suiteName = "WatchlistDeliveryRetryTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    // Recent coverage, so ordinary refreshes ask for a day window.
    defaults.set(
        (now - 3 * 3_600).timeIntervalSinceReferenceDate,
        forKey: WatchlistRefreshService.updatesCoveredThroughKey)
    return defaults
}

@MainActor
private func makeContainer(url: URL? = nil) throws -> ModelContainer {
    try NextSeasonModelContainer.make(
        configuration: url.map { ModelConfiguration(url: $0) }
            ?? ModelConfiguration("retry-\(UUID().uuidString)", isStoredInMemoryOnly: true))
}

@MainActor
private func seed(_ rows: [TrackedShow], in container: ModelContainer) throws {
    let context = ModelContext(container)
    for row in rows { context.insert(try TrackedShowEntity(tracked: row)) }
    try context.save()
}

/// A temporary directory for an on-disk store, removed by the caller.
private func storeDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("retry-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

/// One refresh service over a repository, with fakes and isolated defaults.
@MainActor
private struct Harness {
    let tvMaze = RetryTVMaze()
    let delivery: ScriptedDelivery
    let analytics = RecordingAnalyticsService()
    let repository: any WatchlistRepository
    let refresh: WatchlistRefreshService

    init(
        _ repository: any WatchlistRepository, defaults: UserDefaults = isolatedDefaults(),
        notifications: (any NotificationDelivering)? = nil
    ) {
        let delivery = ScriptedDelivery()
        self.delivery = delivery
        self.repository = repository
        refresh = WatchlistRefreshService(
            tvMaze: tvMaze, repository: repository, notifications: notifications ?? delivery,
            analytics: analytics, userDefaults: defaults, clock: { now })
    }

    init(rows: [TrackedShow]) {
        self.init(InMemoryWatchlistRepository(seed: rows))
    }

    /// TVMaze now reports `shape`, as a server change newer than the last one.
    func report(_ id: Int, _ shape: Shape, at updatedAt: Date = now - day) {
        tvMaze.shows[id] = show(id, shape, updatedAt: updatedAt)
        tvMaze.updates[id] = updatedAt
    }

    /// An ordinary (non-forced) refresh, as from the foreground or background.
    @discardableResult
    func poll(deliver: Bool = true) async -> WatchlistRefreshOutcome? {
        await refresh.refreshAll(deliverNotifications: deliver)
    }

    func saved(_ id: Int) async throws -> TrackedShow {
        try #require(try await repository.trackedShow(showID: id))
    }

    func fetches(of id: Int) -> Int { tvMaze.fetchedShowIDs.filter { $0 == id }.count }
}

@MainActor
private func nonFatalCount(_ analytics: RecordingAnalyticsService, _ context: String) -> Int {
    analytics.events.filter {
        if case .nonFatalError(_, let eventContext) = $0 { return eventContext == context }
        return false
    }.count
}

// MARK: - Outcomes and retry

@MainActor
struct WatchlistDeliveryRetryTests {
    @Test("An accepted notification stays recorded and is not repeated")
    func acceptedIsRecorded() async throws {
        let harness = Harness(rows: [row(1)])
        harness.report(1, .scheduled)

        let outcome = await harness.poll()
        await harness.poll()

        #expect(harness.delivery.accepted.map(\.showID) == [1], "Scenario 1")
        #expect(harness.delivery.attempts.count == 1)
        let saved = try await harness.saved(1)
        #expect(saved.lastNotifiedSignature == signature(.scheduled))
        #expect(saved.pendingChangeSignature == nil)
        #expect(outcome?.notificationDecision.hasPrefix("Notification scheduled for") == true)
    }

    /// Product decision 3: the review harness's reproduction (`FAILED_DELIVERY
    /// firstAttempt=true retryAttempt=false signatureAlreadyRecorded=true`).
    @Test("A failed delivery is retried on the next poll and then recorded")
    func failedThenAccepted() async throws {
        let harness = Harness(rows: [row(1)])
        harness.report(1, .scheduled)
        harness.delivery.outcomes = [.failed]

        let first = await harness.poll()

        let afterFailure = try await harness.saved(1)
        #expect(afterFailure.lastNotifiedSignature == signature(.undated), "Restored")
        #expect(afterFailure.pendingChangeSignature == signature(.scheduled))
        #expect(first?.notificationDecision.contains("will retry next refresh") == true)

        // No new TVMaze change: the pending signature alone brings it back.
        await harness.poll()
        await harness.poll()

        #expect(harness.delivery.attempts.count == 2, "Scenario 2: exactly one retry")
        #expect(harness.delivery.accepted.map(\.showID) == [1])
        let saved = try await harness.saved(1)
        #expect(saved.lastNotifiedSignature == signature(.scheduled))
        #expect(saved.pendingChangeSignature == nil)
    }

    @Test("A delivery that keeps failing is retried on every poll")
    func keepsFailing() async throws {
        let harness = Harness(rows: [row(1)])
        harness.report(1, .scheduled)
        harness.delivery.outcomes = [.failed, .failed, .failed]

        for _ in 0..<3 { await harness.poll() }

        #expect(harness.delivery.attempts.count == 3, "Scenario 3: no cutoff")
        #expect(harness.delivery.accepted.isEmpty)
        #expect(try await harness.saved(1).pendingChangeSignature == signature(.scheduled))
    }

    @Test("A suppressed delivery is consumed and never replayed")
    func suppressedIsConsumed() async throws {
        let harness = Harness(rows: [row(1)])
        harness.report(1, .scheduled)
        harness.delivery.outcomes = [.suppressed]

        let outcome = await harness.poll()
        await harness.poll()

        #expect(harness.delivery.attempts.count == 1, "Scenario 4")
        let saved = try await harness.saved(1)
        #expect(saved.lastNotifiedSignature == signature(.scheduled))
        #expect(saved.pendingChangeSignature == nil)
        #expect(outcome?.notificationDecision.contains("alerts not permitted") == true)
    }

    @Test("An interactive refresh consumes a date-backed change without a retry")
    func interactiveDateBacked() async throws {
        let harness = Harness(rows: [row(1)])
        harness.report(1, .scheduled)

        let outcome = await harness.poll(deliver: false)

        #expect(harness.delivery.attempts.isEmpty, "Scenario 5")
        let saved = try await harness.saved(1)
        #expect(saved.lastNotifiedSignature == signature(.scheduled))
        #expect(saved.pendingChangeSignature == nil)
        #expect(outcome?.notificationDecision.contains("interactive refresh") == true)
    }

    @Test("An interactive refresh still records a first-seen soft change for confirmation")
    func interactiveSoftChange() async throws {
        let harness = Harness(rows: [row(1)])
        harness.report(1, .ended)

        await harness.poll(deliver: false)

        #expect(harness.delivery.attempts.isEmpty, "Scenario 5")
        #expect(try await harness.saved(1).pendingChangeSignature == signature(.ended))
    }

    @Test("A date-backed change after a failure notifies on first sight")
    func supersededByDateBacked() async throws {
        let harness = Harness(rows: [row(1)])
        harness.report(1, .scheduled)
        harness.delivery.outcomes = [.failed]
        await harness.poll()

        harness.report(1, .airing, at: now - day / 2)
        await harness.poll()

        #expect(harness.delivery.accepted.map(\.status) == [status(.airing)], "Scenario 6")
        #expect(try await harness.saved(1).pendingChangeSignature == nil)
    }

    @Test("A soft change after a failure waits for confirmation")
    func supersededBySoftChange() async throws {
        let harness = Harness(rows: [row(1)])
        harness.report(1, .scheduled)
        harness.delivery.outcomes = [.failed]
        await harness.poll()

        harness.report(1, .ended, at: now - day / 2)
        await harness.poll()
        #expect(harness.delivery.attempts.count == 1, "Scenario 6: not immediate")
        #expect(try await harness.saved(1).pendingChangeSignature == signature(.ended))

        await harness.poll()
        #expect(harness.delivery.accepted.map(\.status) == [status(.ended)])
    }

    @Test("A change that is not meaningful clears the pending retry")
    func supersededByMinorChange() async throws {
        let harness = Harness(rows: [row(1)])
        harness.report(1, .scheduled)
        harness.delivery.outcomes = [.failed]
        await harness.poll()

        harness.report(1, .returning, at: now - day / 2)
        await harness.poll()
        await harness.poll()

        #expect(harness.delivery.attempts.count == 1, "Scenario 6")
        #expect(try await harness.saved(1).pendingChangeSignature == nil)
    }

    @Test("Reverting to the announced state before the retry sends nothing")
    func revertsToAnnounced() async throws {
        let harness = Harness(rows: [row(1)])
        harness.report(1, .scheduled)
        harness.delivery.outcomes = [.failed]
        await harness.poll()

        harness.report(1, .undated, at: now - day / 2)
        await harness.poll()
        await harness.poll()

        #expect(harness.delivery.attempts.count == 1, "Scenario 7")
        let saved = try await harness.saved(1)
        #expect(saved.pendingChangeSignature == nil)
        #expect(saved.lastNotifiedSignature == signature(.undated))
    }

    @Test("A soft change that fails after confirmation is pending again and then delivered")
    func confirmedSoftChangeFails() async throws {
        let harness = Harness(rows: [row(1)])
        harness.report(1, .ended)
        harness.delivery.outcomes = [.failed]

        await harness.poll()  // first sight: pending
        await harness.poll()  // confirmed: delivery fails
        #expect(try await harness.saved(1).pendingChangeSignature == signature(.ended))
        await harness.poll()  // no TVMaze change, refetched for the retry

        #expect(harness.fetches(of: 1) == 3, "Scenario 19")
        #expect(harness.delivery.accepted.map(\.status) == [status(.ended)])
    }

    @Test("Permission turned off after a failure consumes the retry for good")
    func suppressedAfterFailure() async throws {
        let harness = Harness(rows: [row(1)])
        harness.report(1, .scheduled)
        harness.delivery.outcomes = [.failed, .suppressed]

        for _ in 0..<3 { await harness.poll() }

        #expect(harness.delivery.attempts.count == 2, "Scenario 13: no replay")
        #expect(harness.delivery.accepted.isEmpty)
        #expect(try await harness.saved(1).pendingChangeSignature == nil)
    }

    @Test("An unknown outcome is never retried")
    func unknownIsNotRetried() async throws {
        let harness = Harness(rows: [row(1)])
        harness.report(1, .scheduled)
        harness.delivery.outcomes = [.unknown]

        let outcome = await harness.poll()
        await harness.poll()

        #expect(harness.delivery.attempts.count == 1, "Scenario 15.4")
        let saved = try await harness.saved(1)
        #expect(saved.lastNotifiedSignature == signature(.scheduled))
        #expect(saved.pendingChangeSignature == nil)
        #expect(outcome?.notificationDecision.contains("unknown") == true)
    }

    /// Ties the outcome mapping to the refresh: the real service, its scheduling
    /// seam failing once, and no DEBUG assertion on the expected failure.
    @Test("Through NotificationService, one rejected request is retried and then accepted")
    func retryThroughNotificationService() async throws {
        @MainActor final class Scheduler {
            var failuresLeft = 1
            var requests: [String] = []
        }
        let scheduler = Scheduler()
        let service = NotificationService(
            scheduler: .init(
                alertsPermitted: true,
                add: { request in
                    scheduler.requests.append(request.identifier)
                    if scheduler.failuresLeft > 0 {
                        scheduler.failuresLeft -= 1
                        throw NSError(domain: UNErrorDomain, code: 1)
                    }
                }),
            analytics: RecordingAnalyticsService())
        let harness = Harness(
            InMemoryWatchlistRepository(seed: [row(1)]), notifications: service)
        harness.report(1, .scheduled)

        await harness.poll()
        await harness.poll()
        await harness.poll()

        let identifier = "show-1-\(signature(.scheduled))"
        #expect(scheduler.requests == [identifier, identifier], "Scenarios 2 and 21")
        #expect(try await harness.saved(1).lastNotifiedSignature == signature(.scheduled))
    }
}

// MARK: - Overlapping refreshes and user actions

@MainActor
struct WatchlistDeliveryOverlapTests {
    @Test("A second refresh skips a show whose delivery is in flight and handles the others")
    func secondRefreshSkipsBusyShow() async throws {
        let harness = Harness(rows: [row(1), row(2)])
        harness.report(1, .scheduled)
        harness.delivery.holdNext = true

        let first = Task { await harness.refresh.refreshAll(onlyShowIDs: [1]) }
        await harness.delivery.waitUntilHeld()
        harness.report(2, .returning)
        await harness.poll()

        #expect(harness.fetches(of: 1) == 1, "Scenario 8: no decision for the busy show")
        #expect(harness.fetches(of: 2) == 1, "Other shows proceed")
        #expect(try await harness.saved(2).nextSeason == status(.returning))
        harness.delivery.release()
        _ = await first.value
        #expect(harness.delivery.accepted.map(\.showID) == [1])
    }

    @Test("A newer soft change seen after a failure is announced on confirmation")
    func softChangeAfterInterleavedFailure() async throws {
        let harness = Harness(rows: [row(1)])
        harness.report(1, .scheduled)
        harness.delivery.holdNext = true

        let first = Task { await harness.poll() }
        await harness.delivery.waitUntilHeld()
        // The reviewer's interleaving: refresh 2 sees soft C while B is in flight.
        harness.report(1, .ended, at: now - day / 2)
        await harness.poll()
        #expect(harness.fetches(of: 1) == 1, "Scenario 9: refresh 2 held back")
        harness.delivery.outcomes = [.failed]
        harness.delivery.release()
        _ = await first.value

        await harness.poll()  // sees C: pending
        await harness.poll()  // confirms C

        #expect(harness.delivery.accepted.map(\.status) == [status(.ended)])
        #expect(try await harness.saved(1).pendingChangeSignature == nil)
    }

    @Test("An unchanged observation during a failing delivery keeps the retry")
    func unchangedObservationKeepsRetry() async throws {
        let harness = Harness(rows: [row(1)])
        harness.report(1, .scheduled)
        harness.delivery.holdNext = true

        let first = Task { await harness.poll() }
        await harness.delivery.waitUntilHeld()
        await harness.poll()  // TVMaze still reports B
        #expect(harness.fetches(of: 1) == 1, "Scenario 12: skipped, nothing written")
        harness.delivery.outcomes = [.failed]
        harness.delivery.release()
        _ = await first.value

        await harness.poll()

        #expect(harness.delivery.accepted.map(\.status) == [status(.scheduled)])
    }

    /// Revision 4 change 1: the catch-up skips the busy show and the next refresh
    /// baselines it. Every decision uses the same fixed time.
    @Test("A catch-up during a failing delivery delays the silent baseline; B is never announced")
    func catchUpDuringFailingDelivery() async throws {
        let harness = Harness(rows: [row(1)])
        harness.report(1, .scheduled)
        harness.delivery.holdNext = true

        let first = Task { await harness.poll() }
        await harness.delivery.waitUntilHeld()
        // Paused and resumed while B is in flight.
        let saved = try await harness.saved(1)
        try await harness.repository.setPaused(true, showIDs: [1])
        harness.refresh.markForCatchUp([saved])
        try await harness.repository.setPaused(false, showIDs: [1])
        await harness.refresh.catchUp(showIDs: [1])
        #expect(harness.fetches(of: 1) == 1, "The catch-up skipped the busy show")
        #expect(harness.refresh.catchUpShowIDs == [1], "Its mark stays")

        harness.delivery.outcomes = [.failed]
        harness.delivery.release()
        _ = await first.value
        #expect(try await harness.saved(1).pendingChangeSignature == signature(.scheduled))

        await harness.poll()

        #expect(harness.delivery.accepted.isEmpty, "Scenario 10")
        #expect(harness.delivery.attempts.count == 1)
        let repaired = try await harness.saved(1)
        #expect(repaired.pendingChangeSignature == nil, "The baseline cleared the retry")
        #expect(repaired.lastNotifiedSignature == signature(.scheduled))
        #expect(harness.refresh.catchUpShowIDs.isEmpty)
    }

    @Test("A show removed during a failing delivery is not restored")
    func removedDuringDelivery() async throws {
        let harness = Harness(rows: [row(1)])
        harness.report(1, .scheduled)
        harness.delivery.holdNext = true

        let first = Task { await harness.poll() }
        await harness.delivery.waitUntilHeld()
        try await harness.repository.remove(showID: 1)
        harness.delivery.outcomes = [.failed]
        harness.delivery.release()
        _ = await first.value

        #expect(try await harness.repository.trackedShow(showID: 1) == nil, "Scenario 18")
    }

    @Test("A show paused during a failing delivery drops the alert, and resume baselines it")
    func pausedDuringDelivery() async throws {
        let harness = Harness(rows: [row(1)])
        harness.report(1, .scheduled)
        harness.delivery.holdNext = true

        let first = Task { await harness.poll() }
        await harness.delivery.waitUntilHeld()
        try await harness.repository.setPaused(true, showIDs: [1])
        harness.delivery.outcomes = [.failed]
        harness.delivery.release()
        _ = await first.value
        #expect(try await harness.saved(1).pendingChangeSignature == nil, "Scenario 18")

        harness.refresh.markForCatchUp([try await harness.saved(1)])
        try await harness.repository.setPaused(false, showIDs: [1])
        await harness.poll()

        #expect(harness.delivery.attempts.count == 1, "Dropped, not replayed")
        #expect(try await harness.saved(1).pendingChangeSignature == nil)
    }
}

// MARK: - SwiftData

@MainActor
struct WatchlistDeliveryRetryPersistenceTests {
    @Test("A show removed and added again during a failing delivery is a new row")
    func readdedDuringDelivery() async throws {
        let container = try makeContainer()
        try seed([row(1)], in: container)
        let harness = Harness(SwiftDataWatchlistRepository(context: ModelContext(container)))
        harness.report(1, .scheduled)
        harness.delivery.holdNext = true

        let first = Task { await harness.poll() }
        await harness.delivery.waitUntilHeld()
        try await harness.repository.remove(showID: 1)
        try await harness.repository.add(show(1, .scheduled))
        harness.delivery.outcomes = [.failed]
        harness.delivery.release()
        _ = await first.value

        let readded = try await harness.saved(1)
        #expect(readded.dateAdded != row(1).dateAdded)
        #expect(readded.pendingChangeSignature == nil, "Scenario 11: restore did nothing")
        #expect(readded.lastNotifiedSignature == nil)
    }

    @Test("A failed delivery's retry survives an app restart")
    func retrySurvivesRestart() async throws {
        let directory = try storeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("watchlist.store")
        let defaults = isolatedDefaults()

        do {
            let container = try makeContainer(url: url)
            try seed([row(1)], in: container)
            let first = Harness(
                SwiftDataWatchlistRepository(context: ModelContext(container)), defaults: defaults)
            first.report(1, .scheduled)
            first.delivery.outcomes = [.failed]
            await first.poll()
        }

        let relaunched = Harness(
            SwiftDataWatchlistRepository(context: ModelContext(try makeContainer(url: url))),
            defaults: defaults)
        relaunched.report(1, .scheduled)
        await relaunched.poll()

        #expect(relaunched.delivery.accepted.map(\.showID) == [1], "Scenario 16")
    }

    @Test("Termination after saving and before scheduling loses the alert")
    func terminationBeforeScheduling() async throws {
        let directory = try storeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("watchlist.store")

        // The state a refresh saves just before it schedules B.
        do {
            let container = try makeContainer(url: url)
            try seed([row(1)], in: container)
            let decision = StatusChangeDetector.evaluate(
                tracked: row(1), newStatus: status(.scheduled), at: now)
            _ = try #require(decision.notification, "The saved decision is one that notifies")
            try await SwiftDataWatchlistRepository(context: ModelContext(container))
                .updateAfterRefresh(decision.tracked)
        }

        let relaunched = Harness(
            SwiftDataWatchlistRepository(context: ModelContext(try makeContainer(url: url))))
        relaunched.report(1, .scheduled)
        await relaunched.poll()

        #expect(relaunched.delivery.attempts.isEmpty, "Scenario 14: accepted loss")
    }

    @Test("A failed restore write loses the retry, is logged, and is rolled back")
    func restoreWriteFails() async throws {
        struct SaveFailure: Error {}
        let container = try makeContainer()
        try seed([row(1)], in: container)
        var saves = 0
        // The refresh write succeeds; the restore that follows it fails.
        let repository = SwiftDataWatchlistRepository(
            context: ModelContext(container),
            save: { context in
                saves += 1
                if saves == 2 { throw SaveFailure() }
                try context.save()
            })
        let harness = Harness(repository)
        harness.report(1, .scheduled)
        harness.delivery.outcomes = [.failed]

        let outcome = await harness.poll()

        #expect(nonFatalCount(harness.analytics, "watchlist_restore_undelivered") == 1)
        #expect(outcome?.notificationDecision.contains("not retried") == true)
        let stored = try #require(
            try ModelContext(container).fetch(FetchDescriptor<TrackedShowEntity>()).first)
        #expect(stored.pendingChangeSignature == nil, "Scenario 17: nothing lingers")
        #expect(try await harness.saved(1).pendingChangeSignature == nil)
        await harness.poll()
        #expect(harness.delivery.attempts.count == 1, "The retry is lost")
    }

    @Test("The restore runs only while the row still holds the attempt's decision")
    func restoreGuard() async throws {
        let container = try makeContainer()
        try seed([row(1)], in: container)
        let repository = SwiftDataWatchlistRepository(context: ModelContext(container))
        let attempt = StatusChangeDetector.evaluate(
            tracked: row(1), newStatus: status(.scheduled), at: now
        ).tracked
        try await repository.updateAfterRefresh(attempt)

        var newer = attempt
        newer.nextSeason = status(.rescheduled)
        newer.lastNotifiedSignature = signature(.rescheduled)
        try await repository.updateAfterRefresh(newer)
        #expect(
            try await repository.restoreUndeliveredNotification(
                attempt, previousLastNotifiedSignature: signature(.undated)) == false,
            "Invariant 3: never overwrites a newer decision")

        try await repository.updateAfterRefresh(attempt)
        #expect(
            try await repository.restoreUndeliveredNotification(
                attempt, previousLastNotifiedSignature: signature(.undated)))
        let restored = try #require(try await repository.trackedShow(showID: 1))
        #expect(restored.lastNotifiedSignature == signature(.undated))
        #expect(restored.pendingChangeSignature == signature(.scheduled))
    }
}

// MARK: - Diagnostics delivery paths

@MainActor
private final class FixedOutcomeNotifications: NotificationManaging {
    var outcome: NotificationDeliveryOutcome
    private(set) var immediateDeliveries = 0
    private(set) var delayedRequests: [String] = []
    /// Every attempted notification, immediate or delayed.
    private(set) var contents: [SeasonNotificationContent] = []

    init(_ outcome: NotificationDeliveryOutcome) { self.outcome = outcome }

    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func needsAuthorizationPrompt() async -> Bool { false }
    func deferAuthorizationPrompt() {}
    func isDenied() async -> Bool { false }
    func canDeliverVisibleAlerts() async -> Bool { true }
    func openNotificationSettings() {}
    func enableNotificationsFromSettingsEntryPoint() async {}
    func requestAuthorizationIfNeeded() async -> Bool { true }
    func deliver(_ content: SeasonNotificationContent) async -> NotificationDeliveryOutcome {
        immediateDeliveries += 1
        contents.append(content)
        return outcome
    }
    func deliver(_ content: SeasonNotificationContent, requestIdentifier: String) async
        -> NotificationDeliveryOutcome
    { outcome }
    func deliverAfterDelay(
        _ content: SeasonNotificationContent,
        requestIdentifier: String,
        delay: TimeInterval
    ) async -> NotificationDeliveryOutcome {
        delayedRequests.append(requestIdentifier)
        contents.append(content)
        return outcome
    }
}

/// A clock that moves forward a minute on every reading, as real time would
/// between Diagnostics taps.
private final class TickingClock: Sendable {
    private let minutes = Mutex(0)
    var date: Date {
        let elapsed = minutes.withLock { count in
            count += 1
            return count
        }
        return now + Double(elapsed) * 60
    }
}

@MainActor
struct DiagnosticsDeliveryOutcomeTests {
    @Test(
        "The delayed pipeline delivery passes the real outcome on",
        arguments: [NotificationDeliveryOutcome.accepted, .suppressed, .failed, .unknown])
    func delayedDeliveryPassesOutcome(_ outcome: NotificationDeliveryOutcome) async {
        let service = FixedOutcomeNotifications(outcome)
        let delivering = DiagnosticsDelayedNotificationDelivering(service: service, delay: 5)

        let result = await delivering.deliver(
            SeasonNotificationContent(showID: 1, showName: "Show 1", status: .airing(season: 2)))

        #expect(result == outcome, "Scenario 22")
        #expect(service.delayedRequests.count == 1)
    }

    /// Acceptance review finding (P2): the runner used to reset after reporting
    /// "will retry", discarding the pending alert.
    @Test("A failed simulated step is retried by the next step, then the scenario resets")
    func simulatedStepRetriesFailedAlert() async {
        let notifications = FixedOutcomeNotifications(.failed)
        let clock = TickingClock()
        let runner = DiagnosticsSimulatedUpdateRunner(
            notifications: notifications, diagnostics: BetaRefreshDiagnostics(),
            analytics: RecordingAnalyticsService(), clock: { clock.date })

        _ = await runner.runNextStep()  // baseline
        let failed = await runner.runNextStep()  // updated: delivery fails
        #expect(failed.contains("will retry next refresh"), "Scenario 23")
        #expect(notifications.immediateDeliveries == 1)

        notifications.outcome = .accepted
        let retried = await runner.runNextStep()

        #expect(notifications.immediateDeliveries == 2, "Scenario 22: retried")
        #expect(retried.contains("Notification scheduled"))
        let statuses = notifications.contents.map(\.status)
        #expect(statuses.count == 2 && statuses[0] == statuses[1], "The same alert, not a new one")
        #expect(runner.dataPhaseLabel.contains("Baseline"), "Reset after the retry succeeded")
    }

    @Test("A failed delayed pipeline is retried by the next run instead of starting over")
    func delayedPipelineRetriesFailedAlert() async {
        let notifications = FixedOutcomeNotifications(.failed)
        let clock = TickingClock()
        let runner = DiagnosticsSimulatedUpdateRunner(
            notifications: notifications, diagnostics: BetaRefreshDiagnostics(),
            analytics: RecordingAnalyticsService(), clock: { clock.date })

        let failed = await runner.runDelayedNewSeasonNotification(delayRange: 1...1)
        #expect(failed.contains("will retry next refresh"))
        notifications.outcome = .accepted
        let retried = await runner.runDelayedNewSeasonNotification(delayRange: 1...1)

        #expect(notifications.delayedRequests.count == 2, "Scenario 22: retried")
        #expect(retried.contains("Notification scheduled"))
        let statuses = notifications.contents.map(\.status)
        #expect(statuses.count == 2 && statuses[0] == statuses[1], "The same alert, not a new one")
    }
}
