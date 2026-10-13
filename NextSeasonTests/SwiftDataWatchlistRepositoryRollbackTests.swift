//
//  SwiftDataWatchlistRepositoryRollbackTests.swift
//  NextSeasonTests
//

import Foundation
import SwiftData
import Testing

@testable import NextSeason

/// Review finding R01: a failed write must not linger in the repository's context.
/// After a failure, same-context reads must not see the change, a later unrelated
/// save must not commit it, and retrying the write must succeed.
@MainActor
struct SwiftDataWatchlistRepositoryRollbackTests {
    struct InjectedSaveError: Error {}

    /// Lets a test make exactly one save fail before the store is touched.
    @MainActor
    final class SaveFailureSwitch {
        var failNextSave = false
    }

    let container: ModelContainer
    let context: ModelContext
    let saves: SaveFailureSwitch
    let repository: SwiftDataWatchlistRepository

    init() throws {
        let container = try NextSeasonModelContainer.make(
            configuration: ModelConfiguration(
                "rollback-\(UUID().uuidString)", isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let saves = SaveFailureSwitch()
        self.container = container
        self.context = context
        self.saves = saves
        repository = SwiftDataWatchlistRepository(context: context) { context in
            if saves.failNextSave {
                saves.failNextSave = false
                throw InjectedSaveError()
            }
            try context.save()
        }
    }

    @Test("A failed insert is discarded, not committed later, and can be retried")
    func failedInsert() async throws {
        saves.failNextSave = true
        await #expect(throws: InjectedSaveError.self) { try await repository.add(show(1)) }

        #expect(try await repository.contains(showID: 1) == false)
        #expect(context.hasChanges == false)

        try await repository.add(show(2))
        #expect(try await storedRepository().trackedShowIDs() == [2])

        try await repository.add(show(1))
        #expect(try await storedRepository().trackedShowIDs() == [1, 2])
    }

    @Test("A failed delete is discarded, not committed later, and can be retried")
    func failedDelete() async throws {
        try await repository.add(show(1))

        saves.failNextSave = true
        await #expect(throws: InjectedSaveError.self) { try await repository.remove(showID: 1) }

        #expect(try await repository.contains(showID: 1))
        #expect(context.hasChanges == false)

        try await repository.add(show(2))
        #expect(try await storedRepository().trackedShowIDs() == [1, 2])

        try await repository.remove(showID: 1)
        #expect(try await storedRepository().trackedShowIDs() == [2])
    }

    @Test("A failed pause is discarded, not committed later, and can be retried")
    func failedPause() async throws {
        try await repository.add(show(1))

        saves.failNextSave = true
        await #expect(throws: InjectedSaveError.self) {
            try await repository.setPaused(true, showIDs: [1])
        }

        #expect(try await repository.activeShowIDs() == [1])
        #expect(context.hasChanges == false)

        try await repository.add(show(2))
        #expect(try await storedRepository().activeShowIDs() == [1, 2])

        try await repository.setPaused(true, showIDs: [1])
        #expect(try await storedRepository().activeShowIDs() == [2])
    }

    /// Also the prerequisite for R03 scenario 17 and R13 scenario 9: a failed
    /// refresh write leaves the previous stored row, including its decision state.
    @Test("A failed refresh write is discarded, not committed later, and can be retried")
    func failedRefreshWrite() async throws {
        try await repository.add(show(1))
        let original = try #require(try await repository.trackedShow(showID: 1))
        var refreshed = original
        refreshed.nextSeason = .announcedUndated(season: 2)
        refreshed.lastNotifiedSignature = "announcedUndated:2"
        refreshed.lastCheckedAt = original.lastCheckedAt.addingTimeInterval(3_600)

        saves.failNextSave = true
        await #expect(throws: InjectedSaveError.self) {
            try await repository.updateAfterRefresh(refreshed)
        }

        #expect(try await repository.trackedShow(showID: 1) == original)
        #expect(context.hasChanges == false)

        try await repository.add(show(2))
        #expect(try await storedRepository().trackedShow(showID: 1) == original)

        try await repository.updateAfterRefresh(refreshed)
        #expect(try await storedRepository().trackedShow(showID: 1) == refreshed)
    }

    @Test("A failed reactivation of a paused row leaves it paused and can be retried")
    func failedReactivation() async throws {
        try await repository.add(show(1))
        try await repository.setPaused(true, showIDs: [1])

        saves.failNextSave = true
        await #expect(throws: InjectedSaveError.self) { try await repository.add(show(1)) }

        #expect(try await repository.activeShowIDs().isEmpty)
        #expect(context.hasChanges == false)

        try await repository.add(show(2))
        #expect(try await storedRepository().activeShowIDs() == [2])

        try await repository.add(show(1))
        #expect(try await storedRepository().activeShowIDs() == [1, 2])
    }

    /// A repository over a fresh context, so reads reflect only what was saved.
    private func storedRepository() -> SwiftDataWatchlistRepository {
        SwiftDataWatchlistRepository(context: ModelContext(container))
    }
}

/// The real failure the review reproduced: SwiftData itself refuses the save
/// (read-only store). The context must still be rolled back.
@MainActor
struct SwiftDataWatchlistRepositoryReadOnlyStoreTests {
    enum Write: CaseIterable, Sendable {
        case insert, delete, pause, refresh
    }

    @Test(
        "A write rejected by a read-only store leaves no pending change", arguments: Write.allCases)
    func rejectedWriteIsRolledBack(_ write: Write) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rollback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("watchlist.store")

        // Seed show 1 through a writable container, then reopen the store read-only.
        do {
            let writable = try NextSeasonModelContainer.make(
                configuration: ModelConfiguration(url: storeURL))
            try await SwiftDataWatchlistRepository(context: ModelContext(writable)).add(show(1))
        }
        let readOnly = try NextSeasonModelContainer.make(
            configuration: ModelConfiguration(url: storeURL, allowsSave: false))
        let context = ModelContext(readOnly)
        let repository = SwiftDataWatchlistRepository(context: context)
        let original = try #require(try await repository.trackedShow(showID: 1))

        // SwiftData's error type for a refused save is not public API, so any error counts.
        await #expect(throws: (any Error).self) {
            switch write {
            case .insert:
                try await repository.add(show(2))
            case .delete:
                try await repository.remove(showID: 1)
            case .pause:
                try await repository.setPaused(true, showIDs: [1])
            case .refresh:
                var refreshed = original
                refreshed.lastNotifiedSignature = "announcedUndated:2"
                try await repository.updateAfterRefresh(refreshed)
            }
        }

        #expect(context.hasChanges == false)
        // Must be the first unfiltered fetch after the failure: on iOS 18 that fetch
        // returned the discarded insert, or omitted the discarded delete, when the
        // repository kept using the rolled-back context.
        #expect(try await repository.trackedShowIDs() == [1])
        #expect(try await repository.trackedShow(showID: 1) == original)
    }
}

/// Minimal show fixture for repository writes.
private func show(_ id: Int) -> Show {
    Show(
        id: id, name: "Show \(id)", tvMazeURL: nil, summaryHTML: nil,
        posterMediumURL: nil, posterOriginalURL: nil, status: .running,
        premiered: nil, ended: nil, network: nil, genres: [], averageRuntime: nil,
        seasons: [], nextEpisode: nil, updatedAt: .now)
}
