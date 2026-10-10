//
//  InMemoryWatchlistRepository.swift
//  NextSeason
//

import Foundation

/// Test and preview double for `WatchlistRepository`.
@MainActor
final class InMemoryWatchlistRepository: WatchlistRepository {
    private var shows: [Int: TrackedShow]

    /// `seed` rows are stored as-is (including `isPaused` and `dateAdded`).
    init(seed: [TrackedShow] = []) {
        shows = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
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

    func activeShowIDs() async throws -> Set<Int> {
        Set(shows.values.filter { !$0.isPaused }.map(\.id))
    }

    func add(_ show: Show) async throws {
        if let existing = shows[show.id] {
            guard existing.isPaused else { return }
            shows[show.id] = TrackedShow(reactivating: existing, from: show)
            return
        }
        let tracked = TrackedShow(from: show)
        shows[show.id] = tracked
    }

    func remove(showID: Int) async throws {
        shows.removeValue(forKey: showID)
    }

    /// Matches SwiftData: refresh writes never change the stored pause flag.
    func updateAfterRefresh(_ tracked: TrackedShow) async throws {
        var updated = tracked
        updated.isPaused = shows[tracked.id]?.isPaused ?? tracked.isPaused
        shows[tracked.id] = updated
    }

    func setPaused(_ isPaused: Bool, showIDs: Set<Int>) async throws {
        for id in showIDs {
            shows[id]?.isPaused = isPaused
        }
    }
}
