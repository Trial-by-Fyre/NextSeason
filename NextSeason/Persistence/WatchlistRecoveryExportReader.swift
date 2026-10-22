//
//  WatchlistRecoveryExportReader.swift
//  NextSeason
//

import Foundation
import SQLite3
import SwiftData
import os

/// Outcome of a best-effort recovery read. `shows` may be incomplete even
/// when `storeWasReadable` is true.
struct WatchlistRecoveryExportRead: Equatable, Sendable {
    /// Recovered rows. May be a subset of what the user originally saved.
    var shows: [TrackedShow]
    /// True when SwiftData opened or SQLite found a watchlist table.
    var storeWasReadable: Bool
}

/// Best-effort watchlist read for persistence recovery.
///
/// Recovery may have been triggered because the store will not open, so this
/// never writes the original files. It copies the store aside, tries SwiftData
/// for full rows, then fills remaining shows from a read-only SQLite scan.
/// Either path can fail independently; an empty result means nothing usable
/// could be recovered.
enum WatchlistRecoveryExportReader {
    /// Loads whatever `TrackedShow` rows can still be decoded from `storeURL`.
    ///
    /// Per-row conversion failures are skipped rather than failing the whole
    /// export. A missing or unreadable store reports `storeWasReadable: false`.
    static func loadShows(
        storeURL: URL = PersistentStoreReset.productionStoreURL,
        fileManager: FileManager = .default
    ) async -> WatchlistRecoveryExportRead {
        let copyURL: URL
        do {
            copyURL = try copyStoreForReading(storeURL: storeURL, fileManager: fileManager)
        } catch {
            AppDiagnosticsLogger.logger(for: .persistence).error(
                "recovery_export_copy_failed error=\(String(describing: error), privacy: .public)"
            )
            return WatchlistRecoveryExportRead(shows: [], storeWasReadable: false)
        }
        let copyDirectory = copyURL.deletingLastPathComponent()
        defer { try? fileManager.removeItem(at: copyDirectory) }

        // SwiftData can still fail on the copy (same corruption as launch).
        // SQLite then supplies name/ID for rows `toDomain()` could not rebuild.
        var openedSwiftData = false
        let swiftDataShows: [TrackedShow]
        do {
            swiftDataShows = try loadViaSwiftData(storeURL: copyURL)
            openedSwiftData = true
        } catch {
            AppDiagnosticsLogger.logger(for: .persistence).error(
                "recovery_export_swiftdata_failed error=\(String(describing: error), privacy: .public)"
            )
            swiftDataShows = []
        }

        let sqliteResult = loadViaSQLite(storeURL: copyURL)
        let shows = merge(preferred: swiftDataShows, fallback: sqliteResult.shows)
        return WatchlistRecoveryExportRead(
            shows: shows,
            storeWasReadable: openedSwiftData || sqliteResult.foundWatchlistTable
        )
    }

