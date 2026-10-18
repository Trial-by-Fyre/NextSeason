import CoreGraphics
import Foundation
import Observation
import SQLite3
import SwiftData
import SwiftUI
import Synchronization
import os

//
//  Show.swift
//  NextSeason
//

/// The app-facing show model. API quirks (HTML summaries, raw date strings,
/// open-ended status) are already resolved here so views never see DTO types.
nonisolated struct Show: Identifiable, Sendable, Hashable {
    let id: Int
    let name: String
    /// The show's page on TVMaze, used for attribution and a "view more" link.
    let tvMazeURL: URL?
    /// Raw TVMaze summary HTML, kept intact so it can be rendered formatted at
    /// display time (see `SummaryFormatter`).
    let summaryHTML: String?
    let posterMediumURL: URL?
    let posterOriginalURL: URL?
    let status: ShowStatus
    let premiered: Date?
    let ended: Date?
    let network: String?
    let genres: [String]
    let averageRuntime: Int?
    let seasons: [Season]
    let nextEpisode: NextEpisode?
    let updatedAt: Date
}

//
//  ShowStatus.swift
//  NextSeason
//

/// A show's production status. TVMaze's set is treated as open-ended: any
/// unrecognized value is preserved in `.unknown` rather than dropped.
nonisolated enum ShowStatus: Sendable, Hashable {
    case running
    case ended
    case toBeDetermined
    case inDevelopment
    case unknown(String)

    init(rawValue: String?) {
        switch rawValue {
        case "Running": self = .running
        case "Ended": self = .ended
        case "To Be Determined": self = .toBeDetermined
        case "In Development": self = .inDevelopment
        case let other?: self = .unknown(other)
        case nil: self = .unknown("Unknown")
        }
    }

    var displayLabel: String {
        switch self {
        case .running: String(localized: "Ongoing series")
        case .ended: String(localized: "Ended")
        case .toBeDetermined: String(localized: "To Be Determined")
        case .inDevelopment: String(localized: "In Development")
        case .unknown(let value): value
        }
    }
}

//
//  Season.swift
//  NextSeason
//

/// A clean, app-facing season. `premiereDate`/`endDate` are nil for an
/// announced-but-unscheduled season.
nonisolated struct Season: Identifiable, Sendable, Hashable {
    let id: Int
    let number: Int
    let premiereDate: Date?
    let endDate: Date?
    let episodeOrder: Int?
}

//
//  NextEpisode.swift
//  NextSeason
//

/// The show's next scheduled episode, when one exists. `season` indicates which
/// season that upcoming episode belongs to — a useful signal for detecting a new
/// season that doesn't yet have its own dated season row.
nonisolated struct NextEpisode: Sendable, Hashable {
    let season: Int?
    let airdate: Date?
}

//
//  NextSeasonStatus.swift
//  NextSeason
//

/// The app's answer to "is there a next season, and when?", derived by
/// `NextSeasonCalculator` from a show's status, seasons, and next episode.
nonisolated enum NextSeasonStatus: Sendable, Hashable {
    /// The most recent season is currently airing / just released.
    case airing(season: Int)
    /// A not-yet-aired season has a known future premiere date.
    case scheduled(season: Int, premiere: Date)
    /// A future season exists in the data but has no premiere date yet.
    case announcedUndated(season: Int)
    /// The show is returning but no next-season row exists yet.
    case returningNoSeasonYet
    /// The show has ended with nothing upcoming.
    case ended
    /// Not enough information to decide.
    case unknown
}

//
//  NextSeasonStatus+Codable.swift
//  NextSeason
//

/// Codable storage for `NextSeasonStatus` on `TrackedShowEntity`.
///
/// Uses a keyed `kind` discriminator (not enum case order) so adding cases later
/// does not break decoding of previously persisted values. Associated values
/// (`season`, `premiere`) are optional keys present only when that kind needs them.
nonisolated extension NextSeasonStatus: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, season, premiere
    }

    /// Stable string tags written to disk; rename only with a migration plan.
    private enum Kind: String, Codable {
        case airing, scheduled, announcedUndated, returningNoSeasonYet, ended, unknown
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .airing:
            self = .airing(season: try container.decode(Int.self, forKey: .season))
        case .scheduled:
            self = .scheduled(
                season: try container.decode(Int.self, forKey: .season),
                premiere: try container.decode(Date.self, forKey: .premiere)
            )
        case .announcedUndated:
            self = .announcedUndated(season: try container.decode(Int.self, forKey: .season))
        case .returningNoSeasonYet:
            self = .returningNoSeasonYet
        case .ended:
            self = .ended
        case .unknown:
            self = .unknown
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .airing(let season):
            try container.encode(Kind.airing, forKey: .kind)
            try container.encode(season, forKey: .season)
        case .scheduled(let season, let premiere):
            try container.encode(Kind.scheduled, forKey: .kind)
            try container.encode(season, forKey: .season)
            try container.encode(premiere, forKey: .premiere)
        case .announcedUndated(let season):
            try container.encode(Kind.announcedUndated, forKey: .kind)
            try container.encode(season, forKey: .season)
        case .returningNoSeasonYet:
            try container.encode(Kind.returningNoSeasonYet, forKey: .kind)
        case .ended:
            try container.encode(Kind.ended, forKey: .kind)
        case .unknown:
            try container.encode(Kind.unknown, forKey: .kind)
        }
    }
}

extension ShowStatus {
    /// TVMaze's exact status string for SwiftData (`statusRaw`). Distinct from
    /// `displayLabel`, which is user-facing copy. `.unknown` round-trips the
    /// original API value unchanged.
    nonisolated var persistenceRawValue: String {
        switch self {
        case .running: "Running"
        case .ended: "Ended"
        case .toBeDetermined: "To Be Determined"
        case .inDevelopment: "In Development"
        case .unknown(let value): value
        }
    }
}

//
//  TrackedShow.swift
//  NextSeason
//

/// A show the user is monitoring for next-season changes. Stored on-device only.
///
/// Refresh, notification debounce, and SwiftData persistence all share this
/// shape; signatures and timestamps below drive PD-008 change detection.
nonisolated struct TrackedShow: Identifiable, Sendable, Hashable {
    let id: Int
    var name: String
    var posterMediumURL: URL?
    var summaryHTML: String?
    var tvMazeURL: URL?
    var status: ShowStatus
    var nextSeason: NextSeasonStatus
    /// TVMaze's `updated` timestamp for this show; used to skip re-fetch when
    /// `/updates/shows` reports no newer change.
    var sourceUpdatedAt: Date
    /// Last time we successfully refreshed this row (policy / diagnostics).
    var lastCheckedAt: Date
    /// Signature of the last status we already notified about; suppresses repeat
    /// alerts for the same change (`StatusChangeDetector`).
    var lastNotifiedSignature: String?
    /// When a non-date-backed change is first seen, holds its signature until a
    /// second poll confirms it (PD-008 debounce).
    var pendingChangeSignature: String?
    /// True when TVMaze no longer returns this show (merged/deleted).
    var isStale: Bool
    var dateAdded: Date
    /// True when a lapsed Plus subscription left this show beyond the free limit.
    /// Paused shows stay saved but are not refreshed, notified, or opened.
    var isPaused: Bool

    init(
        id: Int,
        name: String,
        posterMediumURL: URL?,
        summaryHTML: String? = nil,
        tvMazeURL: URL? = nil,
        status: ShowStatus,
        nextSeason: NextSeasonStatus,
        sourceUpdatedAt: Date,
        lastCheckedAt: Date,
        lastNotifiedSignature: String? = nil,
        pendingChangeSignature: String? = nil,
        isStale: Bool = false,
        dateAdded: Date,
        isPaused: Bool = false
    ) {
        self.id = id
        self.name = name
        self.posterMediumURL = posterMediumURL
        self.summaryHTML = summaryHTML
        self.tvMazeURL = tvMazeURL
        self.status = status
        self.nextSeason = nextSeason
        self.sourceUpdatedAt = sourceUpdatedAt
        self.lastCheckedAt = lastCheckedAt
        self.lastNotifiedSignature = lastNotifiedSignature
        self.pendingChangeSignature = pendingChangeSignature
        self.isStale = isStale
        self.dateAdded = dateAdded
        self.isPaused = isPaused
    }

    /// Fresh data for reactivating a paused row from a newly loaded show. Keeps
    /// the original `dateAdded` (free-tier ordering) and last-notified signature
    /// (no repeat alert for a state already announced); clears pause and debounce.
    init(reactivating existing: TrackedShow, from show: Show, at: Date = .now) {
        self.init(from: show, at: at)
        dateAdded = existing.dateAdded
        lastNotifiedSignature = existing.lastNotifiedSignature
    }

    /// Builds a tracked row from a fully-loaded show at save time.
    init(from show: Show, at: Date = .now) {
        self.init(
            id: show.id,
            name: show.name,
            posterMediumURL: show.posterMediumURL,
            summaryHTML: show.summaryHTML,
            tvMazeURL: show.tvMazeURL,
            status: show.status,
            nextSeason: NextSeasonCalculator.status(for: show, at: at),
            sourceUpdatedAt: show.updatedAt,
            lastCheckedAt: at,
            dateAdded: at
        )
    }
}

extension Show {
    /// A lightweight show for navigation from the watchlist; detail reloads full data.
    init(tracked: TrackedShow) {
        self.init(
            id: tracked.id,
            name: tracked.name,
            tvMazeURL: tracked.tvMazeURL,
            summaryHTML: tracked.summaryHTML,
            posterMediumURL: tracked.posterMediumURL,
            posterOriginalURL: nil,
            status: tracked.status,
            premiered: nil,
            ended: nil,
            network: nil,
            genres: [],
            averageRuntime: nil,
            seasons: [],
            nextEpisode: nil,
            updatedAt: tracked.sourceUpdatedAt
        )
    }
}

//
//  TVDBSearchResult.swift
//  NextSeason
//

/// A series hit from TheTVDB search.
///
/// Identity is TheTVDB's series id — not a TVMaze id. Search filters hits through
/// the local TVDB↔TVMaze show ID mapping before display, overlaying TVMaze title
/// and poster from that snapshot. Open/track resolves via the mapped TVMaze id
/// (`show(id:)`), falling back to `lookupShow(theTVDBID:)` when a mapping is stale.
nonisolated struct TVDBSearchResult: Identifiable, Sendable, Hashable {
    /// TheTVDB series id (`tvdb_id` from the search payload).
    let id: Int
    let name: String
    let year: String?
    let network: String?
    /// Provider status string (e.g. "Continuing", "Ended"); shown as-is on
    /// search rows rather than mapped into TVMaze's `ShowStatus`.
    let status: String?
    let posterURL: URL?

    /// Compact subtitle for search rows (year and/or status).
    var searchSubtitle: String {
        let parts = [year, status].compactMap { value -> String? in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if parts.isEmpty {
            return String(localized: "TV series")
        }
        return parts.joined(separator: " · ")
    }

    /// Returns a copy using cached TVMaze display fields.
    ///
    /// The title falls back to TheTVDB when the mapping has no name.
    /// Posters intentionally never fall back to TheTVDB artwork  —
    /// TheTVDB artwork is not licensed for this use.
    func overlayingTVMazeDisplayFields(_ record: ShowIDMappingRecord) -> TVDBSearchResult {
        let trimmedName = record.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return TVDBSearchResult(
            id: id,
            name: trimmedName.isEmpty ? name : trimmedName,
            year: year,
            network: network,
            status: status,
            posterURL: record.posterMediumURL
        )
    }
}

//
//  ShowIndexEntryData.swift
//  NextSeason
//

/// TVMaze show payload from `/shows?page=` (and `/shows/:id` for refresh).
///
/// Id + externals drive the TheTVDB mapping; name and medium poster are stored
/// so Search can overlay TVMaze display fields without a live show fetch.
nonisolated struct ShowIndexEntryData: Codable, Sendable, Equatable {
    let id: Int
    let name: String?
    let image: ImageData?
    let externals: ShowExternalsData?

    init(
        id: Int,
        name: String? = nil,
        image: ImageData? = nil,
        externals: ShowExternalsData? = nil
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.externals = externals
    }

    // We intentionally store only the medium poster URL.
    // Search results never display original-resolution artwork, so
    // storing larger URLs would increase database size with no benefit.
    var posterMediumURL: URL? {
        image?.medium.flatMap(URL.init(string:))
    }
}

/// External ids attached to a TVMaze show (show ID mapping uses `thetvdb`).
nonisolated struct ShowExternalsData: Codable, Sendable, Equatable {
    let thetvdb: Int?
}

//
//  ImageData.swift
//  NextSeason
//

/// TVMaze image payload (poster format for shows). Either resolution may be absent.
nonisolated struct ImageData: Codable, Sendable, Equatable {
    let medium: String?
    let original: String?
}

//
//  TVMazeService.swift
//  NextSeason
//

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

    /// Approximate length of TVMaze's `since=month` window.
    static let monthWindow: TimeInterval = 30 * 86_400

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

//
//  TheTVDBService.swift
//  NextSeason
//

/// One page of TheTVDB series search hits.
///
/// Pagination bookkeeping (`hasMore`, `nextOffset`) is owned by the service
/// implementation and must be based on the **raw** API row count / links
/// metadata — not the number of domain results after sparse records are
/// dropped. That keeps TheTVDB's `offset` cursor aligned across pages.
nonisolated struct TheTVDBSearchPage: Sendable, Equatable {
    let results: [TVDBSearchResult]
    /// `true` when another `offset` page may still contain matches.
    let hasMore: Bool
    /// Absolute TheTVDB `offset` to request for the next page.
    let nextOffset: Int
}

/// Abstraction over TheTVDB search so view models can be tested with a mock.
///
/// Production uses `TheTVDBClient`. UI tests / previews use
/// `PreviewTheTVDBService`. Keeping search behind this protocol mirrors
/// `TVMazeService` and lets Search stay provider-swappable without touching
/// detail or watchlist code.
nonisolated protocol TheTVDBService: Sendable {
    /// Series matching a free-text query, best matches first.
    ///
    /// Empty / whitespace query → empty page with `hasMore == false`.
    /// `offset` is the zero-based result index (`page * pageSize`), matching
    /// TheTVDB's query parameter (not a 1-based page number).
    /// Callers must continue with `page.nextOffset` rather than reconstructing
    /// offset from `results.count`.
    func searchSeries(matching query: String, offset: Int) async throws -> TheTVDBSearchPage
}

//
//  TheTVDBConfiguration.swift
//  NextSeason
//

/// Shared TheTVDB v4 endpoints, credentials, and search page size.
///
/// Search is the only TheTVDB surface in NextSeason; show/season detail,
/// watchlist persistence, and refresh stay on TVMaze. Marked `nonisolated` so
/// actor clients (e.g. `TheTVDBClient`) can use these defaults under the app's
/// default MainActor isolation.
nonisolated enum TheTVDBConfiguration {
    /// API v4 root (`https://api4.thetvdb.com/v4`).
    static let baseURL = URL(string: "https://api4.thetvdb.com/v4")!

    /// Public site used for attribution links (not the API host).
    static let websiteURL = URL(string: "https://www.thetvdb.com")!

    /// Results per search page. TheTVDB paginates with `limit` + `offset`
    /// (not a 1-based page index).
    static let pageSize = 10
}

//
//  TVMazeError.swift
//  NextSeason
//

/// Errors surfaced by `TVMazeService`. `errorDescription` provides user-facing copy.
nonisolated enum TVMazeError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case network(URLError)
    case decoding(Error)
    /// Missing show **or** end of the `/shows?page=` index (`showsIndex` past last page).
    case notFound
    case rateLimited
    case server(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL, .invalidResponse:
            String(localized: "Something went wrong. Please try again.")
        case .network:
            String(localized: "Couldn't reach TVMaze. Check your connection and try again.")
        case .decoding:
            String(localized: "We couldn't read the data from TVMaze.")
        case .notFound:
            String(localized: "That show isn't available in NextSeason yet.")
        case .rateLimited:
            String(
                localized:
                    "Too many requests right now. Please wait a moment and try again."
            )
        case .server:
            String(
                localized:
                    "TVMaze is having trouble right now. Please try again later."
            )
        }
    }
}

//
//  ShowIDMapping.swift
//  NextSeason
//

/// Cached TVMaze display fields keyed from a TheTVDB series id.
///
/// Used to filter Search and to overlay TVMaze title/poster on the results list
/// without a network fetch. Live TVMaze remains canonical after open/track.
nonisolated struct ShowIDMappingRecord: Equatable, Sendable {
    let tvMazeID: Int
    /// TVMaze show name; `nil` when the snapshot has no title yet.
    let name: String?
    /// TVMaze medium poster; `nil` when the snapshot has no artwork.
    let posterMediumURL: URL?
}

/// Offline TheTVDB → TVMaze lookup used to filter Search to actionable shows
/// and overlay TVMaze title/poster on the results list.
///
/// This is a search-display cache, not the source of truth for seasons or
/// watchlist state. After the user selects a result, live TVMaze remains canonical.
/// Watchlist export also uses the reverse lookup for a TVDB id when one exists.
nonisolated protocol ShowIDMapping: Sendable {
    /// Mapping row for a TheTVDB series id, or `nil` when unknown locally.
    func record(forTVDBID id: Int) async -> ShowIDMappingRecord?
    /// A TheTVDB series id for this TVMaze show, or `nil` when unknown locally.
    ///
    /// A TVMaze show can theoretically map from more than one TheTVDB id; the
    /// lowest id is returned so the result is stable.
    func tvdbID(forTVMazeID id: Int) async -> Int?
}

extension ShowIDMapping {
    /// TVMaze show id for a TheTVDB series id, or `nil` when unknown locally.
    func tvMazeID(forTVDBID id: Int) async -> Int? {
        await record(forTVDBID: id)?.tvMazeID
    }
}

//
//  ShowIDMappingMetadata.swift
//  NextSeason
//

/// Cursor for a partially drained `/updates/shows` pass (newest-first).
///
/// Remaining work is every update strictly older than this point in
/// `(updatedAt desc, showID desc)` order.
nonisolated struct ShowIDMappingResumeCursor: Equatable, Sendable {
    let updatedAt: Date
    let showID: Int
}

