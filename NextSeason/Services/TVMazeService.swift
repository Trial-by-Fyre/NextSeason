//
//  TVMazeService.swift
//  NextSeason
//

import Foundation

/// Abstraction over the TVMaze API so view models can be tested with a mock.
nonisolated protocol TVMazeService: Sendable {
    /// Shows matching a free-text query, best matches first. Empty query → `[]`.
    ///
    /// Guest search uses TheTVDB; this remains for profile tooling and as a
    /// fallback path that still speaks TVMaze ids.
    func searchShows(matching query: String) async throws -> [Show]

    /// Resolves an external TheTVDB series id to the matching TVMaze show.
    ///
    /// Bridge used after guest search: Search lists TheTVDB hits, then this
    /// maps the selected id into the TVMaze-keyed detail / watchlist world when
    /// a local show ID mapping is missing or stale.
    func lookupShow(theTVDBID: Int) async throws -> Show

    /// Full show info including embedded seasons and next episode.
    func show(id: Int, bypassCache: Bool) async throws -> Show

    /// Show IDs updated since the given window (`GET /updates/shows?since=`).
    func updatedShows(since period: TVMazeUpdatePeriod) async throws -> [Int: Date]

    /// Full show-update map (`GET /updates/shows` with no `since` filter).
    ///
    /// Large payload. Used when the last successful sync is older than TVMaze's
    /// coarsest `since=month` window so long-absent installs can still see
    /// external-ID changes by filtering locally against a stored watermark.
    func allUpdatedShows() async throws -> [Int: Date]

    /// One page of the TVMaze show index (`GET /shows?page=`).
    ///
    /// Throws `TVMazeError.notFound` when the page is past the end of the index.
    /// Used only by the show ID mapping generator/refresh path — not Search.
    func showsIndex(page: Int) async throws -> [ShowIndexEntryData]

    /// Lightweight show fetch for mapping refresh (`id`, name, image, externals).
    func showIndexEntry(id: Int) async throws -> ShowIndexEntryData
}

extension TVMazeService {
    /// Default stubs so existing test doubles need not implement index / full-map APIs.
    func allUpdatedShows() async throws -> [Int: Date] {
        [:]
    }

    func showsIndex(page: Int) async throws -> [ShowIndexEntryData] {
        throw TVMazeError.notFound
    }

    func showIndexEntry(id: Int) async throws -> ShowIndexEntryData {
        throw TVMazeError.notFound
    }
}

/// Query window for `GET /updates/shows` (`?since=day|week|month`).
nonisolated enum TVMazeUpdatePeriod: String, Sendable {
    case day, week, month

    /// Conservative length of TVMaze's `since=month` window. TVMaze does not
    /// document the exact length, so assume 28 days (shorter than any calendar
    /// month) rather than risk gaps a shorter window would miss.
    static let monthWindow: TimeInterval = 28 * 86_400

    /// TVMaze caches API output for up to an hour, so a change can take that long
    /// to appear. Sync watermarks are set this far before the request or horizon
    /// so the next sync re-checks the unpublished hour.
    static let propagationDelay: TimeInterval = 60 * 60

    /// Smallest TVMaze update window that still covers every change since
    /// `oldestCheck`. Background refresh is best-effort and may be delayed, so
    /// the window must grow with the polling gap — otherwise a show that changed
    /// just outside a too-small window would be silently skipped.
    ///
    /// Thresholds: ≤1 day → `.day`, ≤1 week → `.week`, otherwise `.month`
    /// (TVMaze's coarsest supported `since` value). Gaps older than
    /// `monthWindow` cannot be covered by `since=` alone — callers that must
    /// not miss older changes should use the unfiltered updates endpoint and
    /// filter locally (see `requiresUnfilteredUpdateMap`).
    static func covering(since oldestCheck: Date, at: Date = .now) -> TVMazeUpdatePeriod {
        let elapsed = at.timeIntervalSince(oldestCheck)
        let oneDay: TimeInterval = 86_400
        let oneWeek: TimeInterval = 604_800

        if elapsed <= oneDay { return .day }
        if elapsed <= oneWeek { return .week }
        return .month
    }

    /// `true` when `since=month` may omit changes that happened after `oldestCheck`.
    static func requiresUnfilteredUpdateMap(since oldestCheck: Date, at: Date = .now) -> Bool {
        at.timeIntervalSince(oldestCheck) > monthWindow
    }
}

extension TVMazeService {
    /// Convenience: fetch show detail using the normal cache policy.
    func show(id: Int) async throws -> Show {
        try await show(id: id, bypassCache: false)
    }
}
