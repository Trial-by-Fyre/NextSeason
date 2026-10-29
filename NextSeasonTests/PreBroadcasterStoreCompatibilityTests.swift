//
//  PreBroadcasterStoreCompatibilityTests.swift
//  NextSeasonTests
//

import Foundation
import SwiftData
import Testing

@testable import NextSeason

/// `broadcasterName` was added to the V1 model in place (pre-release exception;
/// TestFlight testers are told to delete and reinstall). These tests pin what
/// happens to a store on either side of that change. It must never open empty
/// or with rows missing — that would look like a successful update while
/// silently losing the watchlist. Failing to open is safe (launch shows the
/// recovery screen) but is recorded as an issue, because it would change what
/// testers who skip the reinstall experience.
///
/// Observed on the simulator (October 2026): both directions open with every
/// row intact via SwiftData's inferred lightweight migration. That is not
/// documented behavior for an unchanged version identifier, so the supported
/// path remains delete and reinstall. Simulator evidence only; a store written
/// by a shipped TestFlight binary on device still needs a manual check.
@MainActor
struct PreBroadcasterStoreCompatibilityTests {
    @Test("A store written before broadcasterName opens with every row intact")
    func preBroadcasterStoreOpensComplete() throws {
        let storeURL = try makeStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent()) }
        let originals = [representativeTrackedShow(id: 1), representativeTrackedShow(id: 2)]
        try writeLegacyStore(at: storeURL, shows: originals)

        let container: ModelContainer
        do {
            container = try NextSeasonModelContainer.make(
                configuration: ModelConfiguration(url: storeURL))
        } catch {
            // Safe (launch shows the recovery screen), but a change from the
            // observed behavior: testers who skip the reinstall would now see
            // recovery. Fail so that change is noticed and the docs revisited.
            Issue.record("Pre-broadcaster store no longer opens: \(error)")
            return
        }

        let entities = try ModelContext(container)
            .fetch(FetchDescriptor<TrackedShowEntity>(sortBy: [SortDescriptor(\.tvMazeID)]))
        #expect(entities.count == originals.count)
        for (entity, original) in zip(entities, originals) {
            #expect(entity.broadcasterName == nil)
            #expect(try entity.toDomain() == original)
        }
    }

    @Test("Recovery export reads a store that has no broadcasterName column")
    func recoveryExportReadsPreBroadcasterStore() async throws {
        let storeURL = try makeStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent()) }
        try writeLegacyStore(
            at: storeURL,
            shows: [representativeTrackedShow(id: 1), representativeTrackedShow(id: 2)])

        let sqlite = WatchlistRecoveryExportReader.loadViaSQLite(storeURL: storeURL)
        #expect(sqlite.foundWatchlistTable)
        #expect(sqlite.shows.map(\.id).sorted() == [1, 2])

        let read = await WatchlistRecoveryExportReader.loadShows(storeURL: storeURL)
        #expect(read.storeWasReadable)
        #expect(read.shows.map(\.id).sorted() == [1, 2])
    }

    /// Downgrade: a tester reinstalls an earlier TestFlight build over a store
    /// that already has the column. Same invariant from the older model's side.
    @Test("A store with broadcasterName opens under the older model with every row")
    func downgradeOpensComplete() throws {
        let storeURL = try makeStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent()) }
        var current = representativeTrackedShow(id: 1)
        current.broadcasterName = "CBC Gem"
        try {
            let container = try NextSeasonModelContainer.make(
                configuration: ModelConfiguration(url: storeURL))
            let context = ModelContext(container)
            context.insert(try TrackedShowEntity(tracked: current))
            try context.save()
        }()

        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: Schema(versionedSchema: PreBroadcasterSchemaV1.self),
                migrationPlan: PreBroadcasterMigrationPlan.self,
                configurations: ModelConfiguration(url: storeURL))
        } catch {
            // Same reasoning as above, for a tester who installs an older build.
            Issue.record("Older model no longer opens a store with broadcasterName: \(error)")
            return
        }
        let entities = try ModelContext(container)
            .fetch(FetchDescriptor<PreBroadcasterSchemaV1.TrackedShowEntity>())
        #expect(entities.map(\.tvMazeID) == [1])
        #expect(entities.map(\.name) == [current.name])
    }

    // MARK: - Helpers

    private func makeStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pre-broadcaster-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("default.store")
    }

    /// Writes rows the way the pre-change app did: V1 schema and migration plan.
    private func writeLegacyStore(at url: URL, shows: [TrackedShow]) throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: PreBroadcasterSchemaV1.self),
            migrationPlan: PreBroadcasterMigrationPlan.self,
            configurations: ModelConfiguration(url: url))
        let context = ModelContext(container)
        for show in shows {
            context.insert(try PreBroadcasterSchemaV1.TrackedShowEntity(tracked: show))
        }
        try context.save()
    }

    /// Every stored field non-default, and no broadcaster (the legacy store has none).
    private func representativeTrackedShow(id: Int) -> TrackedShow {
        TrackedShow(
            id: id,
            name: "Show \(id)",
            posterMediumURL: URL(string: "https://static.tvmaze.com/\(id).jpg"),
            summaryHTML: "<p>Summary \(id)</p>",
            tvMazeURL: URL(string: "https://www.tvmaze.com/shows/\(id)"),
            status: .running,
            nextSeason: .scheduled(season: 3, premiere: Date(timeIntervalSince1970: 1_767_225_600)),
            sourceUpdatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastCheckedAt: Date(timeIntervalSince1970: 1_700_000_100),
            lastNotifiedSignature: "notified-\(id)",
            pendingChangeSignature: "pending-\(id)",
            isStale: true,
            dateAdded: Date(timeIntervalSince1970: 1_699_000_000 + Double(id)),
            isPaused: true
        )
    }
}

/// Test-only copy of the V1 model exactly as it was before `broadcasterName`.
/// Same version identifier and entity name as production, as a pre-change
/// TestFlight store would record.
enum PreBroadcasterSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [TrackedShowEntity.self] }

    @Model
    final class TrackedShowEntity {
        @Attribute(.unique) var tvMazeID: Int
        var name: String
        var posterMediumURL: URL?
        var summaryHTML: String?
        var tvMazeURL: URL?
        var statusRaw: String
        var nextSeasonSnapshot: Data
        var sourceUpdatedAt: Date
        var lastCheckedAt: Date
        var lastNotifiedSignature: String?
        var pendingChangeSignature: String?
        var isStale: Bool
        var dateAdded: Date
        var isPaused: Bool = false

        init(tracked: TrackedShow) throws {
            tvMazeID = tracked.id
            name = tracked.name
            posterMediumURL = tracked.posterMediumURL
            summaryHTML = tracked.summaryHTML
            tvMazeURL = tracked.tvMazeURL
            statusRaw = tracked.status.persistenceRawValue
            nextSeasonSnapshot = try JSONEncoder().encode(tracked.nextSeason)
            sourceUpdatedAt = tracked.sourceUpdatedAt
            lastCheckedAt = tracked.lastCheckedAt
            lastNotifiedSignature = tracked.lastNotifiedSignature
            pendingChangeSignature = tracked.pendingChangeSignature
            isStale = tracked.isStale
            dateAdded = tracked.dateAdded
            isPaused = tracked.isPaused
        }
    }
}

enum PreBroadcasterMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [PreBroadcasterSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