/// Sync / generation metadata stored alongside TVDB↔TVMaze mappings.
nonisolated struct ShowIDMappingMetadata: Equatable, Sendable {
    /// On-disk schema version for the show ID mapping SQLite file.
    var schemaVersion: Int
    /// When the bundled (or fully regenerated) snapshot was produced (UTC).
    var generatedAt: Date?
    /// Highest TVMaze show id represented in the local mapping.
    var highestTVMazeID: Int
    /// Upper watermark of the last fully completed updates sync.
    var lastSuccessfulSyncAt: Date?
    /// Fixed start time of the in-progress sync. Updates after this are deferred
    /// until the next sync so a multi-pass drain cannot skip mid-flight changes.
    var syncHorizonAt: Date?
    /// When set, an updates pass was capped mid-way and should resume next opportunity.
    var updatesResumeCursor: ShowIDMappingResumeCursor?

    /// True while a sync was started but has not yet committed its horizon.
    var hasInProgressSync: Bool {
        syncHorizonAt != nil || updatesResumeCursor != nil
    }

    static let currentSchemaVersion = 2
}

//
//  InMemoryShowIDMapping.swift
//  NextSeason
//

/// Mutable in-memory show ID map for unit tests and UI-test stubs.
actor InMemoryShowIDMapping: ShowIDMapping {
    private var records: [Int: ShowIDMappingRecord]
    private(set) var metadata: ShowIDMappingMetadata

    /// Id-only map; display fields start empty (typical UI-test stub).
    init(
        map: [Int: Int] = [:],
        metadata: ShowIDMappingMetadata = ShowIDMappingMetadata(
            schemaVersion: ShowIDMappingMetadata.currentSchemaVersion,
            generatedAt: nil,
            highestTVMazeID: 0,
            lastSuccessfulSyncAt: nil,
            syncHorizonAt: nil,
            updatesResumeCursor: nil
        )
    ) {
        self.records = map.mapValues {
            ShowIDMappingRecord(tvMazeID: $0, name: nil, posterMediumURL: nil)
        }
        self.metadata = metadata
    }

    /// Pre-seeded records including TVMaze title/poster (overlay tests).
    init(
        records: [Int: ShowIDMappingRecord],
        metadata: ShowIDMappingMetadata = ShowIDMappingMetadata(
            schemaVersion: ShowIDMappingMetadata.currentSchemaVersion,
            generatedAt: nil,
            highestTVMazeID: 0,
            lastSuccessfulSyncAt: nil,
            syncHorizonAt: nil,
            updatesResumeCursor: nil
        )
    ) {
        self.records = records
        self.metadata = metadata
    }

    func record(forTVDBID id: Int) async -> ShowIDMappingRecord? {
        records[id]
    }

    func tvdbID(forTVMazeID id: Int) async -> Int? {
        records.filter { $0.value.tvMazeID == id }.map(\.key).min()
    }

    /// Inserts or replaces a mapping and bumps `highestTVMazeID` when needed.
    /// Nil display fields keep any values already stored for this TheTVDB id.
    func upsert(
        tvdbID: Int,
        tvMazeID: Int,
        name: String? = nil,
        posterMediumURL: URL? = nil
    ) {
        let existing = records[tvdbID]
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        records[tvdbID] = ShowIDMappingRecord(
            tvMazeID: tvMazeID,
            name: (trimmedName?.isEmpty == false) ? trimmedName : existing?.name,
            posterMediumURL: posterMediumURL ?? existing?.posterMediumURL
        )
        if tvMazeID > metadata.highestTVMazeID {
            metadata.highestTVMazeID = tvMazeID
        }
    }

    func removeMapping(forTVDBID tvdbID: Int) {
        records.removeValue(forKey: tvdbID)
    }

    func removeMappings(forTVMazeID tvMazeID: Int) {
        records = records.filter { $0.value.tvMazeID != tvMazeID }
    }

    /// Same clear-then-upsert semantics as `ShowIDMappingDatabase.applyMapping`.
    func applyMapping(
        tvMazeID: Int,
        tvdbID: Int?,
        name: String? = nil,
        posterMediumURL: URL? = nil
    ) {
        removeMappings(forTVMazeID: tvMazeID)
        if let tvdbID, tvdbID > 0 {
            upsert(
                tvdbID: tvdbID,
                tvMazeID: tvMazeID,
                name: name,
                posterMediumURL: posterMediumURL
            )
        }
    }

    func setLastSuccessfulSyncAt(_ date: Date) {
        metadata.lastSuccessfulSyncAt = date
    }

    func setHighestTVMazeID(_ value: Int) {
        metadata.highestTVMazeID = value
    }

    /// Snapshot of TheTVDB → TVMaze ids for test assertions.
    func allMappings() -> [Int: Int] {
        records.mapValues(\.tvMazeID)
    }
}

//
//  SearchViewModel.swift
//  NextSeason
//

/// Debounced TheTVDB title search for `SearchView`, with local show ID mapping
/// filtering and TVMaze resolution on select.
///
/// Intended to be driven by `.task(id: query)`: each keystroke cancels the prior
/// task, and `search()` sleeps for `debounce` before hitting the network — so
/// rapid typing only fetches the final query.
///
/// Provider split:
/// - **Search list** — TheTVDB hits (`TVDBSearchResult`), paginated, then filtered
///   through the local TVDB↔TVMaze show ID mapping (not a TVMaze network
///   lookup per hit). Mapped rows overlay TVMaze title and poster from the
///   snapshot. Pages are advanced until a reasonable actionable batch is
///   collected or TheTVDB results are exhausted.
/// - **Open / track** — resolve to a TVMaze `Show` first, then use the existing
///   detail and watchlist flows unchanged (those still key off TVMaze ids).
///
/// `displayedQuery` is the trimmed query that produced the current `.results` or
/// `.empty` outcome. When `.task` re-runs with the same text (e.g. returning from
/// show detail), `search()` skips the loading flash and keeps that outcome.
/// Failures clear `displayedQuery` so a retry is not short-circuited.
@Observable
@MainActor
final class SearchViewModel {
    /// Visible page of actionable TheTVDB hits plus whether "Load more" should appear.
    struct ResultsPage: Equatable {
        var items: [TVDBSearchResult]
        var hasMore: Bool
    }

    /// Search screen outcome driven by `.task(id: query)` and load-more.
    enum State: Equatable {
        case idle
        case loading
        case results(ResultsPage)
        case empty
        case failed(String)
    }

    /// Soft target for how many actionable rows to gather before stopping page fill.
    nonisolated static let actionablePageTarget = TheTVDBConfiguration.pageSize
    /// Cap on TheTVDB pages fetched per search / load-more burst.
    nonisolated static let maxTheTVDBPagesPerFill = 6

    private(set) var state: State = .idle
    var query: String = ""
    /// TheTVDB series ids currently resolving to TVMaze (row / navigation lock).
    private(set) var resolvingResultIDs: Set<Int> = []
    /// User-facing error from a failed resolve or load-more (alert).
    private(set) var resolveErrorMessage: String?
    /// True while a "Load more" request is in flight.
    private(set) var isLoadingMore = false

    private let searchService: any TheTVDBService
    private let tvMaze: any TVMazeService
    private let showIDMapping: any ShowIDMapping
    private let analytics: any AnalyticsTracking
    private let debounce: Duration
    /// Trimmed query that produced the current `.results` or `.empty` state; `nil`
    /// while idle, loading, or after a failed search.
    private var displayedQuery: String?
    /// Next TheTVDB `offset` for the active `displayedQuery` (sum of fetched counts).
    private var nextOffset = 0
    /// Cache of TheTVDB series id → TVMaze show id from the local mapping.
    /// Used for search-row stars without network prefetch.
    private var resolvedTVMazeIDsByTVDBID: [Int: Int] = [:]
    /// Cache of full TVMaze shows after an explicit open/track resolve.
    private var resolvedShowsByTVDBID: [Int: Show] = [:]

    init(
        searchService: any TheTVDBService,
        tvMaze: any TVMazeService,
        showIDMapping: any ShowIDMapping,
        analytics: any AnalyticsTracking,
        debounce: Duration = .milliseconds(300)
    ) {
        self.searchService = searchService
        self.tvMaze = tvMaze
        self.showIDMapping = showIDMapping
        self.analytics = analytics
        self.debounce = debounce
    }

    /// Runs the current `query`. Intended to be driven by `.task(id: query)`,
    /// which cancels the previous run when the text changes, giving us debounce.
    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .idle
            displayedQuery = nil
            nextOffset = 0
            isLoadingMore = false
            return
        }

        do {
            try await Task.sleep(for: debounce)
        } catch {
            return  // superseded by a newer query
        }

        // `.task(id: query)` runs again when returning from show detail; keep
        // existing results instead of flashing the loading placeholder.
        if trimmed == displayedQuery, isShowingSearchOutcome {
            return
        }

        state = .loading
        isLoadingMore = false
        nextOffset = 0
        resolvedTVMazeIDsByTVDBID.removeAll(keepingCapacity: true)
        resolvedShowsByTVDBID.removeAll(keepingCapacity: true)
        let searchStarted = Date.now
        AppDiagnosticsLogger.breadcrumb("search_viewmodel_start")
        do {
            let fill = try await collectActionableResults(
                matching: trimmed,
                startingOffset: 0,
                existingIDs: [],
                targetCount: Self.actionablePageTarget
            )
            guard !Task.isCancelled else {
                AppDiagnosticsLogger.logTaskCancel("search_viewmodel")
                return
            }
            let durationMs = Int(Date.now.timeIntervalSince(searchStarted) * 1000)
            displayedQuery = trimmed
            nextOffset = fill.nextOffset
            if fill.items.isEmpty, !fill.hasMore {
                state = .empty
                analytics.track(
                    .searchPerformed(
                        queryLength: trimmed.count,
                        resultCount: 0,
                        durationMs: max(durationMs, 0),
                        outcome: .empty
                    )
                )
                analytics.track(.emptySearchResultsShown)
            } else {
                // Empty items with hasMore means the page-fill cap found nothing
                // actionable yet, but TheTVDB still has pages — keep Load More.
                state = .results(ResultsPage(items: fill.items, hasMore: fill.hasMore))
                analytics.track(
                    .searchPerformed(
                        queryLength: trimmed.count,
                        resultCount: fill.items.count,
                        durationMs: max(durationMs, 0),
                        outcome: fill.items.isEmpty ? .empty : .results
                    )
                )
            }
        } catch is CancellationError {
            AppDiagnosticsLogger.logTaskCancel("search_viewmodel")
            return
        } catch {
            guard !Task.isCancelled else {
                AppDiagnosticsLogger.logTaskCancel("search_viewmodel")
                return
            }
            let durationMs = Int(Date.now.timeIntervalSince(searchStarted) * 1000)
            displayedQuery = nil
            nextOffset = 0
            state = .failed(error.localizedDescription)
            analytics.track(
                .searchPerformed(
                    queryLength: trimmed.count,
                    resultCount: 0,
                    durationMs: max(durationMs, 0),
                    outcome: .failed
                )
            )
            analytics.trackNonFatalError(error, context: "search")
        }
    }

    /// Appends another batch of actionable TheTVDB hits for the current query.
    ///
    /// Continues requesting TheTVDB pages (with a safety cap) until enough
    /// locally mappable results are gathered or TheTVDB has no more pages.
    func loadMore() async {
        guard case .results(let page) = state, page.hasMore, !isLoadingMore else { return }
        let trimmed = displayedQuery ?? query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let existingIDs = Set(page.items.map(\.id))
            let fill = try await collectActionableResults(
                matching: trimmed,
                startingOffset: nextOffset,
                existingIDs: existingIDs,
                targetCount: Self.actionablePageTarget
            )
            guard !Task.isCancelled else { return }
            guard case .results(let current) = state else { return }

            var merged = current.items
            for result in fill.items where !existingIDs.contains(result.id) {
                merged.append(result)
            }
            nextOffset = fill.nextOffset
            if merged.isEmpty, !fill.hasMore {
                state = .empty
                analytics.track(.emptySearchResultsShown)
            } else {
                state = .results(ResultsPage(items: merged, hasMore: fill.hasMore))
            }
        } catch is CancellationError {
            return
        } catch {
            analytics.trackNonFatalError(error, context: "search_load_more")
            presentResolveError(error.localizedDescription)
        }
    }

    /// Resolves a TheTVDB hit to the canonical TVMaze `Show` (with seasons when possible).
    ///
    /// Uses the in-memory show cache when present. Otherwise prefers the local
    /// mapped id (`show(id:)`), then live TheTVDB lookup if that mapping
    /// is missing or stale.
    func resolveShow(for result: TVDBSearchResult) async throws -> Show {
        if let cached = resolvedShowsByTVDBID[result.id] {
            return try await enrichedShow(from: cached)
        }

        resolvingResultIDs.insert(result.id)
        defer { resolvingResultIDs.remove(result.id) }

        let lookedUp = try await lookupTVMazeShow(for: result)
        resolvedShowsByTVDBID[result.id] = lookedUp
        resolvedTVMazeIDsByTVDBID[result.id] = lookedUp.id
        return try await enrichedShow(from: lookedUp)
    }

    /// TVMaze show id known for a TheTVDB hit (local mapping / prior resolve).
    func resolvedTVMazeID(for resultID: Int) -> Int? {
        resolvedTVMazeIDsByTVDBID[resultID] ?? resolvedShowsByTVDBID[resultID]?.id
    }

    /// Clears the resolve / load-more alert message.
    func clearResolveError() {
        resolveErrorMessage = nil
    }

    /// Surfaces a resolve / follow-up failure on the search screen alert.
    func presentResolveError(_ message: String) {
        resolveErrorMessage = message
    }

    // MARK: - Show ID mapping

    private struct ActionableFill {
        var items: [TVDBSearchResult]
        var nextOffset: Int
        var hasMore: Bool
    }

    /// Fetches TheTVDB pages and keeps only hits present in the local
    /// TVDB→TVMaze show ID mapping.
    private func collectActionableResults(
        matching query: String,
        startingOffset: Int,
        existingIDs: Set<Int>,
        targetCount: Int
    ) async throws -> ActionableFill {
        var collected: [TVDBSearchResult] = []
        var seen = existingIDs
        var offset = startingOffset
        var pagesFetched = 0
        var tvdbHasMore = true

        while collected.count < targetCount, tvdbHasMore, pagesFetched < Self.maxTheTVDBPagesPerFill
        {
            try Task.checkCancellation()
            let previousOffset = offset
            let page = try await searchService.searchSeries(matching: query, offset: offset)
            pagesFetched += 1
            // Trust the service's cursor — it advances by raw API row count, not
            // domain `results.count` after sparse records are dropped.
            offset = page.nextOffset
            tvdbHasMore = page.hasMore

            // Refuse to spin if a page claims more results but did not advance.
            if page.hasMore, offset <= previousOffset {
                tvdbHasMore = false
                break
            }

            let actionable = await filterActionable(page.results)
            for result in actionable where !seen.contains(result.id) {
                seen.insert(result.id)
                collected.append(result)
                if collected.count >= targetCount { break }
            }

            // Stop when TheTVDB reports exhaustion even if under target — do not
            // keep requesting solely to chase an arbitrary count.
            if !page.hasMore { break }
        }

        return ActionableFill(items: collected, nextOffset: offset, hasMore: tvdbHasMore)
    }

    /// Keeps only hits present in the local show ID mapping, overlays TVMaze
    /// title/poster, and caches TVMaze ids for row stars / later resolve.
    private func filterActionable(_ results: [TVDBSearchResult]) async -> [TVDBSearchResult] {
        var actionable: [TVDBSearchResult] = []
        actionable.reserveCapacity(results.count)

        for result in results {
            guard let record = await showIDMapping.record(forTVDBID: result.id) else {
                continue
            }
            resolvedTVMazeIDsByTVDBID[result.id] = record.tvMazeID
            actionable.append(result.overlayingTVMazeDisplayFields(record))
        }

        return actionable
    }

    /// Resolves a hit to TVMaze: cached/local mapping → `show(id:)`, then
    /// `lookupShow(theTVDBID:)` if the mapping is missing or the mapped show 404s.
    private func lookupTVMazeShow(for result: TVDBSearchResult) async throws -> Show {
        let mappedID: Int?
        if let cached = resolvedTVMazeIDsByTVDBID[result.id] {
            mappedID = cached
        } else {
            mappedID = await showIDMapping.tvMazeID(forTVDBID: result.id)
        }

        if let mappedID {
            do {
                return try await tvMaze.show(id: mappedID)
            } catch TVMazeError.notFound {
                // Mapping may be stale; fall through to live TheTVDB lookup.
            }
        }

        return try await tvMaze.lookupShow(theTVDBID: result.id)
    }

    /// Lookup / index payloads may omit embeds; fetch full detail when seasons
    /// are missing so tracking / detail have next-season inputs immediately.
    private func enrichedShow(from show: Show) async throws -> Show {
        if !show.seasons.isEmpty { return show }
        return try await tvMaze.show(id: show.id)
    }

    private var isShowingSearchOutcome: Bool {
        switch state {
        case .results, .empty:
            true
        default:
            false
        }
    }
}

//
//  WatchlistRepository.swift
//  NextSeason
//

/// Persistence boundary for saved shows. View models depend on this protocol, not
/// on SwiftData directly (PD-007).
///
/// Production: `SwiftDataWatchlistRepository`. UI tests / previews:
/// `InMemoryWatchlistRepository`.
///
/// "Saved" queries (`all`, `trackedShow`, `trackedShowIDs`, `contains`) include
/// paused shows — a paused show is still on the Watchlist. Use `activeShowIDs()`
/// for anything that means "actively tracked" (free-limit count, star state).
@MainActor
protocol WatchlistRepository: AnyObject {
    /// All saved shows (active and paused), newest `dateAdded` first.
    func all() async throws -> [TrackedShow]
    func trackedShow(showID: Int) async throws -> TrackedShow?
    /// IDs of every saved show, including paused ones.
    func trackedShowIDs() async throws -> Set<Int>
    /// True when the show is saved, including when it is paused.
    func contains(showID: Int) async throws -> Bool
    /// IDs of saved shows that are not paused.
    func activeShowIDs() async throws -> Set<Int>
    /// Insert from a fully loaded `Show`. A second add of an active show is a
    /// no-op; adding a paused show reactivates that row (keeping its original
    /// `dateAdded`) with fresh show data instead of creating a duplicate.
    func add(_ show: Show) async throws
    /// No-op when the ID is not present.
    func remove(showID: Int) async throws
    /// Writes refresh / notification-debounce fields onto an existing row.
    /// Never changes `isPaused`.
    func updateAfterRefresh(_ tracked: TrackedShow) async throws
    /// Sets `isPaused` on the given saved rows; missing IDs are ignored.
    func setPaused(_ isPaused: Bool, showIDs: Set<Int>) async throws
}

