//
//  WatchlistBroadcasterPersistenceTests.swift
//  NextSeasonTests
//

import Foundation
import SwiftData
import Testing

@testable import NextSeason

/// `broadcasterName` survives every repository write path in both the SwiftData
/// and in-memory repositories. SwiftData reads use a fresh context so values
/// come from the store, not the writing context's cache.
@MainActor
struct WatchlistBroadcasterPersistenceTests {
    enum Kind: CaseIterable, CustomTestStringConvertible {
        case swiftData, inMemory
        var testDescription: String { self == .swiftData ? "SwiftData" : "In-memory" }
    }

    /// A repository plus a way to read it back as freshly as that store allows.
    struct Harness {
        let repository: any WatchlistRepository
        let reload: () -> any WatchlistRepository
    }

    private func makeHarness(_ kind: Kind) throws -> Harness {
        switch kind {
        case .inMemory:
            let repository = InMemoryWatchlistRepository()
            return Harness(repository: repository, reload: { repository })
        case .swiftData:
            let container = try NextSeasonModelContainer.make(
                configuration: ModelConfiguration(
                    "broadcaster-\(UUID().uuidString)", isStoredInMemoryOnly: true))
            let rowMarks = WatchlistRowMarks(userDefaults: isolatedDefaults())
            return Harness(
                repository: SwiftDataWatchlistRepository(
                    context: ModelContext(container), rowMarks: rowMarks),
                reload: {
                    SwiftDataWatchlistRepository(
                        context: ModelContext(container), rowMarks: rowMarks)
                })
        }
    }

    private func storedBroadcaster(_ harness: Harness) async throws -> String? {
        try await harness.reload().trackedShow(showID: showID)?.broadcasterName
    }

    @Test("Adding a show stores its broadcaster", arguments: Kind.allCases)
    func addStoresBroadcaster(_ kind: Kind) async throws {
        let harness = try makeHarness(kind)
        try await harness.repository.add(show(network: "CBC Gem"))

        #expect(try await storedBroadcaster(harness) == "CBC Gem")
    }

    @Test("Adding a show without a broadcaster stores nil", arguments: Kind.allCases)
    func addWithoutBroadcaster(_ kind: Kind) async throws {
        let harness = try makeHarness(kind)
        try await harness.repository.add(show(network: nil))

        #expect(try await storedBroadcaster(harness) == nil)
    }

    @Test("Pausing and resuming keeps the broadcaster", arguments: Kind.allCases)
    func pauseKeepsBroadcaster(_ kind: Kind) async throws {
        let harness = try makeHarness(kind)
        try await harness.repository.add(show(network: "CBC Gem"))

        try await harness.repository.setPaused(true, showIDs: [showID])
        #expect(try await storedBroadcaster(harness) == "CBC Gem")
        try await harness.repository.setPaused(false, showIDs: [showID])
        #expect(try await storedBroadcaster(harness) == "CBC Gem")
    }

    @Test("Reactivating a paused show takes the fresh show's broadcaster", arguments: Kind.allCases)
    func reactivationUsesFreshBroadcaster(_ kind: Kind) async throws {
        let harness = try makeHarness(kind)
        try await harness.repository.add(show(network: "CBC"))
        try await harness.repository.setPaused(true, showIDs: [showID])

        try await harness.repository.add(show(network: "CBC Gem"))

        let stored = try #require(try await harness.reload().trackedShow(showID: showID))
        #expect(stored.isPaused == false)
        #expect(stored.broadcasterName == "CBC Gem")
    }

    @Test("Undoing a removal restores the broadcaster", arguments: Kind.allCases)
    func undoRestoresBroadcaster(_ kind: Kind) async throws {
        let harness = try makeHarness(kind)
        try await harness.repository.add(show(network: "CBC Gem"))
        let removed = try #require(try await harness.repository.trackedShow(showID: showID))

        try await harness.repository.remove(showID: showID)
        try await harness.repository.restoreRemoved(removed, isPaused: false)

        #expect(try await storedBroadcaster(harness) == "CBC Gem")
    }

    @Test("A refresh write replaces the broadcaster, including with nil", arguments: Kind.allCases)
    func refreshWriteReplacesBroadcaster(_ kind: Kind) async throws {
        let harness = try makeHarness(kind)
        try await harness.repository.add(show(network: "CBC"))
        var tracked = try #require(try await harness.repository.trackedShow(showID: showID))

        tracked.broadcasterName = "CBC Gem"
        try await harness.repository.updateAfterRefresh(tracked)
        #expect(try await storedBroadcaster(harness) == "CBC Gem")

        tracked.broadcasterName = nil
        try await harness.repository.updateAfterRefresh(tracked)
        #expect(try await storedBroadcaster(harness) == nil)
    }

    @Test(
        "Restoring an undelivered notification leaves the broadcaster alone",
        arguments: Kind.allCases)
    func undeliveredRestoreKeepsBroadcaster(_ kind: Kind) async throws {
        let harness = try makeHarness(kind)
        try await harness.repository.add(show(network: "CBC Gem"))
        let stored = try #require(try await harness.repository.trackedShow(showID: showID))

        _ = try await harness.repository.restoreUndeliveredNotification(
            stored, previousLastNotifiedSignature: nil)

        #expect(try await storedBroadcaster(harness) == "CBC Gem")
    }

    // MARK: - Fixtures

    private let showID = 1

    private func show(network: String?) -> Show {
        Show(
            id: showID,
            name: "Murdoch Mysteries",
            tvMazeURL: nil,
            summaryHTML: nil,
            posterMediumURL: nil,
            posterOriginalURL: nil,
            status: .running,
            premiered: nil,
            ended: nil,
            network: network,
            genres: [],
            averageRuntime: nil,
            seasons: [],
            nextEpisode: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}

private func isolatedDefaults() -> UserDefaults {
    let suiteName = "WatchlistBroadcasterPersistenceTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
