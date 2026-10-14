//
//  ShowIDMappingRefreshServiceTests.swift
//  NextSeasonTests
//

import Foundation
import Synchronization
import Testing

@testable import NextSeason

struct ShowIDMappingRefreshServiceTests {
    private func makeDatabase() async throws -> (ShowIDMappingDatabase, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mapping-refresh-\(UUID().uuidString).sqlite")
        try ShowIDMappingDatabase.createEmptyDatabase(at: url)
        let database = try ShowIDMappingDatabase(preparedFileURL: url)
        return (database, url)
    }

    @Test("Pending updates sort by timestamp newest-first, not by show id")
    func pendingUpdatesSortByTimestamp() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        // Lower show id is newer; sorting by id desc would put 200 first incorrectly.
        let updates = [
            200: older,
            100: newer,
        ]

        let pending = ShowIDMappingRefreshService.pendingUpdates(
            from: updates,
            updatedAfter: nil,
            horizonAt: newer,
            resumeCursor: nil
        )

        #expect(pending.map(\.showID) == [100, 200])
        #expect(pending.map(\.updatedAt) == [newer, older])
    }

    @Test("Pending updates ignore changes newer than the sync horizon")
    func pendingUpdatesRespectHorizon() {
        let within = Date(timeIntervalSince1970: 1_000)
        let horizon = Date(timeIntervalSince1970: 2_000)
        let after = Date(timeIntervalSince1970: 3_000)
        let updates = [
            1: within,
            2: horizon,
            3: after,
        ]

        let pending = ShowIDMappingRefreshService.pendingUpdates(
            from: updates,
            updatedAfter: nil,
            horizonAt: horizon,
            resumeCursor: nil
        )

        #expect(pending.map(\.showID) == [2, 1])
    }

    @Test("Resume cursor keeps only updates older than the pause point")
    func pendingUpdatesRespectResumeCursor() {
        let t1 = Date(timeIntervalSince1970: 1_000)
        let t2 = Date(timeIntervalSince1970: 2_000)
        let t3 = Date(timeIntervalSince1970: 3_000)
        let updates = [
            1: t1,
            2: t2,
            3: t3,
        ]
        let cursor = ShowIDMappingResumeCursor(updatedAt: t3, showID: 3)

        let pending = ShowIDMappingRefreshService.pendingUpdates(
            from: updates,
            updatedAfter: nil,
            horizonAt: t3,
            resumeCursor: cursor
        )

        #expect(pending.map(\.showID) == [2, 1])
    }

    @Test("Pending updates ignore changes at or before the prior sync watermark")
    func pendingUpdatesRespectUpdatedAfter() {
        let watermark = Date(timeIntervalSince1970: 2_000)
        let before = Date(timeIntervalSince1970: 1_000)
        let after = Date(timeIntervalSince1970: 3_000)
        let updates = [
            1: before,
            2: watermark,
            3: after,
        ]

        let pending = ShowIDMappingRefreshService.pendingUpdates(
            from: updates,
            updatedAfter: watermark,
            horizonAt: after,
            resumeCursor: nil
        )

        #expect(pending.map(\.showID) == [3])
    }

    @Test("First refresh uses bundled generatedAt as the updates watermark")
    func firstRefreshUsesGeneratedAtWatermark() async throws {
        let (database, url) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }

        let generatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let now = Date(timeIntervalSince1970: 1_700_000_000 + 3_600)
        try await database.setGeneratedAt(generatedAt)

        let beforeGeneration = Date(timeIntervalSince1970: 1_699_999_000)
        let afterGeneration = Date(timeIntervalSince1970: 1_700_000_500)

        let tvMaze = RecordingIndexTVMazeService(
            updates: [
                10: beforeGeneration,
                20: afterGeneration,
            ],
            externalsByShowID: [
                10: 1_010,
                20: 1_020,
            ]
        )

        let refresh = ShowIDMappingRefreshService(
            database: database,
            tvMaze: tvMaze,
            now: { now },
            maxShowDetailFetchesPerRefresh: 10,
            requestPause: .zero
        )

        await refresh.refreshIfNeeded()

        #expect(await tvMaze.lastFilteredPeriod == .day)
        #expect(await tvMaze.fetchedShowIDs == [20])
        #expect(await database.tvMazeID(forTVDBID: 1_020) == 20)
        #expect(await database.tvMazeID(forTVDBID: 1_010) == nil)

        let metadata = try await database.metadata()
        #expect(
            metadata.lastSuccessfulSyncAt
                == now.addingTimeInterval(-TVMazeUpdatePeriod.propagationDelay))
    }

    @Test("Refresh persists TVMaze title and poster on the mapping")
    func refreshPersistsDisplayFields() async throws {
        let (database, url) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }

        let generatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let now = Date(timeIntervalSince1970: 1_700_000_000 + 3_600)
        try await database.setGeneratedAt(generatedAt)

        let poster = URL(
            string: "https://static.tvmaze.com/uploads/images/medium_portrait/9/9.jpg"
        )!
        let tvMaze = RecordingIndexTVMazeService(
            updates: [
                20: Date(timeIntervalSince1970: 1_700_000_500)
            ],
            externalsByShowID: [
                20: 1_020
            ],
            namesByShowID: [
                20: "Severance"
            ],
            posterURLsByShowID: [
                20: poster
            ]
        )

        let refresh = ShowIDMappingRefreshService(
            database: database,
            tvMaze: tvMaze,
            now: { now },
            maxShowDetailFetchesPerRefresh: 10,
            requestPause: .zero
        )

        await refresh.refreshIfNeeded()

        let record = try #require(await database.record(forTVDBID: 1_020))
        #expect(record.tvMazeID == 20)
        #expect(record.name == "Severance")
        #expect(record.posterMediumURL == poster)
    }

    @Test("No lastSuccessfulSyncAt and no generatedAt uses allUpdatedShows()")
    func missingWatermarksUseUnfilteredUpdates() async throws {
        let (database, url) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }

        let before = try await database.metadata()
        #expect(before.lastSuccessfulSyncAt == nil)
        #expect(before.generatedAt == nil)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let beforeHorizon = Date(timeIntervalSince1970: 1_699_999_000)
        let afterHorizon = Date(timeIntervalSince1970: 1_700_000_100)

        let tvMaze = RecordingIndexTVMazeService(
            updates: [
                10: beforeHorizon,
                20: afterHorizon,
            ],
            externalsByShowID: [
                10: 1_010,
                20: 1_020,
            ]
        )

        let refresh = ShowIDMappingRefreshService(
            database: database,
            tvMaze: tvMaze,
            now: { now },
            maxShowDetailFetchesPerRefresh: 10,
            requestPause: .zero
        )

        await refresh.refreshIfNeeded()

        #expect(await tvMaze.didFetchAllUpdatedShows)
        #expect(await tvMaze.lastFilteredPeriod == nil)
        #expect(await tvMaze.fetchedShowIDs == [10])
        #expect(await database.tvMazeID(forTVDBID: 1_010) == 10)
        #expect(await database.tvMazeID(forTVDBID: 1_020) == nil)

        let metadata = try await database.metadata()
        #expect(
            metadata.lastSuccessfulSyncAt
                == now.addingTimeInterval(-TVMazeUpdatePeriod.propagationDelay))
    }

    @Test("Long absence uses the unfiltered updates map and still applies local watermark")
    func longAbsenceUsesUnfilteredUpdates() async throws {
        let (database, url) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }

        let lastSync = Date(timeIntervalSince1970: 1_000_000_000)
        // Two months later: beyond TVMaze's since=month window.
        let horizon = Date(
            timeIntervalSince1970: 1_000_000_000 + (2 * TVMazeUpdatePeriod.monthWindow)
        )
        try await database.setLastSuccessfulSyncAt(lastSync)

        // Older than since=month can cover from `horizon`, but still after lastSync.
        let oldChange = Date(timeIntervalSince1970: 1_000_000_000 + 7 * 86_400)
        let recentChange = Date(
            timeIntervalSince1970: 1_000_000_000 + TVMazeUpdatePeriod.monthWindow + 7 * 86_400
        )
        let alreadySynced = lastSync

        let tvMaze = RecordingIndexTVMazeService(
            updates: [
                10: oldChange,
                20: recentChange,
                30: alreadySynced,
            ],
            externalsByShowID: [
                10: 1_010,
                20: 1_020,
                30: 1_030,
            ]
        )

        let refresh = ShowIDMappingRefreshService(
            database: database,
            tvMaze: tvMaze,
            now: { horizon },
            maxShowDetailFetchesPerRefresh: 10,
            requestPause: .zero
        )

        await refresh.refreshIfNeeded()

        #expect(await tvMaze.didFetchAllUpdatedShows)
        #expect(await tvMaze.lastFilteredPeriod == nil)
        #expect(await tvMaze.fetchedShowIDs == [20, 10])
        #expect(await database.tvMazeID(forTVDBID: 1_010) == 10)
        #expect(await database.tvMazeID(forTVDBID: 1_020) == 20)
        #expect(await database.tvMazeID(forTVDBID: 1_030) == nil)

        let metadata = try await database.metadata()
        #expect(
            metadata.lastSuccessfulSyncAt
                == horizon.addingTimeInterval(-TVMazeUpdatePeriod.propagationDelay))
    }

    @Test("Capped update pass stores a resume cursor and does not mark sync complete")
    func cappedPassIsResumable() async throws {
        let (database, url) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }

        let syncStart = Date(timeIntervalSince1970: 1_700_000_000)
        let tNewer = Date(timeIntervalSince1970: 3_000)
        let tMid = Date(timeIntervalSince1970: 2_000)
        let tOlder = Date(timeIntervalSince1970: 1_000)
        let tvMaze = RecordingIndexTVMazeService(
            updates: [
                10: tNewer,
                20: tMid,
                30: tOlder,
            ],
            externalsByShowID: [
                10: 1_010,
                20: 1_020,
                30: 1_030,
            ]
        )

        let refresh = ShowIDMappingRefreshService(
            database: database,
            tvMaze: tvMaze,
            now: { syncStart },
            maxShowDetailFetchesPerRefresh: 2,
            requestPause: .zero
        )

        await refresh.refreshIfNeeded()

        let metadataAfterFirst = try await database.metadata()
        #expect(metadataAfterFirst.lastSuccessfulSyncAt == nil)
        #expect(metadataAfterFirst.syncHorizonAt == syncStart)
        let cursor = try #require(metadataAfterFirst.updatesResumeCursor)
        #expect(cursor.showID == 20)
        #expect(cursor.updatedAt == tMid)
        #expect(await tvMaze.fetchedShowIDs == [10, 20])
        #expect(await database.tvMazeID(forTVDBID: 1_010) == 10)
        #expect(await database.tvMazeID(forTVDBID: 1_020) == 20)
        #expect(await database.tvMazeID(forTVDBID: 1_030) == nil)

        await refresh.refreshIfNeeded()

        let metadataAfterSecond = try await database.metadata()
        #expect(metadataAfterSecond.updatesResumeCursor == nil)
        #expect(metadataAfterSecond.syncHorizonAt == nil)
        // Commit the original horizon, not a later wall-clock time,
        // less TVMaze's propagation margin.
        #expect(
            metadataAfterSecond.lastSuccessfulSyncAt
                == syncStart.addingTimeInterval(-TVMazeUpdatePeriod.propagationDelay))
        #expect(await tvMaze.fetchedShowIDs == [10, 20, 30])
        #expect(await database.tvMazeID(forTVDBID: 1_030) == 30)
    }

    @Test("Mid-drain updates after the horizon are deferred to the next sync")
    func midDrainUpdatesAreNotSkippedForever() async throws {
        let (database, url) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }

        let syncStart = Date(timeIntervalSince1970: 1_700_000_000)
        let nextSyncNow = Date(
            timeIntervalSince1970: 1_700_000_000
                + ShowIDMappingRefreshService.refreshInterval + 1
        )

        let tNewer = Date(timeIntervalSince1970: 3_000)
        let tOlder = Date(timeIntervalSince1970: 1_000)
        let midDrainUpdate = Date(timeIntervalSince1970: 1_700_000_100)

        // Pass 1 consumes syncStart for the horizon. Pass 2 reuses the stored
        // horizon (no clock read). Pass 3 reads nextSyncNow twice: once for the
        // weekly-interval check and once when opening a new horizon.
        let clock = SyncClock(dates: [syncStart, nextSyncNow, nextSyncNow])
        let tvMaze = RecordingIndexTVMazeService(
            updates: [
                10: tNewer,
                20: tOlder,
            ],
            externalsByShowID: [
                10: 1_010,
                20: 1_020,
                99: 1_099,
            ]
        )

        let refresh = ShowIDMappingRefreshService(
            database: database,
            tvMaze: tvMaze,
            now: { clock.next() },
            maxShowDetailFetchesPerRefresh: 1,
            requestPause: .zero
        )

        await refresh.refreshIfNeeded()
        #expect(await tvMaze.fetchedShowIDs == [10])
        let afterFirst = try await database.metadata()
        #expect(afterFirst.syncHorizonAt == syncStart)
        #expect(afterFirst.lastSuccessfulSyncAt == nil)

        // A show updates after the sync horizon while we still have backlog.
        await tvMaze.setUpdates([
            10: tNewer,
            20: tOlder,
            99: midDrainUpdate,
        ])

        await refresh.refreshIfNeeded()
        let afterSecond = try await database.metadata()
        #expect(afterSecond.syncHorizonAt == nil)
        #expect(
            afterSecond.lastSuccessfulSyncAt
                == syncStart.addingTimeInterval(-TVMazeUpdatePeriod.propagationDelay))
        #expect(await tvMaze.fetchedShowIDs == [10, 20])
        #expect(await database.tvMazeID(forTVDBID: 1_099) == nil)

        // Next weekly window: only the deferred change remains outstanding.
        await tvMaze.setUpdates([99: midDrainUpdate])

        await refresh.refreshIfNeeded()
        #expect(await tvMaze.fetchedShowIDs.contains(99))
        #expect(await database.tvMazeID(forTVDBID: 1_099) == 99)
        let afterThird = try await database.metadata()
        #expect(
            afterThird.lastSuccessfulSyncAt
                == nextSyncNow.addingTimeInterval(-TVMazeUpdatePeriod.propagationDelay))
        #expect(afterThird.syncHorizonAt == nil)
    }

    // MARK: R08: request window chosen at request time

    /// Review R08 reproduction: a capped sync started with a one-hour gap kept
    /// requesting `day` when it resumed two days later. TVMaze's rolling window
    /// no longer contained the backlog, so the sync completed without it.
    @Test("A capped sync resumed two days later requests a wider window and keeps its backlog")
    func resumedSyncWidensWindow() async throws {
        let (database, url) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }

        // First launch: the bundled snapshot's generation time is the watermark,
        // so a sync can start an hour after it.
        let lastSync = Date(timeIntervalSince1970: 1_700_000_000)
        try await database.setGeneratedAt(lastSync)
        let syncStart = lastSync.addingTimeInterval(3_600)
        let clock = DateBox(syncStart)
        let tvMaze = RecordingIndexTVMazeService(
            updates: [
                10: lastSync.addingTimeInterval(600),
                20: lastSync.addingTimeInterval(1_200),
                30: lastSync.addingTimeInterval(1_800),
            ],
            externalsByShowID: [10: 1_010, 20: 1_020, 30: 1_030],
            serverNow: { clock.date }
        )
        let refresh = ShowIDMappingRefreshService(
            database: database, tvMaze: tvMaze, now: { clock.date },
            maxShowDetailFetchesPerRefresh: 1, requestPause: .zero)

        await refresh.refreshIfNeeded()
        #expect(await tvMaze.lastFilteredPeriod == .day)

        clock.date = syncStart.addingTimeInterval(2 * 86_400)
        await refresh.refreshIfNeeded()
        #expect(await tvMaze.lastFilteredPeriod == .week, "Window chosen from request time")
        await refresh.refreshIfNeeded()

        #expect(await database.tvMazeID(forTVDBID: 1_010) == 10)
        #expect(await database.tvMazeID(forTVDBID: 1_020) == 20)
        #expect(await database.tvMazeID(forTVDBID: 1_030) == 30)
        let metadata = try await database.metadata()
        #expect(metadata.lastSuccessfulSyncAt == syncStart.addingTimeInterval(-3_600))
    }

    @Test("A sync resumed more than 28 days after its last success uses the full map")
    func longResumeUsesFullMap() async throws {
        let (database, url) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }

        let lastSync = Date(timeIntervalSince1970: 1_700_000_000)
        try await database.setGeneratedAt(lastSync)
        let clock = DateBox(lastSync.addingTimeInterval(3_600))
        let tvMaze = RecordingIndexTVMazeService(
            updates: [
                10: lastSync.addingTimeInterval(600), 20: lastSync.addingTimeInterval(1_200),
            ],
            externalsByShowID: [10: 1_010, 20: 1_020],
            serverNow: { clock.date }
        )
        let refresh = ShowIDMappingRefreshService(
            database: database, tvMaze: tvMaze, now: { clock.date },
            maxShowDetailFetchesPerRefresh: 1, requestPause: .zero)

        await refresh.refreshIfNeeded()
        #expect(await tvMaze.didFetchAllUpdatedShows == false)

        clock.date = lastSync.addingTimeInterval(29 * 86_400)
        await refresh.refreshIfNeeded()

        #expect(await tvMaze.didFetchAllUpdatedShows)
        #expect(await database.tvMazeID(forTVDBID: 1_010) == 10)
        #expect(await database.tvMazeID(forTVDBID: 1_020) == 20)
    }

    @Test("A change not yet published when a sync started is applied by the next sync")
    func unpublishedChangeIsAppliedNextSync() async throws {
        let (database, url) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }

        let syncStart = Date(timeIntervalSince1970: 1_700_000_000)
        try await database.setLastSuccessfulSyncAt(syncStart.addingTimeInterval(-8 * 86_400))
        let clock = DateBox(syncStart)
        // Show 40 changed 30 minutes before the sync, but TVMaze's cache does not
        // list it yet.
        let lateChange = syncStart.addingTimeInterval(-1_800)
        let tvMaze = RecordingIndexTVMazeService(
            updates: [:], externalsByShowID: [40: 1_040])
        let refresh = ShowIDMappingRefreshService(
            database: database, tvMaze: tvMaze, now: { clock.date },
            maxShowDetailFetchesPerRefresh: 10, requestPause: .zero)

        await refresh.refreshIfNeeded()
        #expect(await database.tvMazeID(forTVDBID: 1_040) == nil)

        // A week later the change is published, still dated before the old horizon.
        await tvMaze.setUpdates([40: lateChange])
        clock.date = syncStart.addingTimeInterval(ShowIDMappingRefreshService.refreshInterval + 1)
        await refresh.refreshIfNeeded()

        #expect(await database.tvMazeID(forTVDBID: 1_040) == 40, "Product decision 2: margin")
    }

    /// Settable clock shared by the service and the fake's rolling window.
    private final class DateBox: Sendable {
        private let state: Mutex<Date>
        init(_ date: Date) { state = Mutex(date) }
        var date: Date {
            get { state.withLock { $0 } }
            set { state.withLock { $0 = newValue } }
        }
    }

    private final class SyncClock: Sendable {
        private struct State {
            var dates: [Date]
            var index = 0
        }

        private let state: Mutex<State>

        init(dates: [Date]) {
            state = Mutex(State(dates: dates))
        }

        func next() -> Date {
            state.withLock { state in
                let date = state.dates[min(state.index, state.dates.count - 1)]
                state.index += 1
                return date
            }
        }
    }

    private actor RecordingIndexTVMazeService: TVMazeService {
        private var updates: [Int: Date]
        let externalsByShowID: [Int: Int]
        let namesByShowID: [Int: String]
        let posterURLsByShowID: [Int: URL]
        private(set) var fetchedShowIDs: [Int] = []
        private(set) var didFetchAllUpdatedShows = false
        private(set) var lastFilteredPeriod: TVMazeUpdatePeriod?
        /// When set, `since=` behaves like TVMaze's rolling window ending at this
        /// time: changes older than the period are left out.
        let serverNow: (@Sendable () -> Date)?

        init(
            updates: [Int: Date],
            externalsByShowID: [Int: Int],
            namesByShowID: [Int: String] = [:],
            posterURLsByShowID: [Int: URL] = [:],
            serverNow: (@Sendable () -> Date)? = nil
        ) {
            self.updates = updates
            self.externalsByShowID = externalsByShowID
            self.namesByShowID = namesByShowID
            self.posterURLsByShowID = posterURLsByShowID
            self.serverNow = serverNow
        }

        func setUpdates(_ updates: [Int: Date]) {
            self.updates = updates
        }

        func searchShows(matching query: String) async throws -> [Show] { [] }
        func lookupShow(theTVDBID: Int) async throws -> Show { throw TVMazeError.notFound }
        func show(id: Int, bypassCache: Bool) async throws -> Show { throw TVMazeError.notFound }

        func updatedShows(since period: TVMazeUpdatePeriod) async throws -> [Int: Date] {
            lastFilteredPeriod = period
            guard let serverNow else { return updates }
            let length: TimeInterval =
                switch period {
                case .day: 86_400
                case .week: 604_800
                case .month: TVMazeUpdatePeriod.monthWindow
                }
            let windowStart = serverNow().addingTimeInterval(-length)
            return updates.filter { $0.value >= windowStart }
        }

        func allUpdatedShows() async throws -> [Int: Date] {
            didFetchAllUpdatedShows = true
            return updates
        }

        func showsIndex(page: Int) async throws -> [ShowIndexEntryData] {
            throw TVMazeError.notFound
        }

        func showIndexEntry(id: Int) async throws -> ShowIndexEntryData {
            fetchedShowIDs.append(id)
            let posterURL = posterURLsByShowID[id]
            return ShowIndexEntryData(
                id: id,
                name: namesByShowID[id],
                image: posterURL.map { ImageData(medium: $0.absoluteString, original: nil) },
                externals: ShowExternalsData(thetvdb: externalsByShowID[id])
            )
        }
    }
}