extension WatchlistRepository {
    /// Default derived from `all()`; production overrides with a direct query.
    func activeShowIDs() async throws -> Set<Int> {
        Set(try await all().filter { !$0.isPaused }.map(\.id))
    }
}

//
//  InMemoryWatchlistRepository.swift
//  NextSeason
//

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
}

//
//  WatchlistPendingRemoval.swift
//  NextSeason
//

/// Holds a watchlist removal undo window, shared by the watchlist list, show
/// detail, and search flows.
///
/// Two presentation modes:
/// - **Deferred** (star / detail / search): row stays until the window ends or
///   the user confirms; persistence runs on commit.
/// - **Immediate** (swipe-to-delete): persistence runs right away and the toast
///   is informational; Undo restores the show.
@Observable
@MainActor
final class WatchlistPendingRemoval {
    private enum Mode {
        case deferred
        case immediate
    }

    private(set) var pendingRemoval: TrackedShow?
    /// Set when deferred persistence fails after the undo window ends.
    private(set) var removalErrorMessage: String?

    /// Increments whenever `lastOutcome` changes so SwiftUI can observe outcomes.
    private(set) var outcomeGeneration = 0
    private(set) var lastOutcome: PendingRemovalOutcome?

    static var undoWindowSeconds: TimeInterval {
        AccessibilityPreferences.undoRemovalWindowSeconds()
    }

    private let repository: any WatchlistRepository
    private let analytics: any AnalyticsTracking
    private var commitRemovalTask: Task<Void, Never>?
    private var pendingRemovalSource: WatchlistActionSource?
    private var pendingMode: Mode = .deferred
    private var outcomeHandlers: [@MainActor (PendingRemovalOutcome) -> Void] = []

    /// Test override for the undo window; nil uses the accessibility-aware default.
    var undoWindowSecondsOverride: TimeInterval?

    private var undoWindowSeconds: TimeInterval {
        undoWindowSecondsOverride ?? Self.undoWindowSeconds
    }

    init(repository: any WatchlistRepository, analytics: any AnalyticsTracking) {
        self.repository = repository
        self.analytics = analytics
    }

    /// Registers a handler invoked on every significant pending-removal transition.
    func addOutcomeHandler(_ handler: @escaping @MainActor (PendingRemovalOutcome) -> Void) {
        outcomeHandlers.append(handler)
    }

    func clearRemovalError() {
        removalErrorMessage = nil
    }

    /// Removes `tracked` from persistence only after the undo window expires or
    /// `commitPendingRemovalIfNeeded()` runs.
    func requestRemoval(
        _ tracked: TrackedShow,
        source: WatchlistActionSource
    ) {
        commitRemovalTask?.cancel()
        AppDiagnosticsLogger.logTaskCancel("undo_removal_timer")
        removalErrorMessage = nil

        // Only one undo window at a time: finalize the previous show so its
        // removal is not lost when the user untracks another.
        finalizeReplacedPendingRemoval()

        pendingMode = .deferred
        pendingRemovalSource = source
        performRequestRemoval(tracked)
    }

    /// Persists removal immediately, then shows the undo toast. Undo restores
    /// the show to the repository; OK / timeout only dismisses the toast.
    ///
    /// Callers should update list UI synchronously before invoking this so
    /// `List` + `.onDelete` stay consistent.
    func requestImmediateRemoval(
        _ tracked: TrackedShow,
        source: WatchlistActionSource
    ) {
        commitRemovalTask?.cancel()
        AppDiagnosticsLogger.logTaskCancel("undo_removal_timer")
        removalErrorMessage = nil

        finalizeReplacedPendingRemoval()

        pendingMode = .immediate
        pendingRemovalSource = source
        pendingRemoval = tracked

        AppDiagnosticsLogger.logTaskStart("immediate_removal")
        commitRemovalTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.repository.remove(showID: tracked.id)
                self.analytics.track(.watchlistRemoved(source: source, showID: tracked.id))
                self.emitOutcome(.committed(showID: tracked.id))
            } catch {
                self.analytics.trackNonFatalError(error, context: "watchlist_remove")
                self.removalErrorMessage = WatchlistTracking.updateFailedMessage
                self.clearPendingPresentation()
                self.emitOutcome(.failed(showID: tracked.id))
                AppDiagnosticsLogger.logTaskComplete("immediate_removal")
                return
            }

            // Informational toast window — dismiss only; already persisted.
            try? await Task.sleep(for: .seconds(self.undoWindowSeconds))
            guard !Task.isCancelled else {
                AppDiagnosticsLogger.logTaskCancel("immediate_removal")
                return
            }
            guard self.pendingRemoval?.id == tracked.id else { return }
            self.clearPendingPresentation()
            AppDiagnosticsLogger.logTaskComplete("immediate_removal")
        }
    }

    /// Cancels a deferred removal, or restores an immediately deleted show.
    @discardableResult
    func undoRemoval() async -> TrackedShow? {
        commitRemovalTask?.cancel()
        commitRemovalTask = nil
        guard let tracked = pendingRemoval else { return nil }
        let showID = tracked.id
        let mode = pendingMode

        if mode == .immediate {
            do {
                try await restore(tracked)
            } catch {
                analytics.trackNonFatalError(error, context: "watchlist_restore")
                removalErrorMessage = WatchlistTracking.updateFailedMessage
                return nil
            }
        }

        clearPendingPresentation()
        emitOutcome(.undone(showID: showID))
        return tracked
    }

    /// Dismisses the toast when navigating away. Deferred removals are cancelled
    /// (still persisted, so the show stays tracked). Immediate removals keep the
    /// delete and only hide the toast.
    func dismissPendingRemovalForNavigation() {
        guard let tracked = pendingRemoval else { return }
        let showID = tracked.id
        let mode = pendingMode
        commitRemovalTask?.cancel()
        commitRemovalTask = nil
        clearPendingPresentation()
        if mode == .deferred {
            emitOutcome(.cancelled(showID: showID))
        }
    }

    /// Forces any in-flight undoable removal to its terminal state (e.g. before
    /// refresh or leaving a screen where the toast would otherwise outlive the
    /// context). Deferred: persists. Immediate: dismisses toast only.
    func commitPendingRemovalIfNeeded() async {
        await commitPendingRemoval(cancelTimer: true)
    }

    /// OK button entry point: cancels the undo timer and dismisses the toast on
    /// the tap turn, then persists in a follow-up task.
    ///
    /// Prefer this over `Task { await commitPendingRemovalIfNeeded() }` from a
    /// button action so a delayed MainActor hop cannot leave the toast visible
    /// until the timer fires.
    func confirmPendingRemoval() {
        guard let work = beginCommit(cancelTimer: true) else { return }
        Task { [weak self] in
            await self?.persistRemoval(
                work.tracked,
                source: work.source,
                outcome: .committed(showID: work.showID)
            )
        }
    }

    private func finalizeReplacedPendingRemoval() {
        guard let pending = pendingRemoval else { return }
        let previous = pending
        let previousSource = pendingRemovalSource ?? .watchlist
        let previousMode = pendingMode
        clearPendingPresentation()

        if previousMode == .deferred {
            Task { [weak self] in
                await self?.persistRemoval(
                    previous,
                    source: previousSource,
                    outcome: .replaced(showID: previous.id)
                )
            }
        }
        // Immediate replacements are already persisted; nothing to do.
    }

    private func performRequestRemoval(_ tracked: TrackedShow) {
        pendingRemoval = tracked

        AppDiagnosticsLogger.logTaskStart("undo_removal_timer")
        commitRemovalTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.undoWindowSeconds))
            guard !Task.isCancelled else {
                AppDiagnosticsLogger.logTaskCancel("undo_removal_timer")
                return
            }
            // Do not cancel this task from inside `commitPendingRemoval` — a
            // cancellation-aware repository would otherwise abort the remove.
            await self.commitPendingRemoval(cancelTimer: false)
            AppDiagnosticsLogger.logTaskComplete("undo_removal_timer")
        }
    }

    private func commitPendingRemoval(cancelTimer: Bool) async {
        guard let work = beginCommit(cancelTimer: cancelTimer) else { return }
        await persistRemoval(
            work.tracked,
            source: work.source,
            outcome: .committed(showID: work.showID)
        )
    }

    /// Snapshot of a deferred removal that still needs persistence.
    private struct CommitWork {
        let tracked: TrackedShow
        let source: WatchlistActionSource
        let showID: Int
    }

    /// Cancels the undo timer (when requested) and clears toast presentation.
    /// Returns work to persist for deferred mode; `nil` when there is nothing
    /// left to write (no pending item, or immediate-mode dismiss-only).
    private func beginCommit(cancelTimer: Bool) -> CommitWork? {
        if cancelTimer {
            commitRemovalTask?.cancel()
        }
        commitRemovalTask = nil

        guard let tracked = pendingRemoval else { return nil }

        if pendingMode == .immediate {
            clearPendingPresentation()
            return nil
        }

        let source = pendingRemovalSource ?? .watchlist
        let showID = tracked.id

        // End the undo window as soon as commit begins so Undo cannot race with
        // an in-flight `repository.remove`.
        //
        // Note for future cloud / suspending persistence: clearing `pendingRemoval`
        // here means Search/Detail may refresh while the show is still persisted
        // and briefly treat it as tracked again. A richer model that distinguishes
        // `.pending` from `.committing(showID:)` would keep both states untracked
        // for effective-tracking until delete finishes. Not needed for the local
        // SwiftData repository, which completes remove before observation resumes.
        clearPendingPresentation()

        return CommitWork(tracked: tracked, source: source, showID: showID)
    }

    private func persistRemoval(
        _ tracked: TrackedShow,
        source: WatchlistActionSource,
        outcome: PendingRemovalOutcome
    ) async {
        // After the undo window ends, finish persistence even if the SwiftUI /
        // lifecycle task that started commit is cancelled (tab switch, refresh).
        await Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.repository.remove(showID: tracked.id)
                // Defensive: also covers the replace-pending path which persists a
                // prior show without going through `commitPendingRemoval`.
                if self.pendingRemoval?.id == tracked.id {
                    self.clearPendingPresentation()
                }
                self.analytics.track(.watchlistRemoved(source: source, showID: tracked.id))
                self.emitOutcome(outcome)
            } catch {
                // This task is unstructured, so caller cancellation should not
                // reach here. Any failure (including unexpected cancellation)
                // surfaces so the user can retry.
                self.analytics.trackNonFatalError(error, context: "watchlist_remove")
                self.removalErrorMessage = WatchlistTracking.updateFailedMessage
                if self.pendingRemoval?.id == tracked.id {
                    self.clearPendingPresentation()
                }
                self.emitOutcome(.failed(showID: tracked.id))
            }
        }.value
    }

    /// Re-inserts a previously tracked show, preserving next-season and refresh
    /// fields and its original `dateAdded` (so it is the same saved row again).
    private func restore(_ tracked: TrackedShow) async throws {
        try await repository.add(Show(tracked: tracked))
        try await repository.updateAfterRefresh(tracked)
        // Undoing a delete of a paused show must not reactivate it (or use a slot).
        if tracked.isPaused {
            try await repository.setPaused(true, showIDs: [tracked.id])
        }
    }

    private func clearPendingPresentation() {
        pendingRemoval = nil
        pendingRemovalSource = nil
        pendingMode = .deferred
    }

    private func emitOutcome(_ outcome: PendingRemovalOutcome) {
        lastOutcome = outcome
        outcomeGeneration += 1
        for handler in outcomeHandlers {
            handler(outcome)
        }
    }
}

//
//  PendingRemovalOutcome.swift
//  NextSeason
//

/// Terminal or significant transitions for the single pending watchlist removal.
///
/// Callers should react to these outcomes instead of inferring undo vs. commit
/// from `pendingRemoval` clearing or by querying persistence.
enum PendingRemovalOutcome: Equatable {
    /// Deferred removal was persisted, or an immediate removal finished persisting.
    case committed(showID: Int)
    /// User restored the show (deferred cancel or immediate undo-after-delete).
    case undone(showID: Int)
    /// Deferred removal was cancelled without persisting (e.g. navigating to Show Detail).
    case cancelled(showID: Int)
    /// A new pending removal committed this show before its undo window ended.
    case replaced(showID: Int)
    /// Persistence failed after the undo window ended or during immediate delete.
    case failed(showID: Int)
}

//
//  WatchlistRefreshService.swift
//  NextSeason
//

/// Human-readable summary of one refresh pass (diagnostics / beta tooling).
struct WatchlistRefreshOutcome: Sendable, Equatable {
    let fetchResult: String
    let notificationDecision: String
}

/// Polls TVMaze for watchlist changes, updates persisted next-season status, and
/// delivers local notifications when `StatusChangeDetector` says a change is
/// worth alerting (PD-008 debounce / dedupe).
///
/// Pipeline for each refresh:
/// 1. Load tracked shows from the repository, excluding paused shows.
/// 2. Unless `force`, ask TVMaze which show IDs changed since the oldest check
///    (`/updates/shows`), then skip shows that neither changed on the server nor
///    need a calendar/status recheck.
/// 3. For each show that needs work: confirm it is still active, fetch full
///    detail, re-read the stored row (it may have been paused or updated while
///    the fetch was suspended), recompute `NextSeasonStatus`, run
///    `StatusChangeDetector.evaluate`, persist, and optionally deliver a
///    notification. Shows in `catchUpShowIDs` instead get a silent baseline.
///
/// Remains `@MainActor` because `WatchlistRepository` is MainActor-bound for
/// SwiftData; network work still runs off the actor while awaiting `TVMazeService`.
@MainActor
final class WatchlistRefreshService {
    private let tvMaze: any TVMazeService
    private let repository: any WatchlistRepository
    private let notifications: any NotificationDelivering
    private let analytics: any AnalyticsTracking
    private let diagnostics: BetaRefreshDiagnostics?
    /// Injectable time source so tests (and diagnostics) can pin the calendar used
    /// for status / policy decisions; production uses `{ .now }`.
    private let clock: @Sendable () -> Date
    /// Last time `refreshAllIfNeeded` actually ran a refresh (foreground throttle).
    private var lastForegroundRefreshAt: Date?
    /// Persists the catch-up marks.
    private let userDefaults: UserDefaults

    static let catchUpMarksKey = "watchlistCatchUpMarks"

    init(
        tvMaze: any TVMazeService,
        repository: any WatchlistRepository,
        notifications: any NotificationDelivering,
        analytics: any AnalyticsTracking,
        diagnostics: BetaRefreshDiagnostics? = nil,
        userDefaults: UserDefaults = .standard,
        clock: @escaping @Sendable () -> Date = { .now }
    ) {
        self.tvMaze = tvMaze
        self.repository = repository
        self.notifications = notifications
        self.analytics = analytics
        self.diagnostics = diagnostics
        self.userDefaults = userDefaults
        self.clock = clock
    }

    /// Resumed shows still awaiting a silent baseline, keyed by show ID, valued by
    /// the saved row's `dateAdded` (reference-date seconds).
    ///
    /// Persisted so an interrupted or failed catch-up is retried later, and so any
    /// refresh that reaches one of these shows first — including a notifying
    /// foreground or background refresh — baselines it instead of announcing
    /// changes that happened while it was paused. A mark is consumed when its
    /// baseline is written.
    ///
    /// The `dateAdded` ties a mark to one saved row: deleting a show and adding
    /// it again creates a new row (new `dateAdded`), so a leftover mark never
    /// silences the new row's updates. Undoing a delete restores the original
    /// `dateAdded`, so the mark still applies — even if a refresh ran while the
    /// row was deleted, because marks are pruned only when superseded by a new
    /// row, not when their row is temporarily absent.
    private var catchUpMarks: [Int: TimeInterval] {
        get {
            let stored = userDefaults.dictionary(forKey: Self.catchUpMarksKey) ?? [:]
            var marks: [Int: TimeInterval] = [:]
            for (key, value) in stored {
                if let id = Int(key), let dateAdded = value as? TimeInterval {
                    marks[id] = dateAdded
                }
            }
            return marks
        }
        set {
            if newValue.isEmpty {
                userDefaults.removeObject(forKey: Self.catchUpMarksKey)
            } else {
                let stored = Dictionary(
                    uniqueKeysWithValues: newValue.map { (String($0.key), $0.value) })
                userDefaults.set(stored, forKey: Self.catchUpMarksKey)
            }
        }
    }

    /// IDs of shows that still have a catch-up mark.
    var catchUpShowIDs: Set<Int> { Set(catchUpMarks.keys) }

    /// Marks resumed shows for a silent baseline. Call before persisting the
    /// resume so no refresh can see them active but unmarked.
    func markForCatchUp(_ shows: [TrackedShow]) {
        guard !shows.isEmpty else { return }
        var marks = catchUpMarks
        for show in shows {
            marks[show.id] = show.dateAdded.timeIntervalSinceReferenceDate
        }
        catchUpMarks = marks
    }

    /// Post-resume catch-up for just the resumed shows. Notifications are not
    /// turned off for the whole run: a still-marked show is baselined silently,
    /// but one whose mark another refresh already consumed is handled normally,
    /// so a genuinely new change found by a delayed catch-up still notifies.
    func catchUp(showIDs: Set<Int>) async {
        await refreshAll(force: true, onlyShowIDs: showIDs)
    }

    /// True when `row` is the same saved row that was marked for catch-up.
    private func needsCatchUp(_ row: TrackedShow) -> Bool {
        catchUpMarks[row.id] == row.dateAdded.timeIntervalSinceReferenceDate
    }

    /// Scene-active / foreground entry point: runs `refreshAll` only when
    /// `RefreshPolicy` says enough time has passed since the last foreground run.
    ///
    /// - Parameter prepare: Always awaited first, even when the policy then skips
    ///   the refresh. Production re-reads entitlements and reconciles pause state
    ///   here, so the refresh sees reconciled shows rather than pre-lapse state.
    func refreshAllIfNeeded(prepare: @MainActor () async -> Void = {}) async {
        await prepare()
        guard
            RefreshPolicy.shouldPerformForegroundRefresh(
                lastRefreshAt: lastForegroundRefreshAt,
                at: clock()
            )
        else {
            AppDiagnosticsLogger.logger(for: .cache).notice("watchlist_refresh_skipped policy")
            return
        }

        AppDiagnosticsLogger.breadcrumb("watchlist_refresh_foreground")
        await refreshAll(force: false)
        lastForegroundRefreshAt = clock()
    }

