//
//  PersistentStoreReset.swift
//  NextSeason
//

import Foundation
import SwiftData

/// Destructive recovery for a SwiftData store that will not open.
///
/// Deletes the store file and SwiftData sidecars (`-wal`, `-shm`, migration
/// leftovers). Does not touch UserDefaults, analytics counters, or the
/// bundled show ID mapping database.
enum PersistentStoreReset {
    /// SwiftData's default on-disk URL (`Application Support/default.store`).
    /// Must stay aligned with `NextSeasonModelContainer.make()` so recovery
    /// removes the same files production opens. Under the DEBUG recovery
    /// fixture this is the fixture's disposable store, which the app opens instead.
    static var productionStoreURL: URL {
        RecoveryFixture.storeURL ?? ModelConfiguration().url
    }

    /// Removes the production watchlist store. Call only from the user-facing
    /// recovery flow — this permanently deletes saved shows on this device.
    static func removeProductionStore(fileManager: FileManager = .default) throws {
        try removeStore(at: productionStoreURL, fileManager: fileManager)
    }

    /// Deletes `url` and sibling files whose names start with the store
    /// file name, then allows a later `ModelContainer` open to create a
    /// fresh empty store.
    static func removeStore(
        at url: URL,
        fileManager: FileManager = .default
    ) throws {
        let directory = url.deletingLastPathComponent()
        let prefix = url.lastPathComponent
        guard fileManager.fileExists(atPath: directory.path) else { return }

        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for fileURL in contents where fileURL.lastPathComponent.hasPrefix(prefix) {
            try fileManager.removeItem(at: fileURL)
        }
    }
}
