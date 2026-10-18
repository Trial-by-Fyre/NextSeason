//
//  WatchlistRepository+Environment.swift
//  NextSeason
//

import SwiftUI

private struct WatchlistRepositoryKey: EnvironmentKey {
    @MainActor static let defaultValue: any WatchlistRepository = UnconfiguredWatchlistRepository()
}

extension EnvironmentValues {
    /// Local watchlist persistence; must be injected at the root (fatal if missing).
    @MainActor var watchlistRepository: any WatchlistRepository {
        get { self[WatchlistRepositoryKey.self] }
        set { self[WatchlistRepositoryKey.self] = newValue }
    }
}

@MainActor
private final class UnconfiguredWatchlistRepository: WatchlistRepository {
    private func fail() -> Never {
        fatalError("WatchlistRepository was not injected. Set it on the root view.")
    }

    func all() async throws -> [TrackedShow] { fail() }
    func trackedShow(showID: Int) async throws -> TrackedShow? { fail() }
    func trackedShowIDs() async throws -> Set<Int> { fail() }
    func contains(showID: Int) async throws -> Bool { fail() }
    func add(_ show: Show) async throws { fail() }
    func remove(showID: Int) async throws { fail() }
    func updateAfterRefresh(_ tracked: TrackedShow) async throws { fail() }
    func activeShowIDs() async throws -> Set<Int> { fail() }
    func setPaused(_ isPaused: Bool, showIDs: Set<Int>) async throws { fail() }
    func restoreRemoved(_ tracked: TrackedShow, isPaused: Bool) async throws { fail() }
}