    /// Full-fidelity fetch. Throws when the container cannot be opened or the
    /// fetch itself fails; individual `toDomain()` failures are skipped.
    static func loadViaSwiftData(storeURL: URL) throws -> [TrackedShow] {
        let container = try NextSeasonModelContainer.make(
            configuration: ModelConfiguration(url: storeURL)
        )
        let context = ModelContext(container)
        let entities = try context.fetch(FetchDescriptor<TrackedShowEntity>())
        return entities.compactMap { entity in
            do {
                return try entity.toDomain()
            } catch {
                AppDiagnosticsLogger.logger(for: .persistence).error(
                    "recovery_export_row_skipped id=\(entity.tvMazeID, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
                return nil
            }
        }
    }

    /// Read-only SQLite scan used when SwiftData cannot reconstruct a row.
    /// Discovers the watchlist table and columns rather than hard-coding
    /// SwiftData's internal names, which can vary across store formats.
    static func loadViaSQLite(storeURL: URL) -> (shows: [TrackedShow], foundWatchlistTable: Bool) {
        var db: OpaquePointer?
        // Read-only so a damaged store is never mutated; FULLMUTEX because
        // this can run while other recovery work is still on the main actor.
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(storeURL.path, &db, flags, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return ([], false)
        }
        defer { sqlite3_close(db) }
        // This scan runs right after SwiftData closes its container on the same
        // file, which can still hold a lock briefly. Without a timeout SQLite
        // returns SQLITE_BUSY at once and the table looks missing; wait instead.
        sqlite3_busy_timeout(db, 2000)

        guard let table = watchlistTableName(db: db) else { return ([], false) }
        let columns = tableColumns(db: db, table: table)
        // A watchlist table without an ID column is still "readable" — there
        // is just nothing we can export.
        guard let idColumn = column(named: "tvmazeid", in: columns) else { return ([], true) }

        let nameColumn = column(named: "name", in: columns)
        let statusColumn = column(named: "statusraw", in: columns)
        let snapshotColumn = column(named: "nextseasonsnapshot", in: columns)
        let dateAddedColumn = column(named: "dateadded", in: columns)
        let urlColumn = column(named: "tvmazeurl", in: columns)

        let quotedColumns = [
            quote(idColumn),
            nameColumn.map(quote),
            statusColumn.map(quote),
            snapshotColumn.map(quote),
            dateAddedColumn.map(quote),
            urlColumn.map(quote),
        ]
        .compactMap { $0 }
        .joined(separator: ", ")

        let sql = "SELECT \(quotedColumns) FROM \(quote(table));"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return ([], true)
        }
        defer { sqlite3_finalize(statement) }

        // SELECT lists only columns that exist, in this fixed order, so the
        // reader index advances only for columns that were actually projected.
        var shows: [TrackedShow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var index: Int32 = 0
            let tvMazeID = Int(sqlite3_column_int64(statement, index))
            index += 1
            guard tvMazeID > 0 else { continue }

            let name: String
            if nameColumn != nil {
                name = columnText(statement, index: index) ?? ""
                index += 1
            } else {
                name = ""
            }

            let status: ShowStatus
            if statusColumn != nil {
                status = ShowStatus(rawValue: columnText(statement, index: index))
                index += 1
            } else {
                status = .unknown("Unknown")
            }

            let nextSeason: NextSeasonStatus
            if snapshotColumn != nil {
                nextSeason = decodeNextSeason(statement, index: index)
                index += 1
            } else {
                nextSeason = .unknown
            }

            let dateAdded: Date
            if dateAddedColumn != nil {
                dateAdded = columnDate(statement, index: index)
                index += 1
            } else {
                dateAdded = Date(timeIntervalSince1970: 0)
            }

            let tvMazeURL: URL?
            if urlColumn != nil {
                tvMazeURL = columnText(statement, index: index).flatMap(URL.init(string:))
            } else {
                tvMazeURL = nil
            }

            // Refresh-only fields are unused by CSV export; identity columns matter.
            shows.append(
                TrackedShow(
                    id: tvMazeID,
                    name: name,
                    posterMediumURL: nil,
                    tvMazeURL: tvMazeURL,
                    status: status,
                    nextSeason: nextSeason,
                    sourceUpdatedAt: dateAdded,
                    lastCheckedAt: dateAdded,
                    dateAdded: dateAdded
                )
            )
        }
        return (shows, true)
    }

    // MARK: - Merge

    /// Prefers SwiftData-decoded rows; keeps SQLite-only identities so a
    /// corrupt `nextSeasonSnapshot` still exports name and TVMaze ID.
    static func merge(preferred: [TrackedShow], fallback: [TrackedShow]) -> [TrackedShow] {
        var byID: [Int: TrackedShow] = [:]
        for show in fallback {
            byID[show.id] = show
        }
        for show in preferred {
            byID[show.id] = show
        }
        return Array(byID.values)
    }

    // MARK: - Store copy

