//
//  WatchlistRefreshCoverageTests.swift
//  NextSeasonTests
//

import Foundation
import Testing

@testable import NextSeason

// Review finding R11: the coverage watermark that chooses the TVMaze updates
// window. Scenario numbers refer to
// Documentation/Reviews/2026-10-13-r08-r11-behavior-matrix.md.

// MARK: - Fixtures

/// TVMaze fake that records which updates endpoint was used and can fail or hold
/// individual show fetches. Main-actor isolated, so its state needs no locking.
@MainActor
private final class CoverageTVMaze: TVMazeService {
    var updates: [Int: Date] = [:]
    var shows: [Int: Show] = [:]
    var failsUpdates = false
    /// Show IDs whose next detail fetch throws a transient error (consumed once).
    var failNextFetchOf: Set<Int> = []
    /// When set, the first fetch of this show waits until `releaseHeldFetch()`.
    var holdFirstFetchOf: Int?
    private(set) var requests: [String] = []
    private(set) var fetchedShowIDs: [Int] = []
    private var held: CheckedContinuation<Void, Never>?
    private var heldStarted: CheckedContinuation<Void, Never>?

    /// Waits until the held fetch has started.
    func waitForHeldFetch() async {
        if held != nil { return }
        await withCheckedContinuation { heldStarted = $0 }
    }

    func releaseHeldFetch() {
        held?.resume()
        held = nil
    }

    @MainActor func searchShows(matching query: String) async throws -> [Show] { [] }

    @MainActor func lookupShow(theTVDBID: Int) async throws -> Show {
        throw TVMazeError.notFound
    }

    @MainActor func show(id: Int, bypassCache: Bool) async throws -> Show {
        fetchedShowIDs.append(id)
        if holdFirstFetchOf == id {
            holdFirstFetchOf = nil
            await withCheckedContinuation { continuation in
                held = continuation
                heldStarted?.resume()
                heldStarted = nil
            }
            // Like URLSession, a request whose task was cancelled meanwhile throws.
            try Task.checkCancellation()
        }
        if failNextFetchOf.remove(id) != nil { throw URLError(.timedOut) }
        guard let show = shows[id] else { throw TVMazeError.notFound }
        return show
    }

    @MainActor func updatedShows(since period: TVMazeUpdatePeriod) async throws -> [Int: Date] {
        requests.append(period.rawValue)
        if failsUpdates { throw URLError(.notConnectedToInternet) }
        return updates
    }

    @MainActor func allUpdatedShows() async throws -> [Int: Date] {
        requests.append("all")
        if failsUpdates { throw URLError(.notConnectedToInternet) }
        return updates
    }
}

/// In-memory repository that can fail refresh writes for chosen shows and run a
/// hook on each `all()` call (used to cancel during the coverage check).
@MainActor
private final class ScriptedRepository: WatchlistRepository {
    struct WriteFailure: Error {}

    private let base: InMemoryWatchlistRepository
    var failingWrites: Set<Int> = []
    var onAll: ((Int) -> Void)?
    private var allCalls = 0

    init(seed: [TrackedShow]) {
        base = InMemoryWatchlistRepository(seed: seed)
    }

    func all() async throws -> [TrackedShow] {
        allCalls += 1
        onAll?(allCalls)
        return try await base.all()
    }

    func trackedShow(showID: Int) async throws -> TrackedShow? {
        try await base.trackedShow(showID: showID)
    }

    func trackedShowIDs() async throws -> Set<Int> { try await base.trackedShowIDs() }
    func contains(showID: Int) async throws -> Bool { try await base.contains(showID: showID) }
    func add(_ show: Show) async throws { try await base.add(show) }
    func remove(showID: Int) async throws { try await base.remove(showID: showID) }

    func updateAfterRefresh(_ tracked: TrackedShow) async throws {
        if failingWrites.contains(tracked.id) { throw WriteFailure() }
        try await base.updateAfterRefresh(tracked)
    }