    /// Full watchlist refresh used by background tasks, pull-to-refresh, and
    /// `refreshAllIfNeeded`.
    ///
    /// - Parameter force: When true, re-fetches every tracked show instead of
    ///   consulting TVMaze's updates map.
    /// - Parameter deliverNotifications: When false, status is still updated and
    ///   dedupe signatures recorded, but no local notification is scheduled.
    ///   Use for interactive pull-to-refresh where the user can see the list.
    /// - Parameter recordDiagnostics: When true, writes a beta diagnostics sample.
    /// - Parameter onlyShowIDs: When set, refreshes just these shows (post-resume
    ///   catch-up) and leaves every other show for ordinary refreshes.
    /// - Returns: A summary of what happened, or `nil` if the run was cancelled.
    @discardableResult
    func refreshAll(
        force: Bool = false,
        deliverNotifications: Bool = true,
        recordDiagnostics: Bool = false,
        onlyShowIDs: Set<Int>? = nil
    ) async -> WatchlistRefreshOutcome? {
        AppDiagnosticsLogger.logger(for: .cache)
            .notice(
                "watchlist_refresh_start force=\(force, privacy: .public) notify=\(deliverNotifications, privacy: .public)"
            )
        AppDiagnosticsLogger.breadcrumb("watchlist_refresh_start")
        var fetchResult = String(localized: "Completed")
        // Last per-show notification decision string wins for the outcome summary.
        var lastNotificationDecision = String(
            localized: "No notification (no meaningful change)"
        )
        var refreshedShowCount = 0
        var skippedShowCount = 0

        let trackedShows: [TrackedShow]
        do {
            let savedShows = try await repository.all()
            // Drop a catch-up mark only once its show was added again as a new row
            // (same ID, different `dateAdded`). A mark whose row is merely absent
            // is kept: the deletion may still be undone, which restores the
            // original row, and the mark must still silence that row's history.
            // An absent row's mark is inert, since it matches no other row.
            let marks = catchUpMarks
            if !marks.isEmpty {
                let superseded = Set(
                    savedShows.filter { marks[$0.id] != nil && !needsCatchUp($0) }.map(\.id))
                if !superseded.isEmpty {
                    catchUpMarks = marks.filter { !superseded.contains($0.key) }
                }
            }
            // Paused shows (Plus lapsed, beyond the free limit) are never fetched
            // or notified; they also don't widen the updates window below.
            trackedShows = savedShows.filter { show in
                !show.isPaused && (onlyShowIDs?.contains(show.id) ?? true)
            }
        } catch {
            if error is CancellationError {
                AppDiagnosticsLogger.logTaskCancel("watchlist_refresh")
                return nil
            }
            analytics.trackNonFatalError(error, context: "watchlist_refresh_load")
            recordBackgroundDiagnosticsIfNeeded(
                recordDiagnostics,
                fetchResult: String(localized: "Failed to load watchlist"),
                notificationDecision: lastNotificationDecision
            )
            return WatchlistRefreshOutcome(
                fetchResult: String(localized: "Failed to load watchlist"),
                notificationDecision: lastNotificationDecision
            )
        }

        guard !trackedShows.isEmpty else {
            AppDiagnosticsLogger.logger(for: .cache).notice(
                "watchlist_refresh_complete empty_watchlist")
            AppDiagnosticsLogger.breadcrumb("watchlist_refresh_complete")
            let outcome = WatchlistRefreshOutcome(
                fetchResult: String(localized: "Skipped: empty watchlist"),
                notificationDecision: lastNotificationDecision
            )
            recordBackgroundDiagnosticsIfNeeded(
                recordDiagnostics,
                fetchResult: outcome.fetchResult,
                notificationDecision: outcome.notificationDecision
            )
            return outcome
        }

        // Map of showID → TVMaze "updated" timestamp. Empty when forcing a full pass.
        let updates: [Int: Date]
        if force {
            updates = [:]
        } else {
            // Grow the updates window with the largest polling gap so a delayed
            // background run still sees every change since we last checked.
            let oldestCheck = trackedShows.map(\.lastCheckedAt).min() ?? clock()
            let period = TVMazeUpdatePeriod.covering(since: oldestCheck, at: clock())
            do {
                updates = try await tvMaze.updatedShows(since: period)
            } catch {
                analytics.trackNonFatalError(error, context: "watchlist_refresh_updates")
                recordBackgroundDiagnosticsIfNeeded(
                    recordDiagnostics,
                    fetchResult: String(localized: "Failed to fetch TVMaze updates"),
                    notificationDecision: lastNotificationDecision
                )
                return WatchlistRefreshOutcome(
                    fetchResult: String(localized: "Failed to fetch TVMaze updates"),
                    notificationDecision: lastNotificationDecision
                )
            }
        }

        for snapshot in trackedShows {
            // Resumed shows awaiting their baseline are always fetched.
            if !force, !needsCatchUp(snapshot) {
                let serverChanged =
                    updates[snapshot.id].map { $0 > snapshot.sourceUpdatedAt } ?? false
                // `nextSeason` also depends on the calendar (airing → returning when a
                // season ends, scheduled → airing on premiere). Search-track used to
                // persist `.returningNoSeasonYet` without season data; re-check that
                // case even when TVMaze's `updated` epoch is unchanged.
                let needsRecheck = Self.needsCalendarOrStatusRecheck(snapshot.nextSeason)
                // A soft change seen once (PD-008) needs a second poll to confirm.
                // TVMaze's `updated` won't move again for the same data, so without
                // this the pending alert would wait for an unrelated server update.
                let awaitsConfirmation = snapshot.pendingChangeSignature != nil
                guard serverChanged || needsRecheck || awaitsConfirmation else {
                    skippedShowCount += 1
                    continue
                }
            }

            do {
                // The snapshot may be stale: a downgrade can pause a show (or the
                // user remove it) while earlier fetches are suspended.
                guard try await activeRow(for: snapshot.id) != nil else { continue }
                let show = try await tvMaze.show(id: snapshot.id, bypassCache: true)
                // Re-read after the fetch, which suspended: skip a show paused or
                // removed meanwhile, and evaluate against the latest signatures so an
                // overlapping refresh's baseline or debounce is not overwritten.
                guard var tracked = try await activeRow(for: snapshot.id) else { continue }
                // Overlapping requests can finish out of order. Never apply a
                // response older than the version already stored (TVMaze `updated`),
                // or it would overwrite a newer baseline and re-announce history.
                guard show.updatedAt >= tracked.sourceUpdatedAt else {
                    AppDiagnosticsLogger.breadcrumb("watchlist_refresh_stale_response:\(show.id)")
                    continue
                }
                tracked.isStale = false
                tracked.name = show.name
                tracked.posterMediumURL = show.posterMediumURL
                tracked.summaryHTML = show.summaryHTML
                tracked.tvMazeURL = show.tvMazeURL
                tracked.status = show.status
                tracked.sourceUpdatedAt = show.updatedAt

                // Pure status + notify decision; persistence and delivery follow.
                let newStatus = NextSeasonCalculator.status(for: show, at: clock())

                // Checked now, not at loop start, so a refresh already running when a
                // show was resumed still baselines it rather than notifying.
                if needsCatchUp(tracked) {
                    let baseline = StatusChangeDetector.baseline(
                        tracked: tracked, newStatus: newStatus, at: clock())
                    try await repository.updateAfterRefresh(baseline)
                    catchUpMarks[tracked.id] = nil
                    refreshedShowCount += 1
                    lastNotificationDecision = String(
                        localized:
                            "Catch-up for \(tracked.name): baseline recorded, no notification"
                    )
                    continue
                }

                let evaluation = StatusChangeDetector.evaluate(
                    tracked: tracked, newStatus: newStatus, at: clock())

                try await repository.updateAfterRefresh(evaluation.tracked)
                refreshedShowCount += 1
                lastNotificationDecision = Self.describeNotificationDecision(
                    for: tracked.name,
                    evaluation: evaluation,
                    deliverNotifications: deliverNotifications
                )
                if deliverNotifications, let notification = evaluation.notification {
                    await notifications.deliver(notification)
                }
            } catch is CancellationError {
                AppDiagnosticsLogger.logTaskCancel("watchlist_refresh_show")
                return nil
            } catch TVMazeError.notFound {
                // Show removed from TVMaze: keep the row but flag it stale, unless it
                // was paused or removed while the request was in flight.
                guard var tracked = try? await activeRow(for: snapshot.id) else { continue }
                tracked.isStale = true
                tracked.lastCheckedAt = clock()
                try? await repository.updateAfterRefresh(tracked)
                refreshedShowCount += 1
                lastNotificationDecision = String(
                    localized: "Marked stale: \(tracked.name) not found on TVMaze"
                )
            } catch {
                // Per-show failure: leave this row alone and continue the rest.
                analytics.trackNonFatalError(error, context: "watchlist_refresh_show")
                continue
            }
        }

        if refreshedShowCount == 0, skippedShowCount > 0 {
            fetchResult = String(
                localized: "No TVMaze changes for \(skippedShowCount) tracked show(s)"
            )
        } else {
            fetchResult = String(localized: "Refreshed \(refreshedShowCount) show(s)")
            if skippedShowCount > 0 {
                fetchResult += String(localized: ", skipped \(skippedShowCount) unchanged")
            }
            if force {
                fetchResult += String(localized: " (forced)")
            }
        }

        let outcome = WatchlistRefreshOutcome(
            fetchResult: fetchResult,
            notificationDecision: lastNotificationDecision
        )
        recordBackgroundDiagnosticsIfNeeded(
            recordDiagnostics,
            fetchResult: outcome.fetchResult,
            notificationDecision: outcome.notificationDecision
        )
        AppDiagnosticsLogger.logger(for: .cache).notice("watchlist_refresh_complete")
        AppDiagnosticsLogger.breadcrumb("watchlist_refresh_complete")
        return outcome
    }

    private func recordBackgroundDiagnosticsIfNeeded(
        _ recordDiagnostics: Bool,
        fetchResult: String,
        notificationDecision: String
    ) {
        guard recordDiagnostics else { return }
        diagnostics?.recordBackgroundRefreshCompleted(
            at: clock(),
            fetchResult: fetchResult,
            notificationDecision: notificationDecision
        )
    }

    /// Turns an evaluation into the short string shown in diagnostics outcomes.
    private static func describeNotificationDecision(
        for showName: String,
        evaluation: StatusChangeDetector.Evaluation,
        deliverNotifications: Bool
    ) -> String {
        if let notification = evaluation.notification {
            if deliverNotifications {
                return String(
                    localized: "Delivered for \(showName): \(notification.body)"
                )
            }
            return String(
                localized:
                    "Suppressed for \(showName) (interactive refresh): \(notification.body)"
            )
        }
        if evaluation.tracked.pendingChangeSignature != nil {
            return String(localized: "Pending debounce for \(showName)")
        }
        return String(
            localized: "No notification for \(showName) (no meaningful change)"
        )
    }

    /// The stored row when the show is still saved and not paused.
    private func activeRow(for showID: Int) async throws -> TrackedShow? {
        guard let row = try await repository.trackedShow(showID: showID), !row.isPaused else {
            return nil
        }
        return row
    }

    /// Statuses that can change without TVMaze bumping `updated` (calendar drift,
    /// or a previously incomplete `.returningNoSeasonYet` snapshot).
    private static func needsCalendarOrStatusRecheck(_ status: NextSeasonStatus) -> Bool {
        switch status {
        case .airing, .scheduled, .returningNoSeasonYet:
            true
        case .announcedUndated, .ended, .unknown:
            false
        }
    }
}

//
//  StatusChangeDetector.swift
//  NextSeason
//

/// Decides whether a next-season delta is worth notifying about and applies
/// PD-008 debounce rules before alerting.
nonisolated enum StatusChangeDetector {
    struct Evaluation: Sendable {
        var tracked: TrackedShow
        var notification: SeasonNotificationContent?
    }

    /// A stable string representing the current next-season state for dedup.
    static func signature(for status: NextSeasonStatus) -> String {
        switch status {
        case .airing(let season):
            "airing:\(season)"
        case .scheduled(let season, let premiere):
            "scheduled:\(season):\(premiere.timeIntervalSince1970)"
        case .announcedUndated(let season):
            "announcedUndated:\(season)"
        case .returningNoSeasonYet:
            "returningNoSeasonYet"
        case .ended:
            "ended"
        case .unknown:
            "unknown"
        }
    }

    /// Meaningful deltas from `TVMazeResearch.md` §5.
    static func isMeaningfulChange(from old: NextSeasonStatus, to new: NextSeasonStatus) -> Bool {
        guard old != new else { return false }

        switch (old, new) {
        case (.announcedUndated, .scheduled):
            return true
        case (.scheduled, .scheduled):
            return true
        case (_, .airing):
            return true
        case (_, .ended):
            return true
        case (.returningNoSeasonYet, .announcedUndated),
            (.returningNoSeasonYet, .scheduled):
            return true
        default:
            return false
        }
    }

    /// Changes backed by a concrete premiere or on-air evidence can notify immediately.
    static func isDateBacked(_ status: NextSeasonStatus) -> Bool {
        switch status {
        case .scheduled, .airing:
            return true
        default:
            return false
        }
    }

    /// Records `newStatus` as an already-announced baseline, with no notification.
    ///
    /// Used for shows resumed after a Plus lapse: whatever changed while they were
    /// paused is history, so the current state becomes the last-notified signature
    /// and any pending soft-change debounce is cleared. Later changes away from
    /// this baseline notify normally.
    static func baseline(tracked: TrackedShow, newStatus: NextSeasonStatus, at: Date = .now)
        -> TrackedShow
    {
        var updated = tracked
        updated.lastCheckedAt = at
        updated.nextSeason = newStatus
        updated.lastNotifiedSignature = signature(for: newStatus)
        updated.pendingChangeSignature = nil
        return updated
    }

    /// Updates local next-season state and decides whether to notify (PD-008).
    ///
    /// Always returns a tracked show with `lastCheckedAt` and `nextSeason` applied.
    /// A notification is included only when the delta is meaningful, not a duplicate
    /// of `lastNotifiedSignature`, and either date-backed (notify immediately) or
    /// confirmed across two consecutive polls (debounce soft changes).
    static func evaluate(tracked: TrackedShow, newStatus: NextSeasonStatus, at: Date = .now)
        -> Evaluation
    {
        let previousStatus = tracked.nextSeason
        var updated = tracked
        updated.lastCheckedAt = at
        updated.nextSeason = newStatus

        let changeSignature = signature(for: newStatus)

        // Debounce confirmed: a prior poll stashed this soft change as pending, and
        // this poll sees the same signature again — notify and clear pending.
        if tracked.pendingChangeSignature == changeSignature,
            changeSignature != tracked.lastNotifiedSignature
        {
            updated.lastNotifiedSignature = changeSignature
            updated.pendingChangeSignature = nil
            return Evaluation(
                tracked: updated,
                notification: SeasonNotificationContent(
                    showID: tracked.id, showName: tracked.name, status: newStatus)
            )
        }

        // Not a meaningful delta (or no change) — keep the UI current, no alert.
        guard isMeaningfulChange(from: previousStatus, to: newStatus) else {
            updated.pendingChangeSignature = nil
            return Evaluation(tracked: updated, notification: nil)
        }

        // Already notified for this exact next-season state — do not re-alert.
        if changeSignature == tracked.lastNotifiedSignature {
            updated.pendingChangeSignature = nil
            return Evaluation(tracked: updated, notification: nil)
        }

        // Date-backed (scheduled / airing): concrete enough to notify on first sight.
        if isDateBacked(newStatus) {
            updated.lastNotifiedSignature = changeSignature
            updated.pendingChangeSignature = nil
            return Evaluation(
                tracked: updated,
                notification: SeasonNotificationContent(
                    showID: tracked.id, showName: tracked.name, status: newStatus)
            )
        }

        // Soft meaningful change: wait for a second consecutive poll before notifying.
        updated.pendingChangeSignature = changeSignature
        return Evaluation(tracked: updated, notification: nil)
    }
}

nonisolated struct SeasonNotificationContent: Sendable {
    let showID: Int
    let showName: String
    let status: NextSeasonStatus

    /// The show name leads the notification so it's clear which show updated.
    var title: String { showName }

    var body: String {
        switch status {
        case .airing(let season):
            return String(localized: "Season \(season) is now airing.")
        case .scheduled(let season, let premiere):
            let date = premiere.formatted(date: .abbreviated, time: .omitted)
            return String(localized: "Season \(season) premieres \(date).")
        case .announcedUndated(let season):
            return String(localized: "Season \(season) announced — date to be confirmed.")
        case .returningNoSeasonYet:
            return String(localized: "Returning — watch for next season news.")
        case .ended:
            return String(localized: "This series has ended.")
        case .unknown:
            return String(localized: "There's a next season update.")
        }
    }
}

//
//  NextSeasonCalculator.swift
//  NextSeason
//

/// Derives a `NextSeasonStatus` from a show's status, seasons, and next episode.
///
/// TVMaze has no single "next season" field, so this is the one place that rule
/// lives. Pure and date-injectable (`at:`) so unit tests can pin the calendar;
/// shared by show detail, watchlist save, and `WatchlistRefreshService`.
///
/// Rerun-safe by construction: it keys only off original season premiere dates and
/// the next *unaired* episode, none of which a re-broadcast changes
/// (see `Documentation/TVMazeResearch.md` §6.3).
nonisolated enum NextSeasonCalculator {
    /// Priority order: dated upcoming season → next-episode hint → currently
    /// airing latest season → undated upcoming row → overall show status.
    ///
    /// - Parameter show: Domain show whose seasons and next episode drive the status.
    /// - Parameter at: Reference "today" for premiere / end comparisons (UTC days).
    static func status(for show: Show, at: Date = .now) -> NextSeasonStatus {
        // Ignore specials / season 0 for "next season" purposes.
        let seasons = show.seasons
            .filter { $0.number >= 1 }
            .sorted { $0.number < $1.number }

        let aired = seasons.filter { season in
            if let date = season.premiereDate { return TVMazeDate.isOnOrBefore(date, at) }
            return false
        }
        let latestAired = aired.last
        let latestAiredNumber = latestAired?.number ?? 0

        // Seasons numbered beyond the latest one that has actually aired.
        let upcoming = seasons.filter { $0.number > latestAiredNumber }

        // 1. A not-yet-aired season with a known future premiere date.
        let datedUpcoming =
            upcoming
            .compactMap { season -> (number: Int, date: Date)? in
                guard let date = season.premiereDate, TVMazeDate.isAfter(date, at) else {
                    return nil
                }
                return (season.number, date)
            }
            .sorted { $0.date < $1.date }
        if let next = datedUpcoming.first {
            return .scheduled(season: next.number, premiere: next.date)
        }

        // 2. The next episode points at a season beyond the latest aired one —
        //    useful when that new season has no dated row yet.
        if let episode = show.nextEpisode,
            let season = episode.season,
            season > latestAiredNumber
        {
            if let date = episode.airdate {
                if TVMazeDate.isAfter(date, at) {
                    guard episode.number == 1 else {
                        return .announcedUndated(season: season)
                    }
                    return .scheduled(season: season, premiere: date)
                }
                guard episode.number == 1 else {
                    return .announcedUndated(season: season)
                }
                return .airing(season: season)
            }
            // Next episode exists for a new season but no date yet — announced, not airing.
            return .announcedUndated(season: season)
        }

        // 3. The most recent season is currently airing (premiered, not yet ended).
        if show.status != .ended, let latest = latestAired {
            let hasEnded = latest.endDate.map { TVMazeDate.isBefore($0, at) } ?? false
            if !hasEnded {
                return .airing(season: latest.number)
            }
        }

        // 4. A future season row exists but has no date yet.
        if let undated = upcoming.first(where: { $0.premiereDate == nil }) {
            return .announcedUndated(season: undated.number)
        }

        // 5. Fall back to the show's overall status.
        switch show.status {
        case .running, .toBeDetermined, .inDevelopment:
            return .returningNoSeasonYet
        case .ended:
            return .ended
        case .unknown:
            return .unknown
        }
    }
}

