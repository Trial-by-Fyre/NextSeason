//
//  WatchlistRecoveryExportReaderTests.swift
//  NextSeasonTests
//

import Foundation
import SQLite3
import SwiftData
import Testing

@testable import NextSeason

/// Best-effort recovery export reads: SwiftData, per-row skip, and SQLite fallback.
@MainActor
struct WatchlistRecoveryExportReaderTests {
    @Test("A readable store returns recovered shows")
    func readableStoreReturnsShows() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        let show = sampleShow(id: 44933, name: "Severance")

        try seedStore(at: storeURL, shows: [show])

        let read = await WatchlistRecoveryExportReader.loadShows(storeURL: storeURL)
        #expect(read.storeWasReadable)
        #expect(read.shows.map(\.id) == [44933])
        #expect(read.shows.map(\.name) == ["Severance"])

        // Also assert the SQLite path can discover Core Data `Z`-prefixed columns.
        let sqlite = WatchlistRecoveryExportReader.loadViaSQLite(storeURL: storeURL)
        #expect(sqlite.foundWatchlistTable)
        #expect(sqlite.shows.map(\.id) == [44933])
        #expect(sqlite.shows.map(\.name) == ["Severance"])
    }

    @Test("A missing store is unreadable and exports nothing")
    func missingStoreIsUnreadable() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("recovery-missing-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("default.store")

        let read = await WatchlistRecoveryExportReader.loadShows(storeURL: missing)
        #expect(read.storeWasReadable == false)
        #expect(read.shows.isEmpty)
    }

    @Test("A damaged file that is not a store exports nothing")
    func garbageFileIsUnreadable() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        try Data("not a swift data store".utf8).write(to: storeURL)

        let read = await WatchlistRecoveryExportReader.loadShows(storeURL: storeURL)
        #expect(read.storeWasReadable == false)
        #expect(read.shows.isEmpty)
    }

    @Test("A corrupt next-season snapshot still exports the show via SQLite")
    func corruptSnapshotFallsBackToSQLiteIdentity() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        let good = sampleShow(id: 1, name: "Good Show")
        let damaged = sampleShow(id: 2, name: "Damaged Show")

        try seedStore(at: storeURL, shows: [good, damaged])
        try corruptNextSeasonSnapshot(storeURL: storeURL, tvMazeID: 2)

        let read = await WatchlistRecoveryExportReader.loadShows(storeURL: storeURL)
        #expect(read.storeWasReadable)
        let byID = Dictionary(uniqueKeysWithValues: read.shows.map { ($0.id, $0) })
        #expect(byID[1]?.name == "Good Show")
        #expect(byID[2]?.name == "Damaged Show")
        #expect(byID[1]?.nextSeason == good.nextSeason)
        #expect(byID[2]?.nextSeason == .unknown)
    }

    @Test("SQLite fallback reads name and ID when SwiftData cannot open the file")
    func sqliteFallbackReadsIdentityColumns() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        try writeIdentityOnlySQLiteStore(
            at: storeURL,
            id: 44933,
            name: "Severance"
        )

        let read = await WatchlistRecoveryExportReader.loadShows(storeURL: storeURL)
        #expect(read.storeWasReadable)
        #expect(read.shows.count == 1)
        #expect(read.shows[0].id == 44933)
        #expect(read.shows[0].name == "Severance")
    }

    @Test("Merge prefers SwiftData rows and keeps SQLite-only identities")
    func mergePrefersSwiftDataAndKeepsFallbackIdentities() {
        let preferred = sampleShow(id: 1, name: "Preferred")
        let fallbackSame = sampleShow(id: 1, name: "Fallback Same")
        let fallbackOnly = sampleShow(id: 2, name: "Fallback Only")

        let merged = WatchlistRecoveryExportReader.merge(
            preferred: [preferred],
            fallback: [fallbackSame, fallbackOnly]
        )
        let byID = Dictionary(uniqueKeysWithValues: merged.map { ($0.id, $0) })
        #expect(byID[1]?.name == "Preferred")
        #expect(byID[2]?.name == "Fallback Only")
    }

    /// Releases SwiftData's autoreleased storage objects before SQLite opens
    /// the saved fixture directly (including its WAL sidecars).
    private func seedStore(at storeURL: URL, shows: [TrackedShow]) throws {
        try autoreleasepool {
            let container = try NextSeasonModelContainer.make(
                configuration: ModelConfiguration(url: storeURL)
            )
            let context = ModelContext(container)
            for show in shows {
                context.insert(try TrackedShowEntity(tracked: show))
            }
            try context.save()
        }
    }

    /// Overwrites one row's `nextSeasonSnapshot` so SwiftData `toDomain()` fails
    /// and SQLite must still recover name and TVMaze ID.
    private func corruptNextSeasonSnapshot(storeURL: URL, tvMazeID: Int) throws {
        // Validate the saved fixture before opening the connection that will
        // deliberately corrupt it.
        let sqliteResult = WatchlistRecoveryExportReader.loadViaSQLite(storeURL: storeURL)
        try #require(sqliteResult.foundWatchlistTable)
        try #require(sqliteResult.shows.contains { $0.id == tvMazeID })

        var db: OpaquePointer?
        guard sqlite3_open(storeURL.path, &db) == SQLITE_OK, let db else {
            throw RecoveryExportReadError.storeMissing
        }
        defer { sqlite3_close(db) }

        let (table, idColumn, snapshotColumn) = try #require(watchlistSnapshotColumns(db: db))
        let garbage = Data("not-json".utf8)
        let sql =
            "UPDATE \(quote(table)) SET \(quote(snapshotColumn)) = ? WHERE \(quote(idColumn)) = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw RecoveryExportReadError.storeMissing
        }
        defer { sqlite3_finalize(statement) }
        try garbage.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(garbage.count), nil)
            sqlite3_bind_int64(statement, 2, sqlite3_int64(tvMazeID))
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw RecoveryExportReadError.storeMissing
            }
            try #require(sqlite3_changes(db) == 1)
        }
    }

    /// Discovers the watchlist table plus ID/snapshot columns, including `Z` prefixes.
    private func watchlistSnapshotColumns(db: OpaquePointer) -> (String, String, String)? {
        var tableStatement: OpaquePointer?
        guard
            sqlite3_prepare_v2(
                db, "SELECT name FROM sqlite_master WHERE type='table';", -1, &tableStatement, nil)
                == SQLITE_OK
        else { return nil }
        defer { sqlite3_finalize(tableStatement) }

        var tables: [String] = []
        while sqlite3_step(tableStatement) == SQLITE_ROW {
            if let name = sqlite3_column_text(tableStatement, 0) {
                tables.append(String(cString: name))
            }
        }

        for table in tables {
            let normalizedTable = normalizeColumnName(table)
            guard normalizedTable.contains("trackedshow") else { continue }

            var info: OpaquePointer?
            let pragma = "PRAGMA table_info(\(quote(table)));"
            guard sqlite3_prepare_v2(db, pragma, -1, &info, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(info) }

            var idColumn: String?
            var snapshotColumn: String?
            while sqlite3_step(info) == SQLITE_ROW {
                guard let name = sqlite3_column_text(info, 1) else { continue }
                let column = String(cString: name)
                let normalized = normalizeColumnName(column)
                if normalized == "tvmazeid" { idColumn = column }
                if normalized == "nextseasonsnapshot" { snapshotColumn = column }
            }
            if let idColumn, let snapshotColumn {
                return (table, idColumn, snapshotColumn)
            }
        }
        return nil
    }

    /// Same identifier quoting as `WatchlistRecoveryExportReader`.
    private func quote(_ identifier: String) -> String {
        "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Matches production `normalize` so `ZTVMAZEID` and `tvMazeID` both resolve.
    private func normalizeColumnName(_ name: String) -> String {
        var normalized = name.lowercased().replacingOccurrences(of: "_", with: "")
        if normalized.first == "z" {
            normalized.removeFirst()
        }
        return normalized
    }

    /// Minimal SQLite file that is not a SwiftData store, so only the fallback path runs.
    private func writeIdentityOnlySQLiteStore(at url: URL, id: Int, name: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw RecoveryExportReadError.storeMissing
        }
        defer { sqlite3_close(db) }

        let schema = """
            CREATE TABLE TrackedShowEntity (
                tvMazeID INTEGER,
                name TEXT,
                statusRaw TEXT
            );
            """
        guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else {
            throw RecoveryExportReadError.storeMissing
        }
        let insert = "INSERT INTO TrackedShowEntity (tvMazeID, name, statusRaw) VALUES (?, ?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, insert, -1, &statement, nil) == SQLITE_OK else {
            throw RecoveryExportReadError.storeMissing
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, sqlite3_int64(id))
        sqlite3_bind_text(
            statement, 2, name, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(
            statement, 3, "Running", -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw RecoveryExportReadError.storeMissing
        }
    }

    /// Isolated temp directory per test so parallel runs do not share store files.
    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "recovery-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Representative V1 row; next-season status is set so snapshot corruption is visible.
    private func sampleShow(id: Int, name: String) -> TrackedShow {
        TrackedShow(
            id: id,
            name: name,
            posterMediumURL: nil,
            tvMazeURL: URL(string: "https://www.tvmaze.com/shows/\(id)"),
            status: .running,
            nextSeason: .returningNoSeasonYet,
            sourceUpdatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastCheckedAt: Date(timeIntervalSince1970: 1_700_000_100),
            dateAdded: Date(timeIntervalSince1970: 1_699_000_000)
        )
    }
}