    func setPaused(_ isPaused: Bool, showIDs: Set<Int>) async throws {
        try await base.setPaused(isPaused, showIDs: showIDs)
    }
}

@MainActor
private final class RecordingNotifications: NotificationDelivering {
    private(set) var delivered: [SeasonNotificationContent] = []
    func deliver(_ content: SeasonNotificationContent) async { delivered.append(content) }
}

private final class ClockBox: @unchecked Sendable {
    var date: Date
    init(_ date: Date) { self.date = date }
}

private let now = TVMazeDate.dateOnly("2026-06-14")!
private let hour: TimeInterval = 3_600
private let day: TimeInterval = 86_400

/// Season 1 aired in 2024; season 2 is undated (`.announcedUndated`) unless a
/// premiere is given (`.scheduled` for a date after `now`).
private func show(_ id: Int, updatedAt: Date, seasonTwoPremiere: String? = nil) -> Show {
    Show(
        id: id, name: "Show \(id)", tvMazeURL: nil, summaryHTML: nil,
        posterMediumURL: nil, posterOriginalURL: nil, status: .running,
        premiered: TVMazeDate.dateOnly("2024-01-10"), ended: nil, network: nil,
        genres: [], averageRuntime: nil,
        seasons: [
            Season(
                id: id * 10 + 1, number: 1, premiereDate: TVMazeDate.dateOnly("2024-01-10"),
                endDate: TVMazeDate.dateOnly("2024-03-10"), episodeOrder: 8),
            Season(
                id: id * 10 + 2, number: 2,
                premiereDate: TVMazeDate.dateOnly(seasonTwoPremiere), endDate: nil,
                episodeOrder: nil),
        ],
        nextEpisode: nil, updatedAt: updatedAt)
}

/// A saved, already-announced `.announcedUndated` row last updated at `updatedAt`.
/// `.announcedUndated` is never rechecked on the calendar, so the updates map
/// alone decides whether it is fetched.
private func row(_ id: Int, updatedAt: Date) -> TrackedShow {
    var row = TrackedShow(from: show(id, updatedAt: updatedAt), at: updatedAt)
    row.nextSeason = .announcedUndated(season: 2)
    row.lastNotifiedSignature = StatusChangeDetector.signature(for: row.nextSeason)
    row.sourceUpdatedAt = updatedAt
    row.lastCheckedAt = updatedAt
    return row
}

@MainActor
private func isolatedDefaults(coveredThrough: Date? = nil) -> UserDefaults {
    let suiteName = "WatchlistRefreshCoverageTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    if let coveredThrough {
        defaults.set(
            coveredThrough.timeIntervalSinceReferenceDate,
            forKey: WatchlistRefreshService.updatesCoveredThroughKey)
    }
    return defaults
}

@MainActor
private func coveredThrough(_ defaults: UserDefaults) -> Date? {
    (defaults.object(forKey: WatchlistRefreshService.updatesCoveredThroughKey) as? Double)
        .map(Date.init(timeIntervalSinceReferenceDate:))
}

@MainActor
private func makeService(
    _ repository: any WatchlistRepository,
    _ tvMaze: CoverageTVMaze,
    _ defaults: UserDefaults,
    notifications: RecordingNotifications = RecordingNotifications(),
    clock: @escaping @Sendable () -> Date = { now }
) -> WatchlistRefreshService {
    WatchlistRefreshService(
        tvMaze: tvMaze, repository: repository, notifications: notifications,
        analytics: RecordingAnalyticsService(), userDefaults: defaults, clock: clock)
}

// MARK: - Tests