//
//  RefreshPolicy.swift
//  NextSeason
//

/// Throttle rules for automatic foreground watchlist refresh.
///
/// Keeps scene-active refreshes from hammering TVMaze when the app is
/// backgrounded and resumed repeatedly; pull-to-refresh / `force` bypass this.
nonisolated enum RefreshPolicy {
    /// Minimum time between foreground-triggered refreshes.
    static let foregroundMinimumInterval: TimeInterval = 15 * 60

    /// `true` when there was never a foreground refresh, or enough time has passed.
    static func shouldPerformForegroundRefresh(
        lastRefreshAt: Date?,
        at: Date,
        minimumInterval: TimeInterval = foregroundMinimumInterval
    ) -> Bool {
        guard let lastRefreshAt else { return true }
        return at.timeIntervalSince(lastRefreshAt) >= minimumInterval
    }
}

//
//  WatchlistLimitPolicy.swift
//  NextSeason
//

/// Free-tier watchlist capacity and the rule for whether another show can be added.
nonisolated enum WatchlistLimitPolicy {
    /// Permanent free allowance. Paid or complimentary users are unlimited.
    static let freeShowLimit = 3

    /// Adds are allowed when the user has Plus (or complimentary access), or when the
    /// current *active* count is still below the free cap.
    ///
    /// A lapsed Plus user keeps every saved show; shows past the first
    /// `freeShowLimit` are paused (see `showIDsToPause`). Paused shows do not
    /// count, so deleting an active show frees a slot for a new or paused show.
    static func canAddShow(currentCount: Int, isUnlimited: Bool) -> Bool {
        isUnlimited || currentCount < freeShowLimit
    }

    /// Shows to pause when the user does not have Unlimited access.
    ///
    /// Acts only when more than `freeShowLimit` shows are active: the active shows
    /// with the oldest `dateAdded` (ties broken by ID, so the result is
    /// deterministic) stay active and the rest are paused. Already-paused shows
    /// are never considered, so a free user's own choices — deleting an active
    /// show, or reactivating a paused one into a free slot — are left alone.
    ///
    /// Repeated lapses: restoring Plus resumes everything, so the next lapse sees
    /// every saved show as active again and keeps the three oldest by original
    /// `dateAdded`. Reactivating a paused show keeps its original `dateAdded`, so
    /// selections made during an earlier free period are not remembered.
    static func showIDsToPause(in shows: [TrackedShow]) -> Set<Int> {
        let active = shows.filter { !$0.isPaused }
        guard active.count > freeShowLimit else { return [] }
        let oldestFirst = active.sorted {
            ($0.dateAdded, $0.id) < ($1.dateAdded, $1.id)
        }
        return Set(oldestFirst.dropFirst(freeShowLimit).map(\.id))
    }

    /// Shows to resume when the user has Unlimited access: every paused show.
    static func showIDsToResume(in shows: [TrackedShow]) -> Set<Int> {
        Set(shows.filter(\.isPaused).map(\.id))
    }
}

//
//  TVMazeDate.swift
//  NextSeason
//

