//
//  WatchlistRowMarks.swift
//  NextSeason
//

import Foundation

/// Persisted per-row flags shared by the SwiftData repository and the refresh
/// service, so neither depends on the other.
///
/// Each flag is keyed by show ID and valued by the saved row's `dateAdded`
/// (reference-date seconds), which ties it to one saved row: deleting a show and
/// adding it again creates a new row with a new `dateAdded`, so an old flag never
/// applies to it.
struct WatchlistRowMarks {
    /// Unchanged from when the refresh service stored catch-up marks itself, so
    /// marks saved by earlier builds still apply.
    static let catchUpKey = "watchlistCatchUpMarks"
    static let damageReportedKey = "watchlistDamagedSnapshotReports"

    let userDefaults: UserDefaults

    /// Rows awaiting a silent baseline: shows resumed after a Plus lapse, and
    /// rows whose saved next-season snapshot could not be decoded.
    var catchUp: [Int: TimeInterval] {
        get { Self.read(Self.catchUpKey, from: userDefaults) }
        nonmutating set { Self.write(newValue, to: Self.catchUpKey, in: userDefaults) }
    }

    /// Damaged rows already reported to analytics. Kept apart from `catchUp`
    /// because a resumed row can carry a catch-up mark before its damage is first
    /// found, and that first detection must still be reported. Cleared on repair.
    var damageReported: [Int: TimeInterval] {
        get { Self.read(Self.damageReportedKey, from: userDefaults) }
        nonmutating set { Self.write(newValue, to: Self.damageReportedKey, in: userDefaults) }
    }

    private static func read(_ key: String, from userDefaults: UserDefaults) -> [Int: TimeInterval]
    {
        let stored = userDefaults.dictionary(forKey: key) ?? [:]
        var marks: [Int: TimeInterval] = [:]
        for (key, value) in stored {
            if let id = Int(key), let dateAdded = value as? TimeInterval {
                marks[id] = dateAdded
            }
        }
        return marks
    }

    private static func write(
        _ marks: [Int: TimeInterval], to key: String, in userDefaults: UserDefaults
    ) {
        if marks.isEmpty {
            userDefaults.removeObject(forKey: key)
        } else {
            let stored = Dictionary(uniqueKeysWithValues: marks.map { (String($0.key), $0.value) })
            userDefaults.set(stored, forKey: key)
        }
    }
}
