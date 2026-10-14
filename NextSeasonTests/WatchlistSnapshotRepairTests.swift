//
//  WatchlistSnapshotRepairTests.swift
//  NextSeasonTests
//

import Foundation
import SwiftData
import Testing

@testable import NextSeason

// Review finding R13: one undecodable next-season snapshot used to make the whole
// watchlist unreadable. Scenario numbers refer to the R13 section of
// Documentation/Reviews/2026-10-12-r03-r13-behavior-matrix.md (revision 4).

// MARK: - Fixtures

@MainActor
private final class RepairTVMaze: TVMazeService {
    var updates: [Int: Date] = [:]
    var shows: [Int: Show] = [:]
    var failsUpdates = false
    var failingShowIDs: Set<Int> = []
    private(set) var fetchedShowIDs: [Int] = []

    @MainActor func searchShows(matching query: String) async throws -> [Show] { [] }

    @MainActor func lookupShow(theTVDBID: Int) async throws -> Show {
        throw TVMazeError.notFound
    }

    @MainActor func show(id: Int, bypassCache: Bool) async throws -> Show {
        fetchedShowIDs.append(id)
        if failingShowIDs.contains(id) { throw URLError(.timedOut) }
        guard let show = shows[id] else { throw TVMazeError.notFound }
        return show
    }

    @MainActor func updatedShows(since period: TVMazeUpdatePeriod) async throws -> [Int: Date] {
        if failsUpdates { throw URLError(.notConnectedToInternet) }
        return updates
    }

    @MainActor func allUpdatedShows() async throws -> [Int: Date] {
        if failsUpdates { throw URLError(.notConnectedToInternet) }
        return updates
    }
}

@MainActor
private final class RecordingNotifications: NotificationDelivering {
    private(set) var delivered: [SeasonNotificationContent] = []
    func deliver(_ content: SeasonNotificationContent) async { delivered.append(content) }
}

private let now = TVMazeDate.dateOnly("2026-06-14")!
private let day: TimeInterval = 86_400
private let garbage = Data("not-json".utf8)

/// The status TVMaze reports when a damaged row is repaired.
enum RepairedShowStatus: CaseIterable, Sendable {
    case scheduled, airing, ended
}

/// Season 1 aired in 2024; season 2 decides the status.
private func show(_ id: Int, _ status: RepairedShowStatus = .scheduled) -> Show {
    let seasonTwoPremiere = status == .airing ? "2026-06-01" : "2026-09-01"
    return Show(
        id: id, name: "Show \(id)", tvMazeURL: nil, summaryHTML: nil,
        posterMediumURL: nil, posterOriginalURL: nil,
        status: status == .ended ? .ended : .running,
        premiered: TVMazeDate.dateOnly("2024-01-10"), ended: nil, network: nil,
        genres: [], averageRuntime: nil,
        seasons: [
            Season(
                id: id * 10 + 1, number: 1, premiereDate: TVMazeDate.dateOnly("2024-01-10"),
                endDate: TVMazeDate.dateOnly("2024-03-10"), episodeOrder: 8),
            Season(
                id: id * 10 + 2, number: 2,
                premiereDate: status == .ended ? nil : TVMazeDate.dateOnly(seasonTwoPremiere),
                endDate: nil, episodeOrder: nil),
        ],
        nextEpisode: nil, updatedAt: now - day)
}

/// A saved row last refreshed 30 days ago, already told "returning, no season yet",
/// so any of the real statuses above would be news if evaluated normally.
private func row(_ id: Int, paused: Bool = false) -> TrackedShow {
    var row = TrackedShow(from: show(id), at: now - 30 * day)
    row.nextSeason = .returningNoSeasonYet
    row.lastNotifiedSignature = StatusChangeDetector.signature(for: .returningNoSeasonYet)
    row.sourceUpdatedAt = now - 30 * day
    row.lastCheckedAt = now - 30 * day
    row.dateAdded = now - Double(60 + id) * day
    row.isPaused = paused
    return row
}

