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

    /// Matches SwiftData `TrackedShowEntity.apply`: no-op if the row was removed;
    /// refresh writes copy `dateAdded` from the incoming row and never change
    /// the stored pause flag.
    func updateAfterRefresh(_ tracked: TrackedShow) async throws {
        guard var stored = shows[tracked.id] else { return }
        stored.dateAdded = tracked.dateAdded
        stored.name = tracked.name
        stored.posterMediumURL = tracked.posterMediumURL
        stored.summaryHTML = tracked.summaryHTML
        stored.tvMazeURL = tracked.tvMazeURL
        stored.broadcasterName = tracked.broadcasterName
        stored.status = tracked.status
        stored.nextSeason = tracked.nextSeason
        stored.sourceUpdatedAt = tracked.sourceUpdatedAt
        stored.lastCheckedAt = tracked.lastCheckedAt
        stored.lastNotifiedSignature = tracked.lastNotifiedSignature
        stored.pendingChangeSignature = tracked.pendingChangeSignature
        stored.isStale = tracked.isStale
        shows[tracked.id] = stored
    }

    func setPaused(_ isPaused: Bool, showIDs: Set<Int>) async throws {
        for id in showIDs {
            shows[id]?.isPaused = isPaused
        }
    }

    func restoreRemoved(_ tracked: TrackedShow, isPaused: Bool) async throws {
        guard shows[tracked.id] == nil else { return }
        var row = tracked
        row.isPaused = isPaused
        shows[tracked.id] = row
    }

    /// Same guard as SwiftData, as one write.
    @discardableResult
    func restoreUndeliveredNotification(
        _ attempt: TrackedShow, previousLastNotifiedSignature: String?
    ) async throws -> Bool {
        guard let stored = shows[attempt.id],
            StatusChangeDetector.isStillCurrent(stored, decidedBy: attempt)
        else { return false }
        shows[attempt.id]?.lastNotifiedSignature = previousLastNotifiedSignature
        shows[attempt.id]?.pendingChangeSignature = attempt.lastNotifiedSignature
        return true
    }
}