@MainActor
struct WatchlistRefreshCoverageTests {
    @Test("Regular use requests a day window and advances coverage to an hour before the request")
    func regularUseAdvances() async {
        let repository = ScriptedRepository(seed: [row(1, updatedAt: now - 30 * day)])
        let tvMaze = CoverageTVMaze()
        let defaults = isolatedDefaults(coveredThrough: now - 3 * hour)

        await makeService(repository, tvMaze, defaults).refreshAll()

        #expect(tvMaze.requests == ["day"])
        #expect(coveredThrough(defaults) == now - hour, "Scenarios 1 and 19: one-hour margin")
    }

    @Test("A long-stable show does not widen the window when coverage is recent")
    func stableRowKeepsSmallWindow() async {
        let repository = ScriptedRepository(seed: [row(1, updatedAt: now - 90 * day)])
        let tvMaze = CoverageTVMaze()
        let defaults = isolatedDefaults(coveredThrough: now - 12 * hour)

        await makeService(repository, tvMaze, defaults).refreshAll()

        #expect(tvMaze.requests == ["day"], "Scenario 2: lastCheckedAt no longer sets the window")
        #expect(tvMaze.fetchedShowIDs.isEmpty)
    }

    /// Review R11 reproduction: a 90-day-old undated row requested `month`, made no
    /// full-map request, and fetched no show detail.
    @Test("After a long absence the full map finds an old change, and the user is notified")
    func longAbsenceUsesFullMap() async throws {
        let repository = ScriptedRepository(seed: [row(1, updatedAt: now - 90 * day)])
        let tvMaze = CoverageTVMaze()
        tvMaze.updates = [1: now - 40 * day]
        tvMaze.shows[1] = show(1, updatedAt: now - 40 * day, seasonTwoPremiere: "2026-09-01")
        let defaults = isolatedDefaults(coveredThrough: now - 90 * day)
        let notifications = RecordingNotifications()

        await makeService(repository, tvMaze, defaults, notifications: notifications).refreshAll()

        #expect(tvMaze.requests == ["all"])
        #expect(tvMaze.fetchedShowIDs == [1])
        let saved = try #require(try await repository.trackedShow(showID: 1))
        let premiere = try #require(TVMazeDate.dateOnly("2026-09-01"))
        #expect(saved.nextSeason == .scheduled(season: 2, premiere: premiere))
        #expect(notifications.delivered.map(\.showID) == [1], "Product decision 1: notify normally")
        #expect(coveredThrough(defaults) == now - hour)
    }

    @Test(
        "The window follows the coverage gap",
        arguments: [
            (25 * day, "month"),
            (28 * day, "month"),
            (28 * day + 1, "all"),
        ]
    )
    func windowFollowsGap(gap: TimeInterval, request: String) async {
        let repository = ScriptedRepository(seed: [row(1, updatedAt: now - 90 * day)])
        let tvMaze = CoverageTVMaze()

        await makeService(repository, tvMaze, isolatedDefaults(coveredThrough: now - gap))
            .refreshAll()

        #expect(tvMaze.requests == [request], "Scenario 4")
    }

    @Test("The first refresh after upgrading has no watermark, so it uses the full map once")
    func firstRunUsesFullMapOnce() async {
        let repository = ScriptedRepository(seed: [row(1, updatedAt: now - 90 * day)])
        let tvMaze = CoverageTVMaze()
        let defaults = isolatedDefaults()

        let service = makeService(repository, tvMaze, defaults)
        await service.refreshAll()
        await service.refreshAll()

        #expect(tvMaze.requests == ["all", "day"], "Scenario 5")
    }

    @Test("A failed show fetch leaves coverage unchanged; other shows are still updated")
    func failedFetchKeepsCoverage() async throws {
        let repository = ScriptedRepository(seed: [
            row(1, updatedAt: now - 10 * day), row(2, updatedAt: now - 10 * day),
        ])
        let tvMaze = CoverageTVMaze()
        tvMaze.updates = [1: now - 2 * hour, 2: now - 2 * hour]
        tvMaze.shows = [
            1: show(1, updatedAt: now - 2 * hour), 2: show(2, updatedAt: now - 2 * hour),
        ]
        tvMaze.failNextFetchOf = [1]
        let defaults = isolatedDefaults(coveredThrough: now - 6 * hour)

        await makeService(repository, tvMaze, defaults).refreshAll()

        #expect(try await repository.trackedShow(showID: 2)?.sourceUpdatedAt == now - 2 * hour)
        #expect(coveredThrough(defaults) == now - 6 * hour, "Scenario 6")
    }