    /// Copies `storeURL` and SwiftData sidecars into a unique temp directory
    /// so recovery never mutates the on-disk store the user may still reset.
    private static func copyStoreForReading(
        storeURL: URL,
        fileManager: FileManager
    ) throws -> URL {
        let directory = storeURL.deletingLastPathComponent()
        let prefix = storeURL.lastPathComponent
        guard fileManager.fileExists(atPath: storeURL.path) else {
            throw RecoveryExportReadError.storeMissing
        }

        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(
                "recovery-export-\(UUID().uuidString)",
                isDirectory: true
            )
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for fileURL in contents where fileURL.lastPathComponent.hasPrefix(prefix) {
            try fileManager.copyItem(
                at: fileURL,
                to: tempDirectory.appendingPathComponent(fileURL.lastPathComponent)
            )
        }
        return tempDirectory.appendingPathComponent(prefix)
    }

    // MARK: - SQLite discovery

    /// Prefers `TrackedShowEntity` / `ZTRACKEDSHOWENTITY` and ignores SwiftData
    /// metadata tables whose names also contain "trackedshow".
    private static func watchlistTableName(db: OpaquePointer) -> String? {
        let sql = "SELECT name FROM sqlite_master WHERE type='table';"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = columnText(statement, index: 0) {
                names.append(name)
            }
        }

        let candidates = names.filter { name in
            let normalized = normalize(name)
            return normalized.contains("trackedshow") && !normalized.contains("metadata")
        }
        if let exact = candidates.first(where: { normalize($0) == "trackedshowentity" }) {
            return exact
        }
        return candidates.first
    }

    /// Column names from `PRAGMA table_info`, used to match `tvMazeID` / `ZTVMAZEID`.
    private static func tableColumns(db: OpaquePointer, table: String) -> [String] {
        let sql = "PRAGMA table_info(\(quote(table)));"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var columns: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = columnText(statement, index: 1) {
                columns.append(name)
            }
        }
        return columns
    }

    /// Original column name whose normalized form equals `normalizedName`.
    private static func column(named normalizedName: String, in columns: [String]) -> String? {
        columns.first { normalize($0) == normalizedName }
    }

    /// Lowercases, drops underscores, and strips a Core Data `Z` prefix so
    /// `ZTVMAZEID` and `tvMazeID` both match `tvmazeid`.
    private static func normalize(_ name: String) -> String {
        var normalized = name.lowercased().replacingOccurrences(of: "_", with: "")
        if normalized.first == "z" {
            normalized.removeFirst()
        }
        return normalized
    }

    /// Quotes a SQLite identifier so discovered Core Data names stay safe in SQL.
    private static func quote(_ identifier: String) -> String {
        "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// UTF-8 text, or `nil` for NULL / missing values.
    private static func columnText(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard let statement, sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    /// Decodes the persisted `NextSeasonStatus` blob; corrupt JSON becomes `.unknown`.
    private static func decodeNextSeason(
        _ statement: OpaquePointer?,
        index: Int32
    ) -> NextSeasonStatus {
        guard let statement, sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return .unknown
        }
        let byteCount = Int(sqlite3_column_bytes(statement, index))
        guard byteCount > 0, let bytes = sqlite3_column_blob(statement, index) else {
            return .unknown
        }
        let data = Data(bytes: bytes, count: byteCount)
        return (try? JSONDecoder().decode(NextSeasonStatus.self, from: data)) ?? .unknown
    }

    /// SwiftData / Core Data stores dates as CF absolute time. Values that
    /// look like Unix timestamps (export-only fallback files) are accepted too.
    private static func columnDate(_ statement: OpaquePointer?, index: Int32) -> Date {
        guard let statement, sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return Date(timeIntervalSince1970: 0)
        }
        let value = sqlite3_column_double(statement, index)
        if value > 1_000_000_000 {
            return Date(timeIntervalSince1970: value)
        }
        return Date(timeIntervalSinceReferenceDate: value)
    }
}

/// Failures while preparing a side copy of the watchlist store for recovery export.
enum RecoveryExportReadError: Error {
    /// The production `default.store` file is not on disk.
    case storeMissing
}
