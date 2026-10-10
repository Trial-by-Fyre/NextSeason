//
//  NextSeasonSchemaTests.swift
//  NextSeasonTests
//

import Foundation
import SwiftData
import Testing

@testable import NextSeason

@MainActor
struct NextSeasonSchemaTests {
    @Test("V1 is the only schema and has no migration stages")
    func schemaLadderIsV1Only() {
        #expect(NextSeasonSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(NextSeasonSchemaV1.models.count == 1)
        #expect(
            NextSeasonSchemaV1.models.contains { $0 == NextSeasonSchemaV1.TrackedShowEntity.self })
        #expect(NextSeasonMigrationPlan.schemas.count == 1)
        #expect(NextSeasonMigrationPlan.stages.isEmpty)
    }

    /// SwiftData has no entity-level `originalName`. Compatibility with
    /// unversioned TestFlight stores depends on this name staying
    /// `TrackedShowEntity` — the same `Schema.entityName(for:)` used before
    /// the model was nested in V1.
    @Test("V1 persistent entity name remains TrackedShowEntity")
    func v1PersistentEntityNameMatchesUnversionedStore() {
        #expect(
            Schema.entityName(for: NextSeasonSchemaV1.TrackedShowEntity.self) == "TrackedShowEntity"
        )
        #expect(Schema.entityName(for: TrackedShowEntity.self) == "TrackedShowEntity")

        let schema = Schema(versionedSchema: NextSeasonSchemaV1.self)
        #expect(schema.entitiesByName.keys.sorted() == ["TrackedShowEntity"])
        let entity = schema.entitiesByName["TrackedShowEntity"]
        #expect(entity != nil)
        #expect(
            entity?.attributesByName.keys.sorted() == [
                "dateAdded",
                "isPaused",
                "isStale",
                "lastCheckedAt",
                "lastNotifiedSignature",
                "name",
                "nextSeasonSnapshot",
                "pendingChangeSignature",
                "posterMediumURL",
                "sourceUpdatedAt",
                "statusRaw",
                "summaryHTML",
                "tvMazeID",
                "tvMazeURL",
            ])
    }

    @Test("Versioned ModelContainer can be created and round-trips every persisted field")
    func versionedContainerRoundTripsAllFields() throws {
        let container = try NextSeasonModelContainer.make(
            configuration: ModelConfiguration(
                "nextseason-schema-mem-\(UUID().uuidString)",
                isStoredInMemoryOnly: true
            )
        )
        let original = representativeTrackedShow()

        let writeContext = ModelContext(container)
        writeContext.insert(try TrackedShowEntity(tracked: original))
        try writeContext.save()

        let readContext = ModelContext(container)
        let fetched = try readContext.fetch(FetchDescriptor<TrackedShowEntity>())
        let entity = try #require(fetched.first)
        try expectPersistedFields(entity, match: original)
    }

    /// Opens a store created with `ModelContainer(for: TrackedShowEntity.self)`
    /// and no migration plan — the same initializer TestFlight builds used —
    /// then reopens it with `NextSeasonSchemaV1` + `NextSeasonMigrationPlan`.
    ///
    /// What this proves: a store written without a versioned schema, whose
    /// entity name and attributes match V1, can be opened by the production
    /// container path and still reconstruct every persisted field.
    ///
    /// What this does not prove: a store written by a previously compiled
    /// TestFlight binary whose `TrackedShowEntity` was a top-level `@Model`
    /// (not `NextSeasonSchemaV1.TrackedShowEntity`). That still requires the
    /// manual upgrade test.
    @Test("Unversioned on-disk store opens with the V1 migration plan")
    func unversionedStoreOpensWithVersionedSchema() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "nextseason-schema-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("default.store")
        let original = representativeTrackedShow()

        try {
            let unversionedContainer = try ModelContainer(
                for: TrackedShowEntity.self,
                configurations: ModelConfiguration(url: storeURL)
            )
            let context = ModelContext(unversionedContainer)
            context.insert(try TrackedShowEntity(tracked: original))
            try context.save()
        }()

        let versionedContainer = try NextSeasonModelContainer.make(
            configuration: ModelConfiguration(url: storeURL)
        )
        let context = ModelContext(versionedContainer)
        let fetched = try context.fetch(FetchDescriptor<TrackedShowEntity>())
        #expect(fetched.count == 1)

        let entity = try #require(fetched.first)
        try expectPersistedFields(entity, match: original)
    }

    /// Representative V1 row: every stored field is non-default so the
    /// round trip is a useful contract test for the schema that ships in 1.0.
    private func representativeTrackedShow() -> TrackedShow {
        TrackedShow(
            id: 44933,
            name: "Severance",
            posterMediumURL: URL(
                string: "https://static.tvmaze.com/uploads/images/medium_portrait/1/1.jpg"),
            summaryHTML: "<p>A workplace thriller.</p>",
            tvMazeURL: URL(string: "https://www.tvmaze.com/shows/44933/severance"),
            status: .unknown("Pilot"),
            nextSeason: .scheduled(
                season: 3,
                premiere: Date(timeIntervalSince1970: 1_767_225_600)
            ),
            sourceUpdatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastCheckedAt: Date(timeIntervalSince1970: 1_700_000_100),
            lastNotifiedSignature: "notified-sig",
            pendingChangeSignature: "pending-sig",
            isStale: true,
            dateAdded: Date(timeIntervalSince1970: 1_699_000_000),
            isPaused: true
        )
    }

    private func expectPersistedFields(
        _ entity: TrackedShowEntity,
        match tracked: TrackedShow,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        #expect(entity.tvMazeID == tracked.id, sourceLocation: sourceLocation)
        #expect(entity.name == tracked.name, sourceLocation: sourceLocation)
        #expect(entity.posterMediumURL == tracked.posterMediumURL, sourceLocation: sourceLocation)
        #expect(entity.summaryHTML == tracked.summaryHTML, sourceLocation: sourceLocation)
        #expect(entity.tvMazeURL == tracked.tvMazeURL, sourceLocation: sourceLocation)
        #expect(
            entity.statusRaw == tracked.status.persistenceRawValue, sourceLocation: sourceLocation)
        let storedNextSeason = try JSONDecoder().decode(
            NextSeasonStatus.self, from: entity.nextSeasonSnapshot)
        #expect(storedNextSeason == tracked.nextSeason, sourceLocation: sourceLocation)
        #expect(entity.sourceUpdatedAt == tracked.sourceUpdatedAt, sourceLocation: sourceLocation)
        #expect(entity.lastCheckedAt == tracked.lastCheckedAt, sourceLocation: sourceLocation)
        #expect(
            entity.lastNotifiedSignature == tracked.lastNotifiedSignature,
            sourceLocation: sourceLocation)
        #expect(
            entity.pendingChangeSignature == tracked.pendingChangeSignature,
            sourceLocation: sourceLocation)
        #expect(entity.isStale == tracked.isStale, sourceLocation: sourceLocation)
        #expect(entity.dateAdded == tracked.dateAdded, sourceLocation: sourceLocation)
        #expect(entity.isPaused == tracked.isPaused, sourceLocation: sourceLocation)

        let reconstructed = try entity.toDomain()
        #expect(reconstructed == tracked, sourceLocation: sourceLocation)
    }
}