    @Test("A show missing from TVMaze counts as covered only if its stale flag was saved")
    func staleWriteMustSucceed() async throws {
        for writeFails in [true, false] {
            let repository = ScriptedRepository(seed: [row(1, updatedAt: now - 10 * day)])
            if writeFails { repository.failingWrites = [1] }
            let tvMaze = CoverageTVMaze()
            tvMaze.updates = [1: now - 2 * hour]  // no show detail: fetch returns not found
            let defaults = isolatedDefaults(coveredThrough: now - 6 * hour)

            await makeService(repository, tvMaze, defaults).refreshAll()

            if writeFails {
                #expect(
                    coveredThrough(defaults) == now - 6 * hour, "Scenario 7: ignored failed write")
            } else {
                #expect(try await repository.trackedShow(showID: 1)?.isStale == true)
                #expect(coveredThrough(defaults) == now - hour, "Scenario 8")
            }
        }
    }

    /// Acceptance review finding: a stale flag saved by an earlier pass, dated in
    /// the future because the clock later moved back, used to prove coverage.
    @Test("An earlier pass's future-dated stale flag does not prove coverage")
    func oldStaleFlagDoesNotCover() async {
        var stale = row(1, updatedAt: now - 10 * day)
        stale.isStale = true
        stale.lastCheckedAt = now + 5 * day
        let repository = ScriptedRepository(seed: [stale])
        let tvMaze = CoverageTVMaze()
        tvMaze.updates = [1: now - 2 * hour]  // a newer change than the saved row
        tvMaze.shows[1] = show(1, updatedAt: now - 2 * hour)
        tvMaze.failNextFetchOf = [1]
        let defaults = isolatedDefaults(coveredThrough: now - 6 * hour)

        await makeService(repository, tvMaze, defaults).refreshAll()

        #expect(coveredThrough(defaults) == now - 6 * hour, "Scenario 7b")
    }

    @Test("A skipped older response does not prove coverage")
    func olderResponseKeepsCoverage() async {
        let repository = ScriptedRepository(seed: [row(1, updatedAt: now - day)])
        let tvMaze = CoverageTVMaze()
        tvMaze.updates = [1: now - 2 * hour]
        tvMaze.shows[1] = show(1, updatedAt: now - 3 * day)  // older than the saved row
        let defaults = isolatedDefaults(coveredThrough: now - 6 * hour)

        await makeService(repository, tvMaze, defaults).refreshAll()

        #expect(coveredThrough(defaults) == now - 6 * hour, "Scenario 9")
    }

    @Test("Overlapping refreshes that both fail to apply a change leave coverage unchanged")
    func overlappingFailuresKeepCoverage() async {
        let repository = ScriptedRepository(seed: [row(1, updatedAt: now - 10 * day)])
        let tvMaze = CoverageTVMaze()
        tvMaze.updates = [1: now - 2 * hour]
        tvMaze.shows[1] = show(1, updatedAt: now - 2 * hour)
        tvMaze.holdFirstFetchOf = 1
        let defaults = isolatedDefaults(coveredThrough: now - 6 * hour)
        let owner = makeService(repository, tvMaze, defaults)
        let other = makeService(repository, tvMaze, defaults)

        let ownerPass = Task { await owner.refreshAll() }
        await tvMaze.waitForHeldFetch()
        // The other pass reaches the same show while the owning fetch is held.
        tvMaze.failNextFetchOf = [1]
        await other.refreshAll()
        #expect(coveredThrough(defaults) == now - 6 * hour, "The other pass did not cover the show")

        // The owning refresh then fails too.
        tvMaze.failNextFetchOf = [1]
        tvMaze.releaseHeldFetch()
        _ = await ownerPass.value

        #expect(coveredThrough(defaults) == now - 6 * hour, "Scenario 10")
    }

    @Test("A pass whose own fetch failed is covered by an overlapping pass's saved result")
    func overlappingSuccessCovers() async {
        let repository = ScriptedRepository(seed: [row(1, updatedAt: now - 10 * day)])
        let tvMaze = CoverageTVMaze()
        tvMaze.updates = [1: now - 2 * hour]
        tvMaze.shows[1] = show(1, updatedAt: now - 2 * hour)
        tvMaze.holdFirstFetchOf = 1
        let defaults = isolatedDefaults(coveredThrough: now - 6 * hour)

        let first = Task { await makeService(repository, tvMaze, defaults).refreshAll() }
        await tvMaze.waitForHeldFetch()
        // A pull-to-refresh saves the change but never advances coverage itself.
        await makeService(repository, tvMaze, defaults)
            .refreshAll(force: true, deliverNotifications: false)
        #expect(coveredThrough(defaults) == now - 6 * hour)
        tvMaze.failNextFetchOf = [1]
        tvMaze.releaseHeldFetch()
        _ = await first.value

        #expect(coveredThrough(defaults) == now - hour, "Scenario 11: persisted rows decide")
    }

    @Test("Cancellation just before the watermark write leaves it unchanged")
    func cancellationBeforeWrite() async {
        for cancels in [true, false] {
            let repository = ScriptedRepository(seed: [row(1, updatedAt: now - 10 * day)])
            // Call 1 loads the watchlist; call 2 is the coverage check.
            if cancels {
                repository.onAll = { call in
                    if call == 2 { withUnsafeCurrentTask { $0?.cancel() } }
                }
            }
            let tvMaze = CoverageTVMaze()  // nothing changed: every row is skipped
            let defaults = isolatedDefaults(coveredThrough: now - 6 * hour)
            let service = makeService(repository, tvMaze, defaults)

            _ = await Task { await service.refreshAll() }.value

            #expect(tvMaze.fetchedShowIDs.isEmpty)
            #expect(
                coveredThrough(defaults) == (cancels ? now - 6 * hour : now - hour), "Scenario 12")
        }
    }

    @Test("A pass cancelled mid-fetch, as when a background task expires, keeps coverage")
    func cancellationDuringFetch() async {
        let repository = ScriptedRepository(seed: [row(1, updatedAt: now - 10 * day)])
        let tvMaze = CoverageTVMaze()
        tvMaze.updates = [1: now - 2 * hour]
        tvMaze.shows[1] = show(1, updatedAt: now - 2 * hour)
        tvMaze.holdFirstFetchOf = 1
        let defaults = isolatedDefaults(coveredThrough: now - 6 * hour)
        let service = makeService(repository, tvMaze, defaults)

        let pass = Task { await service.refreshAll() }
        await tvMaze.waitForHeldFetch()
        pass.cancel()
        tvMaze.releaseHeldFetch()

        #expect(await pass.value == nil, "Cancelled passes report no outcome")
        #expect(coveredThrough(defaults) == now - 6 * hour, "Scenario 13")
    }

    @Test("A clock reset while a pass runs writes a future watermark that the next pass replaces")
    func clockResetDuringPassSelfCorrects() async {
        let repository = ScriptedRepository(seed: [row(1, updatedAt: now - 10 * day)])
        let tvMaze = CoverageTVMaze()
        tvMaze.updates = [1: now - 2 * hour]
        tvMaze.shows[1] = show(1, updatedAt: now - 2 * hour)
        tvMaze.holdFirstFetchOf = 1
        let clock = ClockBox(now)
        let defaults = isolatedDefaults(coveredThrough: now - 6 * hour)

        // The pass starts at `now`; the clock moves back three days while it is held.
        let pass = Task {
            await makeService(repository, tvMaze, defaults, clock: { clock.date }).refreshAll()
        }
        await tvMaze.waitForHeldFetch()
        clock.date = now - 3 * day
        tvMaze.releaseHeldFetch()
        _ = await pass.value
        #expect(coveredThrough(defaults) == now - hour, "Later than the reset clock")

        await makeService(repository, tvMaze, defaults, clock: { clock.date }).refreshAll()

        #expect(tvMaze.requests == ["day", "all"], "A future watermark forces the full map")
        #expect(coveredThrough(defaults) == now - 3 * day - hour, "Scenario 21")
    }

    @Test("A failed updates request leaves coverage unchanged")
    func failedUpdatesKeepCoverage() async {
        let repository = ScriptedRepository(seed: [row(1, updatedAt: now - 10 * day)])
        let tvMaze = CoverageTVMaze()
        tvMaze.failsUpdates = true
        let defaults = isolatedDefaults(coveredThrough: now - 40 * day)

        await makeService(repository, tvMaze, defaults).refreshAll()

        #expect(tvMaze.requests == ["all"])
        #expect(coveredThrough(defaults) == now - 40 * day, "Scenario 14")
    }

    @Test("Forced refreshes never advance coverage")
    func forcedRefreshesKeepCoverage() async {
        let repository = ScriptedRepository(seed: [row(1, updatedAt: now - 10 * day)])
        let tvMaze = CoverageTVMaze()
        tvMaze.shows[1] = show(1, updatedAt: now - 10 * day)
        let defaults = isolatedDefaults(coveredThrough: now - 6 * hour)
        let service = makeService(repository, tvMaze, defaults)

        await service.refreshAll(force: true, deliverNotifications: false)
        await service.catchUp(showIDs: [1])

        #expect(tvMaze.requests.isEmpty)
        #expect(coveredThrough(defaults) == now - 6 * hour, "Scenario 15")
    }

    @Test("An older pass finishing after a newer one keeps the newer watermark")
    func olderPassKeepsNewerWatermark() async {
        let repository = ScriptedRepository(seed: [row(1, updatedAt: now - 10 * day)])
        let tvMaze = CoverageTVMaze()
        tvMaze.updates = [1: now - 2 * hour]
        tvMaze.shows[1] = show(1, updatedAt: now - 2 * hour)
        tvMaze.holdFirstFetchOf = 1
        let clock = ClockBox(now)
        let defaults = isolatedDefaults(coveredThrough: now - 6 * hour)

        // Pass A starts at `now` and is held; pass B starts two hours later.
        let passA = Task {
            await makeService(repository, tvMaze, defaults, clock: { clock.date }).refreshAll()
        }
        await tvMaze.waitForHeldFetch()
        clock.date = now + 2 * hour
        await makeService(repository, tvMaze, defaults, clock: { clock.date }).refreshAll()
        #expect(coveredThrough(defaults) == now + hour)

        tvMaze.releaseHeldFetch()
        _ = await passA.value

        // B's watermark is later than A's request time but not later than the
        // clock, so it is not mistaken for a clock reset.
        #expect(coveredThrough(defaults) == now + hour, "Scenario 16")
    }

    @Test("A watermark later than the clock triggers the full map and is replaced")
    func futureWatermarkIsReplaced() async {
        let repository = ScriptedRepository(seed: [row(1, updatedAt: now - 10 * day)])
        let tvMaze = CoverageTVMaze()
        let defaults = isolatedDefaults(coveredThrough: now + 5 * day)

        await makeService(repository, tvMaze, defaults).refreshAll()

        #expect(tvMaze.requests == ["all"])
        #expect(coveredThrough(defaults) == now - hour, "Scenarios 20 and 21")
    }
}