/// Parses TVMaze date-only strings ("yyyy-MM-dd"). Implemented without a shared
/// `DateFormatter` so it is safe to call from any concurrency context.
///
/// TVMaze date-only fields represent calendar days in UTC. Comparisons against
/// `Date.now` should use the helpers below so a season ending "today" is not
/// treated as ended for most of that day.
nonisolated enum TVMazeDate {
    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// UTC calendar-day boundary for TVMaze date-only comparisons.
    static func startOfDayUTC(_ date: Date) -> Date {
        utcCalendar.startOfDay(for: date)
    }

    /// True when `date`'s calendar day is on or before `other`'s (UTC).
    static func isOnOrBefore(_ date: Date, _ other: Date) -> Bool {
        startOfDayUTC(date) <= startOfDayUTC(other)
    }

    /// True when `date`'s calendar day is strictly before `other`'s (UTC).
    static func isBefore(_ date: Date, _ other: Date) -> Bool {
        startOfDayUTC(date) < startOfDayUTC(other)
    }

    /// True when `date`'s calendar day is strictly after `other`'s (UTC).
    static func isAfter(_ date: Date, _ other: Date) -> Bool {
        startOfDayUTC(date) > startOfDayUTC(other)
    }

    /// Parses a TVMaze `"yyyy-MM-dd"` (or longer ISO) string as a UTC calendar date.
    static func dateOnly(_ string: String?) -> Date? {
        guard let string, string.count >= 10 else { return nil }
        let parts = string.prefix(10).split(separator: "-")
        guard parts.count == 3,
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            let day = Int(parts[2])
        else {
            return nil
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return utcCalendar.date(from: components)
    }
}

@MainActor protocol NotificationDelivering: AnyObject {
    func deliver(_ content: SeasonNotificationContent) async
}
@MainActor protocol AnalyticsTracking: AnyObject {
    func track(_ event: ReviewEvent)
    func trackNonFatalError(_ error: any Error, context: String)
}
enum ReviewEvent {
    case searchPerformed(
        queryLength: Int, resultCount: Int, durationMs: Int, outcome: ReviewOutcome)
    case emptySearchResultsShown
    case appOpenedFromNotification(showID: Int)
    case watchlistRemoved(source: WatchlistActionSource, showID: Int)
}
enum ReviewOutcome { case empty, results, failed }
enum WatchlistActionSource { case watchlist, search, detail }
@MainActor final class ReviewAnalytics: AnalyticsTracking {
    func track(_ event: ReviewEvent) {}
    func trackNonFatalError(_ error: any Error, context: String) {}
}
enum WatchlistTracking { static let updateFailedMessage = "failed" }
enum AccessibilityPreferences { static func undoRemovalWindowSeconds() -> TimeInterval { 300 } }
@MainActor final class BetaRefreshDiagnostics {
    func recordBackgroundRefreshCompleted(
        at: Date, fetchResult: String, notificationDecision: String
    ) {}
}
enum AppDiagnosticsLogger {
    enum Category: String { case cache, persistence, network, lifecycle }
    nonisolated static func logger(for category: Category) -> Logger {
        Logger(subsystem: "Review", category: category.rawValue)
    }
    nonisolated static func breadcrumb(_ message: String) {}
    nonisolated static func logTaskCancel(_ message: String) {}
    nonisolated static func logTaskStart(_ message: String) {}
    nonisolated static func logTaskComplete(_ message: String) {}
}
@MainActor final class ReviewNotifications: NotificationDelivering {
    var attempted = 0
    func deliver(_ content: SeasonNotificationContent) async { attempted += 1 }
}
nonisolated func hit(_ id: Int) -> TVDBSearchResult {
    TVDBSearchResult(
        id: id, name: "Hit \(id)", year: nil, network: nil, status: nil, posterURL: nil)
}
nonisolated func fixtureShow(_ id: Int) -> Show {
    Show(
        id: id, name: "Show \(id)", tvMazeURL: nil, summaryHTML: nil, posterMediumURL: nil,
        posterOriginalURL: nil, status: .running, premiered: nil, ended: nil, network: nil,
        genres: [], averageRuntime: nil, seasons: [], nextEpisode: nil,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
}
@MainActor final class ReviewMaze: TVMazeService {
    var detailFetches = 0
    var periods: [TVMazeUpdatePeriod] = []
    var allUpdateFetches = 0
    var result = fixtureShow(1)
    func searchShows(matching query: String) async throws -> [Show] { [] }
    func lookupShow(theTVDBID: Int) async throws -> Show { result }
    func show(id: Int, bypassCache: Bool) async throws -> Show {
        detailFetches += 1
        return result
    }
    func updatedShows(since period: TVMazeUpdatePeriod) async throws -> [Int: Date] {
        periods.append(period)
        return [:]
    }
    func allUpdatedShows() async throws -> [Int: Date] {
        allUpdateFetches += 1
        return [1: result.updatedAt]
    }
}
struct OverflowSearch: TheTVDBService {
    func searchSeries(matching query: String, offset: Int) async throws -> TheTVDBSearchPage {
        let ids = offset == 0 ? Array(1...10) : Array(11...20)
        return TheTVDBSearchPage(
            results: ids.map(hit), hasMore: offset == 0, nextOffset: offset + 10)
    }
}
@MainActor final class RacingSearch: TheTVDBService {
    var held: CheckedContinuation<TheTVDBSearchPage, Never>?
    var started: CheckedContinuation<Void, Never>?
    func searchSeries(matching query: String, offset: Int) async throws -> TheTVDBSearchPage {
        if query == "A", offset == 10 {
            return await withCheckedContinuation {
                held = $0
                started?.resume()
                started = nil
            }
        }
        let ids = query == "B" ? Array(101...110) : Array(1...10)
        return TheTVDBSearchPage(results: ids.map(hit), hasMore: query == "A", nextOffset: 10)
    }
    func waitUntilHeld() async {
        if held != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() {
        held?.resume(
            returning: TheTVDBSearchPage(
                results: Array(11...20).map(hit), hasMore: false, nextOffset: 20))
        held = nil
    }
}
@main struct ReviewHarness {
    @MainActor static func main() async throws {
        verifyMatrixLateFailure()
        try verifyEpisodeHint()
        try await verifyNavigation()
        try await verifyPersistence()
        try await verifyMappingResume()
        let analytics = ReviewAnalytics()
        let maze = ReviewMaze()
        let map = InMemoryShowIDMapping(
            map: Dictionary(uniqueKeysWithValues: (1...110).filter { $0 != 10 }.map { ($0, $0) }))
        let overflow = SearchViewModel(
            searchService: OverflowSearch(), tvMaze: maze, showIDMapping: map, analytics: analytics,
            debounce: .zero)
        overflow.query = "overflow"
        await overflow.search()
        if case .results(let page) = overflow.state {
            print(
                "SEARCH_OVERFLOW expected=19 actual=\(page.items.count) hasMore=\(page.hasMore) ids=\(page.items.map(\.id))"
            )
        }
        let service = RacingSearch()
        let fullMap = InMemoryShowIDMapping(
            map: Dictionary(uniqueKeysWithValues: (1...110).map { ($0, $0) }))
        let race = SearchViewModel(
            searchService: service, tvMaze: maze, showIDMapping: fullMap, analytics: analytics,
            debounce: .zero)
        race.query = "A"
        await race.search()
        let more = Task { await race.loadMore() }
        await service.waitUntilHeld()
        race.query = "B"
        await race.search()
        service.release()
        await more.value
        if case .results(let page) = race.state {
            print("SEARCH_RACE expected_B_only=\(Array(101...110)) actual=\(page.items.map(\.id))")
        }
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
        let date = TVMazeDate.dateOnly("2027-01-01")!
        print(
            "DATE_FORMAT source=2027-01-01 actual=\(date.formatted(date: .abbreviated, time: .omitted))"
        )
        let repo = InMemoryWatchlistRepository()
        for id in 1...3 { try await repo.add(fixtureShow(id)) }
        let removal = WatchlistPendingRemoval(repository: repo, analytics: analytics)
        let tracked = try await repo.trackedShow(showID: 1)!
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            removal.addOutcomeHandler { if $0 == .committed(showID: 1) { done.resume() } }
            removal.requestImmediateRemoval(tracked, source: .watchlist)
        }
        try await repo.add(fixtureShow(4))
        _ = await removal.undoRemoval()
        print(
            "UNDO_LIMIT expected_at_most=3 actual=\(try await repo.activeShowIDs().count) pausedOnReconcile=\(WatchlistLimitPolicy.showIDsToPause(in: try await repo.all()))"
        )
        let now = TVMazeDate.dateOnly("2026-10-12")!
        let old = now.addingTimeInterval(-90 * 86400)
        let undated = TrackedShow(
            id: 1, name: "Old", posterMediumURL: nil, status: .running,
            nextSeason: .announcedUndated(season: 2), sourceUpdatedAt: old, lastCheckedAt: old,
            dateAdded: old)
        let oldRepo = InMemoryWatchlistRepository(seed: [undated])
        let notifications = ReviewNotifications()
        let defaults = UserDefaults(suiteName: "NextSeason.ReviewHarness.\(UUID())")!
        let refresh = WatchlistRefreshService(
            tvMaze: maze, repository: oldRepo, notifications: notifications, analytics: analytics,
            userDefaults: defaults, clock: { now })
        await refresh.refreshAll()
        print(
            "LONG_ABSENCE period=\(maze.periods) fullUpdateFetches=\(maze.allUpdateFetches) showFetches=\(maze.detailFetches)"
        )
        let newStatus = NextSeasonStatus.scheduled(
            season: 2, premiere: now.addingTimeInterval(86400))
        let eval = StatusChangeDetector.evaluate(tracked: undated, newStatus: newStatus, at: now)
        let retry = StatusChangeDetector.evaluate(
            tracked: eval.tracked, newStatus: newStatus, at: now)
        print(
            "FAILED_DELIVERY firstAttempt=\(eval.notification != nil) retryAttempt=\(retry.notification != nil) signatureAlreadyRecorded=\(eval.tracked.lastNotifiedSignature != nil)"
        )
    }
}

//
//  ShowIDMappingDatabase.swift
//  NextSeason
//

/// Direct SQLite store for TheTVDB → TVMaze show ID mappings.
///
/// Intentionally not SwiftData: the data is relational, tiny, and updated
/// incrementally outside the watchlist persistence stack.
actor ShowIDMappingDatabase: ShowIDMapping {
    nonisolated static let bundledResourceName = "tvdb_tvmaze_show_id_mapping"
    nonisolated static let bundledResourceExtension = "sqlite"
    nonisolated static let writableFileName = "tvdb_tvmaze_show_id_mapping.sqlite"

    /// SQLite handle; `nonisolated(unsafe)` because `OpaquePointer` is not Sendable
    /// and actor `deinit` must close it without hopping.
    nonisolated(unsafe) private var db: OpaquePointer?
    private let fileURL: URL
    private let bundledURL: URL?

    init(fileURL: URL, bundledURL: URL?) throws {
        self.fileURL = fileURL
        self.bundledURL = bundledURL
        try Self.prepareWritableDatabase(at: fileURL, bundledURL: bundledURL)
        let opened = try Self.openDatabase(at: fileURL)
        try Self.migrateIfNeeded(opened)
        db = opened
    }

    /// Opens an already-prepared database file (tests / in-memory setups).
    init(preparedFileURL: URL) throws {
        self.fileURL = preparedFileURL
        self.bundledURL = nil
        let opened = try Self.openDatabase(at: preparedFileURL)
        try Self.migrateIfNeeded(opened)
        db = opened
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    /// Protocol entry point — hops onto the actor, then uses the sync lookup.
    func record(forTVDBID id: Int) async -> ShowIDMappingRecord? {
        lookupRecord(forTVDBID: id)
    }

    func tvdbID(forTVMazeID id: Int) async -> Int? {
        lookupTVDBID(forTVMazeID: id)
    }

    /// Synchronous TheTVDB → TVMaze lookup for callers already on this actor
    /// (refresh writes, recovery). Prefer `record(forTVDBID:)` from outside.
    func lookupRecord(forTVDBID id: Int) -> ShowIDMappingRecord? {
        guard let db else { return nil }
        let sql =
            "SELECT tvmaze_id, name, poster_medium_url FROM mappings WHERE tvdb_id = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, sqlite3_int64(id))
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let tvMazeID = Int(sqlite3_column_int64(statement, 0))
        let name = Self.columnText(statement, index: 1)
        let poster = Self.columnText(statement, index: 2).flatMap(URL.init(string:))
        return ShowIDMappingRecord(tvMazeID: tvMazeID, name: name, posterMediumURL: poster)
    }

    /// Synchronous TVMaze → TheTVDB lookup for callers already on this actor.
    func lookupTVDBID(forTVMazeID id: Int) -> Int? {
        guard let db else { return nil }
        let sql = "SELECT tvdb_id FROM mappings WHERE tvmaze_id = ? ORDER BY tvdb_id ASC LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, sqlite3_int64(id))
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(statement, 0))
    }

    /// Inserts or replaces the mapping keyed by TheTVDB id.
    /// Nil display fields keep any values already stored for this TheTVDB id.
    func upsert(
        tvdbID: Int,
        tvMazeID: Int,
        name: String? = nil,
        posterMediumURL: URL? = nil
    ) throws {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        try execute(
            """
            INSERT INTO mappings(tvdb_id, tvmaze_id, name, poster_medium_url) VALUES(?, ?, ?, ?)
            ON CONFLICT(tvdb_id) DO UPDATE SET
                tvmaze_id = excluded.tvmaze_id,
                name = COALESCE(excluded.name, mappings.name),
                poster_medium_url = COALESCE(excluded.poster_medium_url, mappings.poster_medium_url);
            """,
            bind: { statement in
                sqlite3_bind_int64(statement, 1, sqlite3_int64(tvdbID))
                sqlite3_bind_int64(statement, 2, sqlite3_int64(tvMazeID))
                Self.bindText(
                    statement,
                    index: 3,
                    (trimmedName?.isEmpty == false) ? trimmedName : nil
                )
                Self.bindText(statement, index: 4, posterMediumURL?.absoluteString)
            }
        )
    }

    /// Removes a single TheTVDB → TVMaze row.
    func removeMapping(forTVDBID tvdbID: Int) throws {
        try execute(
            "DELETE FROM mappings WHERE tvdb_id = ?;",
            bind: { statement in
                sqlite3_bind_int64(statement, 1, sqlite3_int64(tvdbID))
            }
        )
    }

    /// Removes every mapping that points at this TVMaze show (0–N TheTVDB ids).
    func removeMappings(forTVMazeID tvMazeID: Int) throws {
        try execute(
            "DELETE FROM mappings WHERE tvmaze_id = ?;",
            bind: { statement in
                sqlite3_bind_int64(statement, 1, sqlite3_int64(tvMazeID))
            }
        )
    }

    /// Reconciles one TVMaze show's external TheTVDB id into the mapping.
    ///
    /// A show can change or lose its TheTVDB external; clear prior rows for
    /// this TVMaze id, then write the current mapping when present.
    func applyMapping(
        tvMazeID: Int,
        tvdbID: Int?,
        name: String? = nil,
        posterMediumURL: URL? = nil
    ) throws {
        try removeMappings(forTVMazeID: tvMazeID)
        if let tvdbID, tvdbID > 0 {
            try upsert(
                tvdbID: tvdbID,
                tvMazeID: tvMazeID,
                name: name,
                posterMediumURL: posterMediumURL
            )
        }
    }

    /// Reads sync / generation meta keys into a single value type.
    func metadata() throws -> ShowIDMappingMetadata {
        ShowIDMappingMetadata(
            schemaVersion: Int(metaValue("schema_version") ?? "")
                ?? ShowIDMappingMetadata.currentSchemaVersion,
            generatedAt: Self.parseDate(metaValue("generated_at")),
            highestTVMazeID: Int(metaValue("highest_tvmaze_id") ?? "") ?? 0,
            lastSuccessfulSyncAt: Self.parseDate(metaValue("last_successful_sync_at")),
            syncHorizonAt: Self.parseDate(metaValue("sync_horizon_at")),
            updatesResumeCursor: updatesResumeCursor()
        )
    }

    /// High-water mark for the `/shows?page=` tail crawl.
    func setHighestTVMazeID(_ value: Int) throws {
        try setMeta(key: "highest_tvmaze_id", value: String(value))
    }

    /// Commits the upper watermark after a fully drained updates pass.
    func setLastSuccessfulSyncAt(_ date: Date) throws {
        try setMeta(key: "last_successful_sync_at", value: Self.formatDate(date))
    }

    /// Records when the bundled (or fully regenerated) snapshot was produced.
    func setGeneratedAt(_ date: Date) throws {
        try setMeta(key: "generated_at", value: Self.formatDate(date))
    }

    /// Pins the in-progress sync start so mid-flight updates are deferred.
    func setSyncHorizonAt(_ date: Date) throws {
        try setMeta(key: "sync_horizon_at", value: Self.formatDate(date))
    }

    /// Clears the in-progress horizon after a successful commit (or abort cleanup).
    func clearSyncHorizonAt() throws {
        try setMeta(key: "sync_horizon_at", value: "")
    }

    /// Persists where a rate-limited updates drain should resume next opportunity.
    func setUpdatesResumeCursor(_ cursor: ShowIDMappingResumeCursor) throws {
        try setMeta(key: "updates_resume_at", value: Self.formatDate(cursor.updatedAt))
        try setMeta(key: "updates_resume_show_id", value: String(cursor.showID))
    }

    /// Clears a partial updates drain cursor.
    func clearUpdatesResumeCursor() throws {
        try setMeta(key: "updates_resume_at", value: "")
        try setMeta(key: "updates_resume_show_id", value: "")
    }

    /// Clears in-progress sync markers after a horizon is successfully committed.
    func clearInProgressSyncState() throws {
        try clearUpdatesResumeCursor()
        try clearSyncHorizonAt()
    }

    private func updatesResumeCursor() -> ShowIDMappingResumeCursor? {
        guard let updatedAt = Self.parseDate(metaValue("updates_resume_at")),
            let showID = Int(metaValue("updates_resume_show_id") ?? "")
        else {
            return nil
        }
        return ShowIDMappingResumeCursor(updatedAt: updatedAt, showID: showID)
    }

    /// Closes the SQLite handle. Used by tests before replacing files on disk.
    func close() {
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    /// Replaces the writable database from the bundled baseline after corruption.
    func recreateFromBundledBaseline() throws {
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
        try Self.prepareWritableDatabase(
            at: fileURL,
            bundledURL: bundledURL,
            forceReplace: true
        )
        let opened = try Self.openDatabase(at: fileURL)
        try Self.migrateIfNeeded(opened)
        db = opened
    }

    // MARK: - File bootstrap

    /// Opens the on-device mapping database at the default Application Support
    /// location, copying the bundled baseline if needed.
    ///
    /// If the first open fails, replaces the writable file from the bundled
    /// baseline (or empty schema) and retries once. A second failure is thrown.
    nonisolated static func openDefault() throws -> ShowIDMappingDatabase {
        try open(fileURL: defaultWritableURL(), bundledURL: bundledDatabaseURL())
    }

    /// Opens a mapping database at `fileURL`, copying from `bundledURL` if needed.
    ///
    /// If the first open fails, replaces the writable file from the bundled
    /// baseline (or empty schema) and retries once. A second failure is thrown.
    nonisolated static func open(
        fileURL: URL,
        bundledURL: URL?
    ) throws -> ShowIDMappingDatabase {
        do {
            return try ShowIDMappingDatabase(
                fileURL: fileURL,
                bundledURL: bundledURL
            )
        } catch {
            try prepareWritableDatabase(
                at: fileURL,
                bundledURL: bundledURL,
                forceReplace: true
            )
            return try ShowIDMappingDatabase(
                fileURL: fileURL,
                bundledURL: bundledURL
            )
        }
    }

    /// Application Support path for the mutable on-device copy of the mapping.
    nonisolated static func defaultWritableURL(
        fileManager: FileManager = .default
    ) throws -> URL {
        let folder = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("ShowIDMapping", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(writableFileName)
    }

    /// Locates the read-only bundled baseline; tries a few resource layouts so
    /// Xcode folder references and flat copies both resolve.
    nonisolated static func bundledDatabaseURL(
        bundle: Bundle = .main
    ) -> URL? {
        bundle.url(
            forResource: bundledResourceName,
            withExtension: bundledResourceExtension,
            subdirectory: "Resources/ShowIDMapping"
        )
            ?? bundle.url(
                forResource: bundledResourceName,
                withExtension: bundledResourceExtension,
                subdirectory: "ShowIDMapping"
            )
            ?? bundle.url(
                forResource: bundledResourceName,
                withExtension: bundledResourceExtension
            )
    }

    /// Ensures a writable SQLite file exists at `fileURL`.
    ///
    /// Reuses an existing readable file, replaces a corrupt one, copies the
    /// bundled baseline when available, or creates an empty schema otherwise.
    /// `forceReplace` is the recovery path after open failures.
    nonisolated static func prepareWritableDatabase(
        at fileURL: URL,
        bundledURL: URL?,
        forceReplace: Bool = false,
        fileManager: FileManager = .default
    ) throws {
        let folder = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        if forceReplace, fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }

        if fileManager.fileExists(atPath: fileURL.path), !forceReplace {
            if isReadableDatabase(at: fileURL) {
                if bundledURL != nil {
                    let version = storedSchemaVersion(at: fileURL) ?? 0
                    if version == ShowIDMappingMetadata.currentSchemaVersion {
                        return
                    }
                    // Schema bump — replace from the bundled snapshot so Search
                    // gets TVMaze titles/posters instead of empty new columns.
                    try fileManager.removeItem(at: fileURL)
                } else {
                    return
                }
            } else {
                // Unreadable / truncated file — drop it and fall through to copy/create.
                try fileManager.removeItem(at: fileURL)
            }
        }

        guard let bundledURL else {
            try createEmptyDatabase(at: fileURL)
            return
        }

        try fileManager.copyItem(at: bundledURL, to: fileURL)
        // Ensure the Application Support copy is writable even if the bundle
        // resource was copied with restrictive permissions.
        try fileManager.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: fileURL.path
        )
    }

    /// Creates a minimal empty mapping database (schema + default meta) when no bundled
    /// baseline is available — Search simply finds no actionable hits until refresh.
    nonisolated static func createEmptyDatabase(at fileURL: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(fileURL.path, &db) == SQLITE_OK, let db else {
            throw ShowIDMappingError.sqlite("Unable to create empty show ID mapping database")
        }
        defer { sqlite3_close(db) }
        try exec(
            db,
            """
            CREATE TABLE IF NOT EXISTS meta (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS mappings (
                tvdb_id INTEGER PRIMARY KEY NOT NULL,
                tvmaze_id INTEGER NOT NULL,
                name TEXT,
                poster_medium_url TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_mappings_tvmaze_id ON mappings(tvmaze_id);
            """
        )
        try exec(
            db,
            """
            INSERT OR REPLACE INTO meta(key, value) VALUES('schema_version', '\(ShowIDMappingMetadata.currentSchemaVersion)');
            INSERT OR REPLACE INTO meta(key, value) VALUES('generated_at', '');
            INSERT OR REPLACE INTO meta(key, value) VALUES('highest_tvmaze_id', '0');
            INSERT OR REPLACE INTO meta(key, value) VALUES('last_successful_sync_at', '');
            INSERT OR REPLACE INTO meta(key, value) VALUES('source', 'TVMaze');
            INSERT OR REPLACE INTO meta(key, value) VALUES('license', 'CC BY-SA');
            """
        )
    }

    nonisolated private static func isReadableDatabase(at fileURL: URL) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open_v2(fileURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
            let db
        else {
            return false
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name='mappings';"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW
    }

    nonisolated private static func openDatabase(at fileURL: URL) throws -> OpaquePointer {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(fileURL.path, &db, flags, nil) == SQLITE_OK, let db else {
            throw ShowIDMappingError.sqlite("Unable to open show ID mapping database")
        }
        return db
    }

    // MARK: - Internals

    /// Ensures `meta` / `mappings` exist, adds display columns on older files,
    /// and records the current schema version.
    nonisolated private static func migrateIfNeeded(_ db: OpaquePointer) throws {
        try exec(
            db,
            """
            CREATE TABLE IF NOT EXISTS meta (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS mappings (
                tvdb_id INTEGER PRIMARY KEY NOT NULL,
                tvmaze_id INTEGER NOT NULL,
                name TEXT,
                poster_medium_url TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_mappings_tvmaze_id ON mappings(tvmaze_id);
            """
        )
        if !mappingsHasColumn(db, "name") {
            try exec(db, "ALTER TABLE mappings ADD COLUMN name TEXT;")
        }
        if !mappingsHasColumn(db, "poster_medium_url") {
            try exec(db, "ALTER TABLE mappings ADD COLUMN poster_medium_url TEXT;")
        }
        try writeMetaValue(
            db,
            key: "schema_version",
            value: String(ShowIDMappingMetadata.currentSchemaVersion)
        )
    }

    nonisolated private static func storedSchemaVersion(at fileURL: URL) -> Int? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(fileURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
            let db
        else {
            return nil
        }
        defer { sqlite3_close(db) }
        guard let raw = readMetaValue(db, key: "schema_version") else { return nil }
        return Int(raw)
    }

    nonisolated private static func mappingsHasColumn(_ db: OpaquePointer, _ name: String) -> Bool {
        var statement: OpaquePointer?
        guard
            sqlite3_prepare_v2(db, "PRAGMA table_info(mappings);", -1, &statement, nil)
                == SQLITE_OK
        else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let cString = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: cString) == name { return true }
        }
        return false
    }

    nonisolated private static func bindText(
        _ statement: OpaquePointer?,
        index: Int32,
        _ value: String?
    ) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(
            statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    nonisolated private static func columnText(_ statement: OpaquePointer?, index: Int32) -> String?
    {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        let value = String(cString: cString)
        return value.isEmpty ? nil : value
    }

    nonisolated private static func readMetaValue(_ db: OpaquePointer, key: String) -> String? {
        let sql = "SELECT value FROM meta WHERE key = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(
            statement, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let cString = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: cString)
    }

    nonisolated private static func writeMetaValue(
        _ db: OpaquePointer,
        key: String,
        value: String
    ) throws {
        let sql =
            "INSERT INTO meta(key, value) VALUES(?, ?) "
            + "ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ShowIDMappingError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(
            statement, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(
            statement, 2, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ShowIDMappingError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func metaValue(_ key: String) -> String? {
        guard let db else { return nil }
        return Self.readMetaValue(db, key: key)
    }

    private func setMeta(key: String, value: String) throws {
        guard let db else { throw ShowIDMappingError.sqlite("Database is closed") }
        try Self.writeMetaValue(db, key: key, value: value)
    }

    private func execute(
        _ sql: String,
        bind: ((OpaquePointer?) -> Void)? = nil
    ) throws {
        guard let db else { throw ShowIDMappingError.sqlite("Database is closed") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ShowIDMappingError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        bind?(statement)
        let step = sqlite3_step(statement)
        // Multi-statement scripts use exec instead; single statements end at DONE.
        guard step == SQLITE_DONE || step == SQLITE_ROW else {
            throw ShowIDMappingError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
    }

    nonisolated private static func exec(_ db: OpaquePointer, _ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "SQLite error"
            sqlite3_free(errorMessage)
            throw ShowIDMappingError.sqlite(message)
        }
    }

    nonisolated private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: raw)
    }

    nonisolated private static func formatDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

/// Failures opening, preparing, or mutating the show ID mapping SQLite store.
///
/// Surfaced to launch-time recovery and tests; Search treats a missing
/// mapping as “not actionable” rather than throwing these errors.
enum ShowIDMappingError: Error, LocalizedError {
    /// Low-level SQLite prepare / step / exec failure (message from `sqlite3_errmsg`).
    case sqlite(String)
    /// Bundled baseline resource could not be located in the app bundle.
    case missingBundledDatabase

    var errorDescription: String? {
        switch self {
        case .sqlite(let message):
            return message
        case .missingBundledDatabase:
            return "Bundled show ID mapping database is missing."
        }
    }
}

//
//  ShowIDMappingRefreshService.swift
//  NextSeason
//

/// Opportunistic on-device refresh of the TVDB↔TVMaze show ID mapping.
///
/// Never blocks Search or launch. Failures leave the existing writable database
/// untouched aside from whatever partial writes already committed — the bundled
/// baseline remains a recovery path via `ShowIDMappingDatabase`.
///
/// Update passes are newest-first and **resumable**. Each sync captures a fixed
/// upper watermark (`syncHorizonAt`) when it begins. Only updates at or before
/// that horizon are drained; when the backlog finishes, `lastSuccessfulSyncAt`
/// is set to the horizon (not “now”), so changes that arrived mid-drain are
/// picked up on the next sync instead of being skipped forever.
///
/// The updates lower watermark is `lastSuccessfulSyncAt ?? generatedAt`, so a
/// freshly installed bundled database only processes changes newer than the
/// bundled snapshot.
actor ShowIDMappingRefreshService {
    /// Roughly weekly refreshes are enough for search filtering freshness.
    static let refreshInterval: TimeInterval = 7 * 24 * 60 * 60

    /// Cap per opportunity so a large `/updates/shows` window cannot burst.
    static let defaultMaxShowDetailFetchesPerRefresh = 75

    /// Delay between TVMaze calls during refresh (stay under ≥20 / 10s).
    static let defaultRequestPause: Duration = .milliseconds(400)

    private let database: ShowIDMappingDatabase
    private let tvMaze: any TVMazeService
    private let now: @Sendable () -> Date
    private let maxShowDetailFetchesPerRefresh: Int
    private let requestPause: Duration
    private var isRunning = false

    init(
        database: ShowIDMappingDatabase,
        tvMaze: any TVMazeService,
        now: @escaping @Sendable () -> Date = { Date() },
        maxShowDetailFetchesPerRefresh: Int = ShowIDMappingRefreshService
            .defaultMaxShowDetailFetchesPerRefresh,
        requestPause: Duration = ShowIDMappingRefreshService.defaultRequestPause
    ) {
        self.database = database
        self.tvMaze = tvMaze
        self.now = now
        self.maxShowDetailFetchesPerRefresh = maxShowDetailFetchesPerRefresh
        self.requestPause = requestPause
    }

    /// Starts a refresh when due, or continues a capped updates pass.
    /// Safe to call from foreground activation.
    func refreshIfNeeded() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        do {
            let metadata = try await database.metadata()
            if !metadata.hasInProgressSync,
                let lastSync = metadata.lastSuccessfulSyncAt,
                now().timeIntervalSince(lastSync) < Self.refreshInterval
            {
                return
            }

            // Freeze the upper bound for this sync. Mid-drain TVMaze changes after
            // this instant are deferred until the next sync cycle.
            let horizonAt = metadata.syncHorizonAt ?? now()
            if metadata.syncHorizonAt == nil {
                try await database.setSyncHorizonAt(horizonAt)
            }

            AppDiagnosticsLogger.logger(for: .network)
                .notice("show_id_mapping_refresh_start")
            AppDiagnosticsLogger.breadcrumb("show_id_mapping_refresh")

            try await refreshTail(fromHighestID: metadata.highestTVMazeID)
            // Prefer the last completed sync; on first launch fall back to the
            // bundled snapshot's generation time so we only pull genuinely new
            // changes instead of rechecking a default week of already-mapped shows.
            let updatesWatermark = metadata.lastSuccessfulSyncAt ?? metadata.generatedAt
            let updatesFinished = try await refreshUpdatedShows(
                since: updatesWatermark,
                horizonAt: horizonAt,
                resumeCursor: metadata.updatesResumeCursor
            )
            if updatesFinished {
                // Commit the horizon, not wall-clock "now", so anything newer than
                // the horizon remains eligible for the next sync window.
                try await database.setLastSuccessfulSyncAt(horizonAt)
                try await database.clearInProgressSyncState()
                AppDiagnosticsLogger.logger(for: .network)
                    .notice("show_id_mapping_refresh_complete")
            } else {
                AppDiagnosticsLogger.logger(for: .network)
                    .notice("show_id_mapping_refresh_paused")
                AppDiagnosticsLogger.breadcrumb("show_id_mapping_refresh_paused")
            }
        } catch {
            // Non-fatal: keep serving the existing map.
            AppDiagnosticsLogger.logger(for: .network)
                .error(
                    "show_id_mapping_refresh_failed error=\(error.localizedDescription, privacy: .public)"
                )
            AppDiagnosticsLogger.breadcrumb("show_id_mapping_refresh_failed")
        }
    }

    /// Walks TVMaze show-index pages from the local high-water mark to the end.
    private func refreshTail(fromHighestID highestID: Int) async throws {
        var page = max(highestID, 0) / 250
        var highest = highestID
        var emptyPages = 0

        while true {
            let shows: [ShowIndexEntryData]
            do {
                shows = try await tvMaze.showsIndex(page: page)
            } catch TVMazeError.notFound {
                break
            }

            if shows.isEmpty {
                emptyPages += 1
                // Defensive: avoid spinning if the API returns empty pages forever.
                if emptyPages >= 3 { break }
            } else {
                emptyPages = 0
                for entry in shows {
                    if entry.id > highest { highest = entry.id }
                    try await database.applyMapping(
                        tvMazeID: entry.id,
                        tvdbID: entry.externals?.thetvdb,
                        name: entry.name,
                        posterMediumURL: entry.posterMediumURL
                    )
                }
                try await database.setHighestTVMazeID(highest)
            }

            page += 1
            try await Task.sleep(for: requestPause)
            try Task.checkCancellation()
        }
    }

    /// Refreshes mappings for shows TVMaze reports as updated since the last sync.
    ///
    /// - Returns: `true` when the horizon window is fully drained; `false` when
    ///   work remains and a resume cursor was persisted.
    private func refreshUpdatedShows(
        since lastSync: Date?,
        horizonAt: Date,
        resumeCursor: ShowIDMappingResumeCursor?
    ) async throws -> Bool {
        let updates = try await fetchUpdates(since: lastSync, horizonAt: horizonAt)
        let pending = Self.pendingUpdates(
            from: updates,
            updatedAfter: lastSync,
            horizonAt: horizonAt,
            resumeCursor: resumeCursor
        )
        guard !pending.isEmpty else { return true }

        var fetched = 0
        var lastProcessed: ShowIDMappingResumeCursor?
        for item in pending {
            guard fetched < maxShowDetailFetchesPerRefresh else { break }
            do {
                let entry = try await tvMaze.showIndexEntry(id: item.showID)
                try await database.applyMapping(
                    tvMazeID: entry.id,
                    tvdbID: entry.externals?.thetvdb,
                    name: entry.name,
                    posterMediumURL: entry.posterMediumURL
                )
            } catch TVMazeError.notFound {
                // Show removed from TVMaze — drop any local mapping.
                try await database.removeMappings(forTVMazeID: item.showID)
            }
            lastProcessed = item
            fetched += 1
            try await Task.sleep(for: requestPause)
            try Task.checkCancellation()
        }

        let remaining = pending.count - fetched
        if remaining > 0, let lastProcessed {
            // Pause: keep lastSuccessfulSyncAt unchanged and resume older work next time.
            try await database.setUpdatesResumeCursor(lastProcessed)
            return false
        }

        return true
    }

    /// Loads the TVMaze update map for this sync window.
    ///
    /// TVMaze can only filter updates as far back as one month.
    /// For older sync points, fetch the complete show-update map and
    /// locally discard entries whose last-updated timestamp is at or
    /// before our saved sync watermark.
    private func fetchUpdates(
        since lastSync: Date?,
        horizonAt: Date
    ) async throws -> [Int: Date] {
        guard let lastSync else {
            // No trustworthy baseline exists.
            return try await tvMaze.allUpdatedShows()
        }

        if TVMazeUpdatePeriod.requiresUnfilteredUpdateMap(
            since: lastSync,
            at: horizonAt
        ) {
            AppDiagnosticsLogger.breadcrumb("show_id_mapping_updates_unfiltered")
            return try await tvMaze.allUpdatedShows()
        }

        // Cover from the updates watermark through the fixed horizon, not
        // wall-clock now — keeps the window stable across resume passes.
        let period = TVMazeUpdatePeriod.covering(
            since: lastSync,
            at: horizonAt
        )

        return try await tvMaze.updatedShows(since: period)
    }

    /// Newest-first ordering by update timestamp, then show id for stability.
    ///
    /// Keeps updates strictly after `updatedAfter` (prior sync watermark) and at
    /// or before `horizonAt`. When resuming, also keeps only entries strictly
    /// older than the stored cursor.
    nonisolated static func pendingUpdates(
        from updates: [Int: Date],
        updatedAfter: Date?,
        horizonAt: Date,
        resumeCursor: ShowIDMappingResumeCursor?
    ) -> [ShowIDMappingResumeCursor] {
        let items = updates.compactMap {
            showID, updatedAt -> ShowIDMappingResumeCursor? in
            if let updatedAfter, updatedAt <= updatedAfter { return nil }
            guard updatedAt <= horizonAt else { return nil }
            return ShowIDMappingResumeCursor(updatedAt: updatedAt, showID: showID)
        }
        let filtered: [ShowIDMappingResumeCursor]
        if let resumeCursor {
            filtered = items.filter { Self.isOlderThanCursor($0, resumeCursor) }
        } else {
            filtered = items
        }
        return filtered.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.showID > rhs.showID
        }
    }

    nonisolated private static func isOlderThanCursor(
        _ item: ShowIDMappingResumeCursor,
        _ cursor: ShowIDMappingResumeCursor
    ) -> Bool {
        if item.updatedAt != cursor.updatedAt {
            return item.updatedAt < cursor.updatedAt
        }
        return item.showID < cursor.showID
    }
}

nonisolated final class ReviewClock: Sendable {
    let value: Mutex<Date>
    init(_ date: Date) { value = Mutex(date) }
    var date: Date { value.withLock { $0 } }
    func set(_ date: Date) { value.withLock { $0 = date } }
}
@MainActor final class RollingMaze: TVMazeService {
    let time: ReviewClock
    let updates: [Int: Date]
    init(time: ReviewClock, updates: [Int: Date]) {
        self.time = time
        self.updates = updates
    }
    func searchShows(matching query: String) async throws -> [Show] { [] }
    func lookupShow(theTVDBID: Int) async throws -> Show { fixtureShow(theTVDBID) }
    func show(id: Int, bypassCache: Bool) async throws -> Show { fixtureShow(id) }
    func updatedShows(since period: TVMazeUpdatePeriod) async throws -> [Int: Date] {
        let length: TimeInterval = period == .day ? 86400 : (period == .week ? 604800 : 2_592_000)
        let cutoff = time.date.addingTimeInterval(-length)
        return updates.filter { $0.value > cutoff }
    }
    func allUpdatedShows() async throws -> [Int: Date] { updates }
    func showIndexEntry(id: Int) async throws -> ShowIndexEntryData {
        ShowIndexEntryData(id: id, externals: ShowExternalsData(thetvdb: id))
    }
}
extension ReviewHarness {
    @MainActor static func verifyMappingResume() async throws {
        let start = TVMazeDate.dateOnly("2026-10-01")!
        let time = ReviewClock(start)
        let url = URL(fileURLWithPath: "/tmp/NextSeasonReviewMapping-\(UUID()).sqlite")
        try ShowIDMappingDatabase.createEmptyDatabase(at: url)
        let db = try ShowIDMappingDatabase(preparedFileURL: url)
        try await db.setLastSuccessfulSyncAt(start.addingTimeInterval(-3600))
        // Force an in-progress horizon so weekly throttle is not involved.
        try await db.setSyncHorizonAt(start)
        let api = RollingMaze(
            time: time,
            updates: [
                1: start.addingTimeInterval(-1800), 2: start.addingTimeInterval(-1200),
                3: start.addingTimeInterval(-600),
            ])
        let refresh = ShowIDMappingRefreshService(
            database: db, tvMaze: api, now: { time.date }, maxShowDetailFetchesPerRefresh: 1,
            requestPause: .zero)
        await refresh.refreshIfNeeded()
        time.set(start.addingTimeInterval(2 * 86400))
        await refresh.refreshIfNeeded()
        print(
            "MAPPING_DELAYED_RESUME records=\(await db.record(forTVDBID: 1) != nil),\(await db.record(forTVDBID: 2) != nil),\(await db.record(forTVDBID: 3) != nil) completed=\(!(try await db.metadata()).hasInProgressSync)"
        )
        await db.close()
        try FileManager.default.removeItem(at: url)
    }
}

//
//  NextSeasonSchemaV1.swift
//  NextSeason
//

/// First shipped SwiftData schema (app 1.0).
///
/// The persisted model lives on this type as `TrackedShowEntity` so V1 stays
/// a frozen snapshot when a later `NextSeasonSchemaV2.TrackedShowEntity` is
/// added. Do not edit the nested model in place; add a new schema version.
/// (Pre-release exception: `isPaused` was added in place before public release
/// because beta testers start from a fresh database.)
///
/// SwiftData identifies an entity by `Schema.Entity.name` (see
/// `Schema.entityName(for:)`). There is no entity-level `originalName` —
/// `@Attribute(originalName:)` only maps renamed properties. The nested class
/// therefore keeps the name `TrackedShowEntity` so the persistent identity
/// matches stores written by the unversioned top-level model.
enum NextSeasonSchemaV1: VersionedSchema {
    nonisolated static let versionIdentifier = Schema.Version(1, 0, 0)

    nonisolated static var models: [any PersistentModel.Type] {
        [TrackedShowEntity.self]
    }
}

//
//  TrackedShowEntity.swift
//  NextSeason
//

/// SwiftData persistence model for a watchlist row.
///
/// Mirrors `TrackedShow` but stores types SwiftData handles natively:
/// - `statusRaw` — TVMaze status string (`ShowStatus.persistenceRawValue`)
/// - `nextSeasonSnapshot` — JSON-encoded `NextSeasonStatus` (associated values
///   don’t map cleanly to SwiftData attributes)
///
/// Notification debounce fields (`lastNotifiedSignature`, `pendingChangeSignature`)
/// persist across launches so PD-008 soft-change confirmation survives process death.
///
/// Frozen V1 persistence contract (`NextSeasonSchemaV1.TrackedShowEntity`).
/// Changing stored properties requires `NextSeasonSchemaV2`, not an in-place edit.
///
/// Pre-release exception: `isPaused` was added in place before public release.
/// Beta testers reinstall with a fresh database, so no migration exists for it.
/// From the first App Store release onward, the V2 rule above applies.
///
/// The class name stays `TrackedShowEntity` so `Schema.entityName(for:)` remains
/// the same string used by unversioned TestFlight stores.
extension NextSeasonSchemaV1 {
    @Model
    final class TrackedShowEntity {
        /// TVMaze show ID; unique so a show can appear at most once on the watchlist.
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
        /// Plus-lapse pause flag. Written only by the repository's `setPaused` and
        /// reactivating `add`, never by `apply(_:)`, so a refresh that loaded the
        /// row before it was paused cannot un-pause it when it writes back.
        var isPaused: Bool = false

        init(tracked: TrackedShow) throws {
            self.tvMazeID = tracked.id
            self.name = tracked.name
            self.posterMediumURL = tracked.posterMediumURL
            self.summaryHTML = tracked.summaryHTML
            self.tvMazeURL = tracked.tvMazeURL
            self.statusRaw = tracked.status.persistenceRawValue
            self.nextSeasonSnapshot = try JSONEncoder().encode(tracked.nextSeason)
            self.sourceUpdatedAt = tracked.sourceUpdatedAt
            self.lastCheckedAt = tracked.lastCheckedAt
            self.lastNotifiedSignature = tracked.lastNotifiedSignature
            self.pendingChangeSignature = tracked.pendingChangeSignature
            self.isStale = tracked.isStale
            self.dateAdded = tracked.dateAdded
            self.isPaused = tracked.isPaused
        }

        /// Updates mutable fields after a refresh. Does not change `tvMazeID` or
        /// `isPaused`.
        ///
        /// `dateAdded` is copied from `tracked`. Refresh writes pass the stored row
        /// back, so it is unchanged there; undoing a delete passes the removed row,
        /// which restores its original save date (free-tier order and the row's
        /// catch-up mark both depend on it). Matches `InMemoryWatchlistRepository`.
        func apply(_ tracked: TrackedShow) throws {
            dateAdded = tracked.dateAdded
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
        }

        func toDomain() throws -> TrackedShow {
            let nextSeason = try JSONDecoder().decode(
                NextSeasonStatus.self, from: nextSeasonSnapshot)
            return TrackedShow(
                id: tvMazeID,
                name: name,
                posterMediumURL: posterMediumURL,
                summaryHTML: summaryHTML,
                tvMazeURL: tvMazeURL,
                status: ShowStatus(rawValue: statusRaw),
                nextSeason: nextSeason,
                sourceUpdatedAt: sourceUpdatedAt,
                lastCheckedAt: lastCheckedAt,
                lastNotifiedSignature: lastNotifiedSignature,
                pendingChangeSignature: pendingChangeSignature,
                isStale: isStale,
                dateAdded: dateAdded,
                isPaused: isPaused
            )
        }
    }
}

/// Current-schema alias. Point this at `NextSeasonSchemaV2.TrackedShowEntity`
/// when that version becomes current; leave the V1 nested type unchanged.
typealias TrackedShowEntity = NextSeasonSchemaV1.TrackedShowEntity

//
//  NextSeasonModelContainer.swift
//  NextSeason
//

/// Shared `ModelContainer` construction for production, UI tests, and
/// persistence tests.
///
/// Always opens `NextSeasonSchemaV1` with `NextSeasonMigrationPlan`.
/// Production must keep SwiftData's default store URL so existing
/// Application Support `default.store` files remain the store that is opened.
/// Recovery deletes that same URL via `PersistentStoreReset`.
enum NextSeasonModelContainer {
    /// Opens the versioned watchlist store. Production callers must omit a
    /// custom URL so SwiftData keeps using Application Support `default.store`.
    static func make(configuration: ModelConfiguration = ModelConfiguration()) throws
        -> ModelContainer
    {
        let schema = Schema(versionedSchema: NextSeasonSchemaV1.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: NextSeasonMigrationPlan.self,
            configurations: configuration
        )
    }
}

//
//  NextSeasonMigrationPlan.swift
//  NextSeason
//

/// Schema ladder for the user watchlist store.
///
/// V1 is the baseline that unversioned TestFlight stores are expected to
/// match by entity name and attribute hash. `stages` stays empty until a
/// V2 schema actually ships — do not add a placeholder migration.
nonisolated enum NextSeasonMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [NextSeasonSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

//
//  SwiftDataWatchlistRepository.swift
//  NextSeason
//

/// Production `WatchlistRepository` backed by SwiftData / `TrackedShowEntity`.
///
/// `@MainActor` because `ModelContext` is main-actor bound. Callers (view models,
/// refresh) already hop to the main actor before awaiting these methods.
@MainActor
final class SwiftDataWatchlistRepository: WatchlistRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Newest saves first (`dateAdded` descending).
    func all() async throws -> [TrackedShow] {
        AppDiagnosticsLogger.logger(for: .persistence).notice("watchlist_read_all start")
        AppDiagnosticsLogger.breadcrumb("watchlist_read_all")
        let descriptor = FetchDescriptor<TrackedShowEntity>(
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
        let result = try context.fetch(descriptor).map { try $0.toDomain() }
        AppDiagnosticsLogger.logger(for: .persistence)
            .notice("watchlist_read_all complete count=\(result.count, privacy: .public)")
        return result
    }

    func trackedShow(showID: Int) async throws -> TrackedShow? {
        guard let entity = try entity(for: showID) else { return nil }
        return try entity.toDomain()
    }

    func trackedShowIDs() async throws -> Set<Int> {
        let descriptor = FetchDescriptor<TrackedShowEntity>()
        return Set(try context.fetch(descriptor).map(\.tvMazeID))
    }

    func contains(showID: Int) async throws -> Bool {
        var descriptor = FetchDescriptor<TrackedShowEntity>(
            predicate: #Predicate { $0.tvMazeID == showID }
        )
        descriptor.fetchLimit = 1
        return try context.fetchCount(descriptor) > 0
    }

    func activeShowIDs() async throws -> Set<Int> {
        let descriptor = FetchDescriptor<TrackedShowEntity>(
            predicate: #Predicate { $0.isPaused == false }
        )
        return Set(try context.fetch(descriptor).map(\.tvMazeID))
    }

    /// Idempotent for active rows. A paused row is reactivated in place with
    /// fresh show data, keeping its original `dateAdded`.
    func add(_ show: Show) async throws {
        AppDiagnosticsLogger.logger(for: .persistence)
            .notice("watchlist_write_add show_id=\(show.id, privacy: .public)")
        AppDiagnosticsLogger.breadcrumb("watchlist_add:\(show.id)")
        if let existing = try entity(for: show.id) {
            guard existing.isPaused else { return }
            try existing.apply(TrackedShow(reactivating: try existing.toDomain(), from: show))
            existing.isPaused = false
            try context.save()
            return
        }
        let tracked = TrackedShow(from: show)
        context.insert(try TrackedShowEntity(tracked: tracked))
        try context.save()
    }

    func setPaused(_ isPaused: Bool, showIDs: Set<Int>) async throws {
        guard !showIDs.isEmpty else { return }
        AppDiagnosticsLogger.logger(for: .persistence)
            .notice(
                "watchlist_write_paused paused=\(isPaused, privacy: .public) count=\(showIDs.count, privacy: .public)"
            )
        AppDiagnosticsLogger.breadcrumb("watchlist_set_paused:\(isPaused):\(showIDs.count)")
        let ids = Array(showIDs)
        let descriptor = FetchDescriptor<TrackedShowEntity>(
            predicate: #Predicate { ids.contains($0.tvMazeID) }
        )
        for entity in try context.fetch(descriptor) {
            entity.isPaused = isPaused
        }
        try context.save()
    }

    /// No-op if the show is not on the watchlist.
    func remove(showID: Int) async throws {
        AppDiagnosticsLogger.logger(for: .persistence)
            .notice("watchlist_write_remove show_id=\(showID, privacy: .public)")
        AppDiagnosticsLogger.breadcrumb("watchlist_remove:\(showID)")
        guard let entity = try entity(for: showID) else { return }
        context.delete(entity)
        try context.save()
    }

    /// Applies refresh fields onto an existing row. No-op if the show was removed
    /// between fetch and write (e.g. user untracked during a background refresh).
    func updateAfterRefresh(_ tracked: TrackedShow) async throws {
        AppDiagnosticsLogger.logger(for: .persistence)
            .notice("watchlist_write_refresh show_id=\(tracked.id, privacy: .public)")
        AppDiagnosticsLogger.breadcrumb("watchlist_refresh_write:\(tracked.id)")
        guard let entity = try entity(for: tracked.id) else { return }
        try entity.apply(tracked)
        try context.save()
    }

    private func entity(for showID: Int) throws -> TrackedShowEntity? {
        var descriptor = FetchDescriptor<TrackedShowEntity>(
            predicate: #Predicate { $0.tvMazeID == showID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

extension ReviewHarness {
    @MainActor static func verifyPersistence() async throws {
        let dir = URL(fileURLWithPath: "/tmp/NextSeasonReviewStore-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("default.store")
        try {
            let store = try NextSeasonModelContainer.make(
                configuration: ModelConfiguration(url: url))
            let context = ModelContext(store)
            context.insert(try TrackedShowEntity(tracked: TrackedShow(from: fixtureShow(1))))
            try context.save()
        }()
        let readOnly = try NextSeasonModelContainer.make(
            configuration: ModelConfiguration(url: url, allowsSave: false))
        let context = ModelContext(readOnly)
        let repo = SwiftDataWatchlistRepository(context: context)
        do {
            try await repo.add(fixtureShow(2))
            print("SAVE_FAILURE fixture did not fail")
        } catch {
            print(
                "SAVE_FAILURE threw=true insertedStillVisible=\(try await repo.contains(showID: 2)) contextHasChanges=\(context.hasChanges)"
            )
        }
        context.rollback()
        let store = try NextSeasonModelContainer.make(
            configuration: ModelConfiguration(isStoredInMemoryOnly: true))
        let corruptContext = ModelContext(store)
        let entity = try TrackedShowEntity(tracked: TrackedShow(from: fixtureShow(1)))
        entity.nextSeasonSnapshot = Data("broken-json".utf8)
        corruptContext.insert(entity)
        try corruptContext.save()
        let corruptRepo = SwiftDataWatchlistRepository(context: corruptContext)
        do {
            _ = try await corruptRepo.all()
            print("CORRUPT_ROW fixture did not fail")
        } catch {
            print(
                "CORRUPT_ROW containerOpened=true allThrows=true identitiesReadable=\(try await corruptRepo.trackedShowIDs())"
            )
        }
    }
}

//
//  AppNavigationCoordinator.swift
//  NextSeason
//

/// Routes deep links from notifications into the correct tab and detail screen.
@Observable
@MainActor
final class AppNavigationCoordinator {
    enum Tab: Hashable {
        case search
        case watchlist

        /// Index in the root `TabView`, used when handling tab-bar reselection.
        var tabBarIndex: Int {
            switch self {
            case .search: 0
            case .watchlist: 1
            }
        }
    }

    var selectedTab: Tab = .search
    var watchlistPath = NavigationPath()
    var searchPath = NavigationPath()
    /// One-shot query injection for external automation (Instruments `ProfileFlowRunner`).
    /// `ContentView` binds this into the Search tab environment; the runner sets it
    /// directly. Unused in normal launches.
    var automationSearchQuery: String?
    /// Bumped when search reaches a settled outcome during an automated run.
    /// `ProfileFlowRunner` polls this token after setting `automationSearchQuery`.
    private(set) var automationSearchSettledToken = 0
    /// Bumped when show detail finishes loading during an automated run.
    /// `ProfileFlowRunner` polls this after pushing onto `searchPath`.
    private(set) var automationDetailLoadedToken = 0

    func notifyAutomationSearchSettled() {
        automationSearchSettledToken &+= 1
    }

    func notifyAutomationDetailLoaded() {
        automationDetailLoadedToken &+= 1
    }

    private(set) var pendingShowID: Int?
    private(set) var watchlistReloadToken = 0

    /// A tracked show whose detail should be pushed onto the Watchlist tab once
    /// that tab's `NavigationStack` is on screen. The push is deferred (rather than
    /// appended immediately in `resolvePendingNavigation`) because pushing in the
    /// same update as the tab switch makes SwiftUI drop it and leave the user on
    /// the list. `WatchlistView` calls `applyPendingWatchlistDetail()` once mounted.
    private(set) var pendingWatchlistDetail: TrackedShow?

    /// Whether the pending deep-link push should animate. Determined by whether the
    /// app was already foreground-active when the notification was tapped: an in-app
    /// tap animates like normal navigation, while a launch/foreground tap does not
    /// (so the detail page is already in place rather than visibly sliding in).
    private var pendingWatchlistDetailAnimated = false

    /// Whether the queued navigation (`pendingShowID`) originated from an in-app tap.
    /// Applied when resolving to Search immediately and copied into
    /// `pendingWatchlistDetailAnimated` when the Watchlist push is deferred.
    private var pendingNavigationAnimated = false

    /// Guards the one-time cold-launch tab decision so foreground returns keep the
    /// user on whatever tab they were last using.
    private var didResolveInitialTab = false

    /// - Parameter showID: TVMaze show ID to open on the detail screen.
    /// - Parameter animated: `true` when the tap happened while the app was already
    ///   foreground-active (in-app navigation), `false` for a launch/foreground tap.
    func queueShowNavigation(showID: Int, animated: Bool = false) {
        pendingShowID = showID
        pendingNavigationAnimated = animated
    }

    /// Pushes a deferred notification deep link onto the Watchlist stack. Called by
    /// `WatchlistView` from `onAppear`/`onChange` so the push lands after that tab's
    /// `NavigationStack` is mounted. Safe to call repeatedly; it no-ops once the
    /// pending show has been consumed. The animation is decided by the tap context
    /// captured in `resolvePendingNavigation`, not by which callback triggers it.
    func applyPendingWatchlistDetail() {
        guard let tracked = pendingWatchlistDetail else { return }
        pendingWatchlistDetail = nil
        guard pendingWatchlistDetailAnimated else {
            // Launch / foreground: push without animation so the detail page is
            // already in place, rather than visibly sliding in.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                watchlistPath = NavigationPath()
                watchlistPath.append(tracked)
            }
            return
        }
        // In-app deep link while the Watchlist is already on screen: animate the push.
        watchlistPath = NavigationPath()
        watchlistPath.append(tracked)
    }

    /// Cold-launch landing tab: Watchlist when it already has at least one show,
    /// otherwise Search. Runs once per launch; it does not override a notification
    /// deep link and is never re-run on a foreground return.
    func resolveInitialTab(repository: any WatchlistRepository) async {
        guard !didResolveInitialTab else { return }
        didResolveInitialTab = true

        // Profile flows drive navigation themselves; leave the default tab alone.
        guard !ProfileFlowConfiguration.isEnabled else { return }
        // A notification deep link picks the tab itself (see resolvePendingNavigation).
        guard pendingShowID == nil else { return }

        do {
            let trackedIDs = try await repository.trackedShowIDs()
            selectedTab = trackedIDs.isEmpty ? .search : .watchlist
        } catch {
            selectedTab = .search
        }
    }

    /// Pops the search navigation stack to its root without changing tabs.
    /// The search query lives in `SearchViewModel`, so it is preserved.
    func popSearchToRoot() {
        searchPath = NavigationPath()
    }

    /// Switches to the Search tab at its root, popping any detail screen the
    /// search stack was left on (e.g. a show viewed while adding to the
    /// watchlist) so the user lands on the search screen itself.
    func showSearchRoot() {
        popSearchToRoot()
        selectedTab = .search
    }

    /// Bumps a token `WatchlistView` observes so it reloads from persistence.
    func notifyWatchlistDataChanged(reloadWatchlist: Bool = true) {
        if reloadWatchlist {
            watchlistReloadToken &+= 1
        }
    }

    /// Turns a queued notification deep link (`pendingShowID`) into tab + detail
    /// navigation. Called from `ContentView` after attach and whenever a new
    /// `pendingShowID` arrives while the app is already running.
    ///
    /// Prefer Watchlist when the show is still tracked (deferred push so the
    /// tab's `NavigationStack` is mounted). A paused show opens the Watchlist
    /// root without detail. Otherwise (not saved) fall back to Search and
    /// push immediately, honoring `pendingNavigationAnimated` for launch vs
    /// in-app taps.
    ///
    /// - Parameters:
    ///   - repository: Saved-show lookup that decides Watchlist vs. Search.
    ///   - tvMaze: Loads the show for the Search fallback when it isn't saved.
    ///   - analytics: Records the notification open and lookup failures.
    ///   - prepare: Awaited before the saved-show lookup. Production passes
    ///     `WatchlistAccessReconciler.reconcileWhenAccessKnown`, so a cold
    ///     launch from an old notification decides using reconciled pause state
    ///     (a show that just lost Plus is paused before it could open detail).
    func resolvePendingNavigation(
        repository: any WatchlistRepository,
        tvMaze: any TVMazeService,
        analytics: any AnalyticsTracking,
        prepare: @MainActor () async -> Void = {}
    ) async {
        guard let showID = pendingShowID else { return }
        // Consume the queue up front so a concurrent resolve cannot process twice.
        pendingShowID = nil
        await prepare()

        do {
            if let tracked = try await repository.trackedShow(showID: showID) {
                // A paused show (Plus lapsed) must not open detail — not even via
                // the Search fallback below. Land on the Watchlist root, where
                // the show appears in the Paused section.
                if tracked.isPaused {
                    selectedTab = .watchlist
                    watchlistPath = NavigationPath()
                    analytics.track(.appOpenedFromNotification(showID: showID))
                    return
                }
                // Defer the path append until WatchlistView appears — pushing in
                // the same update as the tab switch can drop the navigation.
                selectedTab = .watchlist
                pendingWatchlistDetail = tracked
                pendingWatchlistDetailAnimated = pendingNavigationAnimated
                analytics.track(.appOpenedFromNotification(showID: showID))
                return
            }
        } catch is CancellationError {
            return
        } catch {
            // Lookup failed; try the Search/TVMaze path below rather than giving up.
            analytics.trackNonFatalError(error, context: "notification_navigation_watchlist_lookup")
        }

        // Not on the watchlist (or watchlist lookup failed): open via Search.
        do {
            let show = try await tvMaze.show(id: showID)
            selectedTab = .search
            if pendingNavigationAnimated {
                searchPath.append(show)
            } else {
                // Launch / foreground tap: land on detail without a slide-in.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    searchPath = NavigationPath()
                    searchPath.append(show)
                }
            }
            analytics.track(.appOpenedFromNotification(showID: showID))
        } catch is CancellationError {
            return
        } catch {
            analytics.trackNonFatalError(error, context: "notification_navigation_show_lookup")
        }
    }
}

enum ProfileFlowConfiguration { static let isEnabled = false }
@MainActor final class HoldingNavigationMaze: TVMazeService {
    var held: CheckedContinuation<Show, Never>?
    var started: CheckedContinuation<Void, Never>?
    func searchShows(matching query: String) async throws -> [Show] { [] }
    func lookupShow(theTVDBID: Int) async throws -> Show { fixtureShow(theTVDBID) }
    func show(id: Int, bypassCache: Bool) async throws -> Show {
        await withCheckedContinuation {
            held = $0
            started?.resume()
            started = nil
        }
    }
    func updatedShows(since period: TVMazeUpdatePeriod) async throws -> [Int: Date] { [:] }
    func waitUntilHeld() async {
        if held != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() {
        held?.resume(returning: fixtureShow(1))
        held = nil
    }
}
extension ReviewHarness {
    @MainActor static func verifyNavigation() async throws {
        let repo = InMemoryWatchlistRepository()
        try await repo.add(fixtureShow(2))
        let coordinator = AppNavigationCoordinator()
        let service = HoldingNavigationMaze()
        let analytics = ReviewAnalytics()
        coordinator.queueShowNavigation(showID: 1)
        let first = Task {
            await coordinator.resolvePendingNavigation(
                repository: repo, tvMaze: service, analytics: analytics)
        }
        await service.waitUntilHeld()
        coordinator.queueShowNavigation(showID: 2)
        await coordinator.resolvePendingNavigation(
            repository: repo, tvMaze: service, analytics: analytics)
        service.release()
        await first.value
        print(
            "NOTIFICATION_NAVIGATION expectedLatestTab=watchlist actual=\(coordinator.selectedTab) pendingLatestShow=\(coordinator.pendingWatchlistDetail?.id ?? -1)"
        )
    }
}

//
//  NetworkData.swift
//  NextSeason
//

/// A TVMaze `network` or `webChannel`. Only the name is needed by the app.
nonisolated struct NetworkData: Codable, Sendable {
    let id: Int?
    let name: String?
}

//
//  SeasonData.swift
//  NextSeason
//

/// A season entry from `/shows/:id/seasons` or the `seasons` embed.
/// Dates and `episodeOrder` are null for announced-but-unscheduled seasons.
nonisolated struct SeasonData: Codable, Sendable {
    let id: Int
    let number: Int
    let premiereDate: String?
    let endDate: String?
    let episodeOrder: Int?
}

//
//  NextEpisodeData.swift
//  NextSeason
//

/// The `nextepisode` embed: the show's upcoming scheduled episode, if any.
/// `season` indicates which season that episode belongs to.
nonisolated struct NextEpisodeData: Codable, Sendable {
    let id: Int?
    let season: Int?
    let number: Int?
    let name: String?
    let airdate: String?
    let airstamp: String?
}

//
//  EmbeddedData.swift
//  NextSeason
//

/// The `_embedded` container returned when requesting embeds on a show.
nonisolated struct EmbeddedData: Codable, Sendable {
    let seasons: [SeasonData]?
    let nextepisode: NextEpisodeData?
}

//
//  ShowData.swift
//  NextSeason
//

/// Mirrors a TVMaze show object (`/shows/:id` and the `show` field of a search
/// result). Only the fields NextSeason uses are decoded; unknown keys are ignored.
nonisolated struct ShowData: Codable, Sendable {
    let id: Int
    let name: String
    let url: String?
    let status: String?
    let premiered: String?
    let ended: String?
    let summary: String?
    let image: ImageData?
    let network: NetworkData?
    let webChannel: NetworkData?
    let genres: [String]?
    let averageRuntime: Int?
    let updated: Int?
    let embedded: EmbeddedData?

    enum CodingKeys: String, CodingKey {
        case id, name, url, status, premiered, ended, summary, image
        case network, webChannel, genres, averageRuntime, updated
        case embedded = "_embedded"
    }
}

//
//  ShowData+Domain.swift
//  NextSeason
//
//  Maps network DTOs into clean domain models. Kept separate so the API shape
//  and the app's model can evolve independently.
//

// From the agent supervisor: I was not familiar with using the term domain in
// this way, so I asked Cursor what it meant by it. It said “the app’s own idea
// of the data”, which is distinct from what the API sent and said it's
// sometimes referred to as an app model or business model.

extension ShowData {
    /// Converts a TVMaze show payload into the app's `Show` model.
    ///
    /// Date-only fields go through `TVMazeDate.dateOnly` (UTC calendar days).
    /// Streaming-only titles often have `webChannel` instead of `network`; we
    /// surface whichever name is present. Missing `updated` becomes
    /// `.distantPast` so refresh comparisons treat the show as never updated
    /// rather than colliding with a real timestamp.
    nonisolated func toDomain() -> Show {
        Show(
            id: id,
            name: name,
            tvMazeURL: url.flatMap(URL.init(string:)),
            summaryHTML: summary,
            posterMediumURL: image?.medium.flatMap(URL.init(string:)),
            posterOriginalURL: image?.original.flatMap(URL.init(string:)),
            status: ShowStatus(rawValue: status),
            premiered: TVMazeDate.dateOnly(premiered),
            ended: TVMazeDate.dateOnly(ended),
            // Prefer broadcast network; fall back to streaming webChannel.
            network: network?.name ?? webChannel?.name,
            genres: genres ?? [],
            averageRuntime: averageRuntime,
            seasons: (embedded?.seasons ?? []).map { $0.toDomain() },
            nextEpisode: embedded?.nextepisode.map {
                NextEpisode(season: $0.season, airdate: TVMazeDate.dateOnly($0.airdate))
            },
            // Unix seconds from TVMaze; absent → sentinel so "never updated" sorts earliest.
            updatedAt: updated.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? .distantPast
        )
    }
}

extension SeasonData {
    /// Maps a season DTO; premiere/end stay nil when TVMaze has announced but not scheduled.
    nonisolated func toDomain() -> Season {
        Season(
            id: id,
            number: number,
            premiereDate: TVMazeDate.dateOnly(premiereDate),
            endDate: TVMazeDate.dateOnly(endDate),
            episodeOrder: episodeOrder
        )
    }
}

extension ReviewHarness {
    @MainActor static func verifyEpisodeHint() throws {
        let json =
            #"{"id":1,"name":"Incomplete","status":"Running","_embedded":{"seasons":[{"id":1,"number":1,"premiereDate":"2024-01-01","endDate":"2024-03-01"},{"id":2,"number":2,"premiereDate":null}],"nextepisode":{"id":8,"season":2,"number":8,"airdate":"2027-02-01"}}}"#
        let data = try JSONDecoder().decode(ShowData.self, from: Data(json.utf8))
        let show = data.toDomain()
        print(
            "MIDSEASON_EPISODE number=\(data.embedded?.nextepisode?.number ?? -1) result=\(NextSeasonCalculator.status(for: show, at: TVMazeDate.dateOnly("2027-01-01")!))"
        )
    }
}

extension ReviewHarness {
    @MainActor static func verifyMatrixLateFailure() {
        var original = TrackedShow(from: fixtureShow(1))
        original.nextSeason = .returningNoSeasonYet
        original.lastNotifiedSignature = StatusChangeDetector.signature(for: original.nextSeason)
        let b = NextSeasonStatus.scheduled(season: 2, premiere: TVMazeDate.dateOnly("2027-01-01")!)
        let attemptB = StatusChangeDetector.evaluate(tracked: original, newStatus: b)
        let newerC = StatusChangeDetector.evaluate(tracked: attemptB.tracked, newStatus: .ended)
        var restored = newerC.tracked
        // Model the proposed guard when it checks lastNotifiedSignature alone.
        if restored.lastNotifiedSignature == attemptB.tracked.lastNotifiedSignature {
            restored.lastNotifiedSignature = original.lastNotifiedSignature
            restored.pendingChangeSignature = StatusChangeDetector.signature(for: b)
        }
        let confirmC = StatusChangeDetector.evaluate(tracked: restored, newStatus: .ended)
        print(
            "MATRIX_LATE_FAILURE newerPending=\(newerC.tracked.pendingChangeSignature ?? "nil") overwrittenPending=\(restored.pendingChangeSignature ?? "nil") nextCAlert=\(confirmC.notification != nil) nextPending=\(confirmC.tracked.pendingChangeSignature ?? "nil")"
        )
    }
}