private func isolatedDefaults() -> UserDefaults {
    let suiteName = "WatchlistSnapshotRepairTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

/// A store seeded with `rows`, with the snapshots of `damaged` overwritten by
/// bytes that cannot decode. `url` makes it an on-disk store.
@MainActor
private func seededContainer(
    _ rows: [TrackedShow], damaged: Set<Int>, url: URL? = nil
) throws -> ModelContainer {
    let configuration =
        url.map { ModelConfiguration(url: $0) }
        ?? ModelConfiguration("repair-\(UUID().uuidString)", isStoredInMemoryOnly: true)
    let container = try NextSeasonModelContainer.make(configuration: configuration)
    let context = ModelContext(container)
    for row in rows {
        let entity = try TrackedShowEntity(tracked: row)
        if damaged.contains(row.id) { entity.nextSeasonSnapshot = garbage }
        context.insert(entity)
    }
    try context.save()
    return container
}

/// The snapshot bytes currently saved for a show, read through a fresh context.
@MainActor
private func savedSnapshot(_ id: Int, in container: ModelContainer) throws -> Data? {
    try ModelContext(container).fetch(FetchDescriptor<TrackedShowEntity>())
        .first { $0.tvMazeID == id }?.nextSeasonSnapshot
}

@MainActor
private func damageEvents(_ analytics: RecordingAnalyticsService) -> Int {
    analytics.events.filter {
        if case .nonFatalError(_, let context) = $0 {
            return context == "watchlist_snapshot_damaged"
        }
        return false
    }.count
}

/// The SwiftData repository and refresh service, sharing one defaults suite as in
/// production. Coverage is recent, so the refresh asks for a `day` window.
@MainActor
private struct Harness {
    let container: ModelContainer
    let defaults: UserDefaults
    let tvMaze = RepairTVMaze()
    let notifications = RecordingNotifications()
    let analytics = RecordingAnalyticsService()
    let repository: SwiftDataWatchlistRepository
    let refresh: WatchlistRefreshService

    init(
        container: ModelContainer, defaults: UserDefaults = isolatedDefaults(),
        save: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.container = container
        self.defaults = defaults
        defaults.set(
            (now - 3_600 * 3).timeIntervalSinceReferenceDate,
            forKey: WatchlistRefreshService.updatesCoveredThroughKey)
        repository = SwiftDataWatchlistRepository(
            context: ModelContext(container), rowMarks: WatchlistRowMarks(userDefaults: defaults),
            analytics: analytics, save: save)
        refresh = WatchlistRefreshService(
            tvMaze: tvMaze, repository: repository, notifications: notifications,
            analytics: analytics, userDefaults: defaults, clock: { now })
    }

    var marks: WatchlistRowMarks { WatchlistRowMarks(userDefaults: defaults) }
}

// MARK: - Repository

@MainActor
struct WatchlistSnapshotRepairRepositoryTests {
    @Test("A damaged row no longer hides the watchlist; it reads as status unknown")
    func mixedList() async throws {
        let harness = Harness(
            container: try seededContainer([row(1), row(2), row(3)], damaged: [2]))

        let rows = try await harness.repository.all()

        #expect(Set(rows.map(\.id)) == [1, 2, 3], "Scenario 1")
        #expect(rows.first { $0.id == 2 }?.nextSeason == .unknown)
        #expect(rows.first { $0.id == 1 }?.nextSeason == .returningNoSeasonYet)
    }

    enum ReadPath: CaseIterable, Sendable { case all, single, reactivation }

    @Test(
        "Every decoding path marks the row for repair before returning it",
        arguments: ReadPath.allCases)
    func everyPathMarksFirst(_ path: ReadPath) async throws {
        let damagedRow = row(1, paused: path == .reactivation)
        let harness = Harness(container: try seededContainer([damagedRow], damaged: [1]))

        switch path {
        case .all: _ = try await harness.repository.all()
        case .single:
            #expect(try await harness.repository.trackedShow(showID: 1)?.nextSeason == .unknown)
        case .reactivation: try await harness.repository.add(show(1))
        }

        let dateAdded = damagedRow.dateAdded.timeIntervalSinceReferenceDate
        #expect(harness.marks.catchUp[1] == dateAdded, "Scenario 2: marked")
        if path == .reactivation {
            // Reactivation rewrites the row as valid `.unknown`; the mark keeps the repair.
            #expect(try await harness.repository.activeShowIDs() == [1])
        } else {
            #expect(
                try savedSnapshot(1, in: harness.container) == garbage, "Reads never rewrite it")
        }
    }

    @Test("A valid unknown status is not treated as damage")
    func validUnknownIsNotDamage() async throws {
        var unknown = row(1)
        unknown.nextSeason = .unknown
        let harness = Harness(container: try seededContainer([unknown], damaged: []))

        _ = try await harness.repository.all()

        #expect(harness.marks.catchUp.isEmpty, "Scenario 3")
        #expect(damageEvents(harness.analytics) == 0)
    }

    @Test("Damage is reported once, even on a row that already had a resume mark")
    func damageReportedOnce() async throws {
        let damagedRow = row(1)
        let harness = Harness(container: try seededContainer([damagedRow], damaged: [1]))
        harness.marks.catchUp = [1: damagedRow.dateAdded.timeIntervalSinceReferenceDate]

        _ = try await harness.repository.all()
        _ = try await harness.repository.trackedShow(showID: 1)
        _ = try await harness.repository.all()

        #expect(damageEvents(harness.analytics) == 1, "Scenario 15 and clarification 2")
    }
}

