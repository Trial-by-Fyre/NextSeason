//
//  WatchlistExportPreparationTests.swift
//  NextSeasonTests
//

import Foundation
import Testing

@testable import NextSeason

/// Export prepare UI state: in-progress disabling, error dismissal, and retry after failure.
/// Uses a gated repository to observe mid-flight state before `all()` completes.
@MainActor
struct WatchlistExportPreparationTests {
    @Test("Failed prepare stays retryable after the error is dismissed")
    func retryAfterFailedPrepare() async throws {
        let repository = GatedWatchlistExportRepository()
        repository.allResults = [
            .failure(URLError(.cannotConnectToHost)),
            .success([]),
        ]
        let mapping = InMemoryShowIDMapping(map: [:])
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("watchlist-export-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let preparation = WatchlistExportPreparation()
        #expect(preparation.isPreparing == false)
        #expect(preparation.isExportControlDisabled == false)

        let prepareTask = Task {
            await preparation.prepare(
                repository: repository,
                showIDMapping: mapping,
                directory: directory
            )
        }

        await repository.waitUntilAllBegan()
        #expect(preparation.isPreparing)
        #expect(preparation.isExportControlDisabled)
        #expect(preparation.exportFile == nil)

        repository.resumeAll()
        await prepareTask.value

        #expect(preparation.isPreparing == false)
        #expect(preparation.errorMessage != nil)
        #expect(preparation.exportFile == nil)

        preparation.dismissError()
        #expect(preparation.errorMessage == nil)
        #expect(preparation.isExportControlDisabled == false)
        #expect(repository.allCallCount == 1)

        let retryTask = Task {
            await preparation.prepare(
                repository: repository,
                showIDMapping: mapping,
                directory: directory
            )
        }
        await repository.waitUntilAllBegan()
        #expect(preparation.isPreparing)
        #expect(repository.allCallCount == 2)

        repository.resumeAll()
        await retryTask.value

        #expect(preparation.isPreparing == false)
        #expect(preparation.errorMessage == nil)
        #expect(preparation.exportFile != nil)
        #expect(repository.allCallCount == 2)
    }
}

/// Suspends inside `all()` until released so tests can observe in-progress state.
@MainActor
private final class GatedWatchlistExportRepository: WatchlistRepository {
    var allResults: [Result<[TrackedShow], Error>] = []
    private(set) var allCallCount = 0
    private var allBeganContinuation: CheckedContinuation<Void, Never>?
    private var allGateContinuation: CheckedContinuation<Void, Never>?

    func waitUntilAllBegan() async {
        await withCheckedContinuation { continuation in
            if allGateContinuation != nil {
                continuation.resume()
                return
            }
            allBeganContinuation = continuation
        }
    }

    func resumeAll() {
        allGateContinuation?.resume()
        allGateContinuation = nil
    }

    func all() async throws -> [TrackedShow] {
        allCallCount += 1
        allBeganContinuation?.resume()
        allBeganContinuation = nil
        await withCheckedContinuation { continuation in
            allGateContinuation = continuation
        }
        return try allResults.removeFirst().get()
    }

    func trackedShow(showID: Int) async throws -> TrackedShow? { nil }

    func trackedShowIDs() async throws -> Set<Int> { [] }

    func contains(showID: Int) async throws -> Bool { false }

    func add(_ show: Show) async throws {}

    func remove(showID: Int) async throws {}

    func updateAfterRefresh(_ tracked: TrackedShow) async throws {}

    func setPaused(_ isPaused: Bool, showIDs: Set<Int>) async throws {}
}