// MARK: - Repair through refresh

@MainActor
struct WatchlistSnapshotRepairRefreshTests {
    @Test("The next refresh repairs a damaged row silently", arguments: RepairedShowStatus.allCases)
    func repairIsSilent(_ status: RepairedShowStatus) async throws {
        let harness = Harness(container: try seededContainer([row(1)], damaged: [1]))
        harness.tvMaze.shows[1] = show(1, status)  // no server change in the updates map
        _ = try await harness.repository.all()

        let outcome = await harness.refresh.refreshAll()

        #expect(harness.tvMaze.fetchedShowIDs == [1], "Scenario 4: fetched despite no change")
        #expect(harness.notifications.delivered.isEmpty, "Scenarios 5 and 6: no alert")
        let snapshot = try #require(try savedSnapshot(1, in: harness.container))
        #expect((try? JSONDecoder().decode(NextSeasonStatus.self, from: snapshot)) != nil)
        #expect(harness.marks.catchUp.isEmpty)
        #expect(harness.marks.damageReported.isEmpty)
        #expect(
            outcome?.notificationDecision.contains("Repaired") == true, "Scenario 15 diagnostics")
    }

    @Test("A failed updates request or show fetch leaves the repair pending")
    func networkFailureKeepsMark() async throws {
        for failsUpdates in [true, false] {
            let harness = Harness(container: try seededContainer([row(1)], damaged: [1]))
            harness.tvMaze.shows[1] = show(1)
            harness.tvMaze.failsUpdates = failsUpdates
            harness.tvMaze.failingShowIDs = failsUpdates ? [] : [1]
            _ = try await harness.repository.all()

            await harness.refresh.refreshAll()

            #expect(harness.marks.catchUp[1] != nil, "Scenario 7")
            #expect(try savedSnapshot(1, in: harness.container) == garbage)
            #expect(harness.notifications.delivered.isEmpty)
        }
    }

    @Test("A show TVMaze no longer has is marked stale, which repairs it")
    func notFoundRepairsAndClearsMark() async throws {
        let harness = Harness(container: try seededContainer([row(1)], damaged: [1]))
        _ = try await harness.repository.all()  // no show detail: fetch returns not found

        await harness.refresh.refreshAll()

        #expect(try await harness.repository.trackedShow(showID: 1)?.isStale == true)
        #expect(try savedSnapshot(1, in: harness.container) != garbage)
        #expect(harness.marks.catchUp.isEmpty, "Scenario 8: revision 4 change 2")
    }

    /// Acceptance review finding: a pending signature left on a damaged row forced
    /// a refetch on every refresh even after the 404 repair cleared the mark.
    @Test("After a 404 repair, a damaged row with a pending signature is not refetched")
    func notFoundRepairClearsPendingSignature() async throws {
        var pending = row(1)
        pending.pendingChangeSignature = StatusChangeDetector.signature(for: .ended)
        let harness = Harness(container: try seededContainer([pending], damaged: [1]))
        _ = try await harness.repository.all()

        await harness.refresh.refreshAll()  // not found: repairs the row
        #expect(harness.tvMaze.fetchedShowIDs == [1])
        #expect(try await harness.repository.trackedShow(showID: 1)?.pendingChangeSignature == nil)

        await harness.refresh.refreshAll()  // nothing changed

        #expect(harness.tvMaze.fetchedShowIDs == [1], "Not refetched")
    }

    @Test("A failed repair write keeps the damaged snapshot and the mark for a retry")
    func failedRepairWrite() async throws {
        final class FailOnce { var fail = true }
        let failOnce = FailOnce()
        let harness = Harness(
            container: try seededContainer([row(1)], damaged: [1]),
            save: { context in
                if failOnce.fail {
                    failOnce.fail = false
                    throw URLError(.cannotWriteToFile)
                }
                try context.save()
            })
        harness.tvMaze.shows[1] = show(1)
        _ = try await harness.repository.all()

        await harness.refresh.refreshAll()
        #expect(try savedSnapshot(1, in: harness.container) == garbage, "Scenario 9: rolled back")
        #expect(harness.marks.catchUp[1] != nil)

        await harness.refresh.refreshAll()
        #expect(try savedSnapshot(1, in: harness.container) != garbage)
        #expect(harness.marks.catchUp.isEmpty)
        #expect(harness.notifications.delivered.isEmpty)
    }

    @Test("A repair pending at restart still happens silently after relaunch")
    func repairSurvivesRestart() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("repair-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("watchlist.store")
        let defaults = isolatedDefaults()

        do {
            let first = Harness(
                container: try seededContainer([row(1)], damaged: [1], url: url), defaults: defaults
            )
            _ = try await first.repository.all()
        }

        let relaunched = Harness(
            container: try NextSeasonModelContainer.make(
                configuration: ModelConfiguration(url: url)),
            defaults: defaults)
        relaunched.tvMaze.shows[1] = show(1)
        await relaunched.refresh.refreshAll()

        #expect(relaunched.tvMaze.fetchedShowIDs == [1], "Scenario 10")
        #expect(relaunched.notifications.delivered.isEmpty)
        #expect(relaunched.marks.catchUp.isEmpty)
    }

    @Test("Delete and Undo before any refresh, then restart, still repairs silently")
    func undoThenRestart() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("repair-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("watchlist.store")
        let defaults = isolatedDefaults()

        do {
            let first = Harness(
                container: try seededContainer([row(1)], damaged: [1], url: url), defaults: defaults
            )
            let shown = try #require(try await first.repository.trackedShow(showID: 1))
            try await first.repository.remove(showID: 1)
            // Undo restores the removed row exactly as WatchlistPendingRemoval does.
            try await first.repository.add(Show(tracked: shown))
            try await first.repository.updateAfterRefresh(shown)
        }

        let relaunched = Harness(
            container: try NextSeasonModelContainer.make(
                configuration: ModelConfiguration(url: url)),
            defaults: defaults)
        relaunched.tvMaze.shows[1] = show(1)
        await relaunched.refresh.refreshAll()

        #expect(relaunched.tvMaze.fetchedShowIDs == [1], "Scenario 11: the mark survived Undo")
        #expect(relaunched.notifications.delivered.isEmpty)
        #expect(relaunched.marks.catchUp.isEmpty)
    }

    @Test("A paused damaged row keeps its mark and is not fetched")
    func pausedDamagedRow() async throws {
        let harness = Harness(container: try seededContainer([row(1, paused: true)], damaged: [1]))
        harness.tvMaze.shows[1] = show(1)

        #expect(try await harness.repository.all().first?.nextSeason == .unknown)
        await harness.refresh.refreshAll()

        #expect(harness.tvMaze.fetchedShowIDs.isEmpty, "Scenario 12")
        #expect(harness.marks.catchUp[1] != nil)
    }

    @Test("Removing a damaged row and adding the show again drops the old mark")
    func reAddedRowDropsMark() async throws {
        let harness = Harness(container: try seededContainer([row(1)], damaged: [1]))
        harness.tvMaze.shows[1] = show(1)
        _ = try await harness.repository.all()
        try await harness.repository.remove(showID: 1)
        try await harness.repository.add(show(1))  // a new row with a new dateAdded

        await harness.refresh.refreshAll()

        #expect(harness.marks.catchUp.isEmpty, "Scenario 13")
        #expect(harness.marks.damageReported.isEmpty)
    }

    @Test("Every row damaged: all are listed, then all are repaired")
    func everyRowDamaged() async throws {
        let harness = Harness(
            container: try seededContainer([row(1), row(2), row(3)], damaged: [1, 2, 3]))
        for id in 1...3 { harness.tvMaze.shows[id] = show(id) }

        #expect(try await harness.repository.all().count == 3, "Scenario 14")
        await harness.refresh.refreshAll()

        #expect(Set(harness.tvMaze.fetchedShowIDs) == [1, 2, 3])
        #expect(harness.notifications.delivered.isEmpty)
        #expect(harness.marks.catchUp.isEmpty)
    }

    @Test("A damaged row no longer blocks the refresh coverage watermark")
    func damagedRowDoesNotBlockCoverage() async throws {
        let harness = Harness(container: try seededContainer([row(1), row(2)], damaged: [2]))
        harness.tvMaze.shows[2] = show(2)

        await harness.refresh.refreshAll()

        let saved = harness.defaults.object(
            forKey: WatchlistRefreshService.updatesCoveredThroughKey)
        #expect(
            saved as? Double == (now - 3_600).timeIntervalSinceReferenceDate,
            "Revision 4 scenario 16")
    }
}
