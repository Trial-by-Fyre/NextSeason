//
//  RecoveryFixture.swift
//  NextSeason
//

import Foundation
import SwiftData

/// DEBUG-only launch arguments that put the app into persistence recovery
/// without touching the real watchlist, for the device checks in
/// `Documentation/Reviews/LaunchRegistrationRecovery-2026-11-05.md`.
///
/// Any fixture argument makes the app use a disposable store and an isolated
/// defaults suite for store-tied state, and makes Reset Local Data skip clearing
/// delivered and pending notifications (they may belong to the real watchlist).
///
/// - `-RecoveryFixtureOpenFailures N`: the first `N` compositions in this
///   process throw (at launch, then on each Reset Local Data or Try Again);
///   later ones succeed. With `2`: launch fails, Reset wipes the disposable
///   store but reopening fails, then Try Again succeeds.
/// - `-RecoveryFixtureCrashLoop`: launch shows crash-loop recovery without
///   composing; Try Again then composes, subject to any injected failures.
///
/// Release builds compile the behavior out: everything reports inactive.
enum RecoveryFixture {
    static let openFailuresArgument = "-RecoveryFixtureOpenFailures"
    static let crashLoopArgument = "-RecoveryFixtureCrashLoop"

    /// True when any fixture argument is present.
    static var isActive: Bool {
        #if DEBUG
            return arguments.contains(openFailuresArgument)
                || arguments.contains(crashLoopArgument)
        #else
            return false
        #endif
    }

    /// True when launch should present crash-loop recovery.
    static var forcesCrashLoop: Bool {
        #if DEBUG
            return arguments.contains(crashLoopArgument)
        #else
            return false
        #endif
    }

    /// Throws while injected open failures remain, consuming one per call.
    static func throwIfOpenFailureInjected() throws {
        #if DEBUG
            guard remainingOpenFailures > 0 else { return }
            remainingOpenFailures -= 1
            AppDiagnosticsLogger.breadcrumb("recovery_fixture_open_failure_injected")
            throw InjectedOpenFailure(remainingAfterThis: remainingOpenFailures)
        #endif
    }

    /// The disposable store, in its own Application Support subdirectory, or
    /// nil when the fixture is inactive. Reset Local Data removes only this.
    static var storeURL: URL? {
        #if DEBUG
            guard isActive else { return nil }
            return URL.applicationSupportDirectory
                .appending(path: "RecoveryFixture", directoryHint: .isDirectory)
                .appending(path: "default.store")
        #else
            return nil
        #endif
    }

    /// Configuration for the disposable store, or nil when inactive.
    static func storeConfiguration() throws -> ModelConfiguration? {
        guard let storeURL else { return nil }
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        return ModelConfiguration(url: storeURL)
    }

    /// Isolated defaults for store-tied state (refresh watermark, catch-up
    /// marks, pause state), or nil when inactive.
    static var watchlistDefaults: UserDefaults? {
        #if DEBUG
            guard isActive else { return nil }
            return UserDefaults(suiteName: "com.TrialByFyre.NextSeason.RecoveryFixture")
        #else
            return nil
        #endif
    }

    #if DEBUG
        private static let arguments = ProcessInfo.processInfo.arguments

        /// Parsed once per process; each composition attempt consumes one.
        private static var remainingOpenFailures: Int = {
            guard let index = arguments.firstIndex(of: openFailuresArgument),
                arguments.indices.contains(index + 1),
                let count = Int(arguments[index + 1])
            else { return 0 }
            return max(count, 0)
        }()

        struct InjectedOpenFailure: Error, CustomStringConvertible {
            let remainingAfterThis: Int
            var description: String {
                "Recovery fixture: injected store open failure (\(remainingAfterThis) remaining)"
            }
        }
    #endif
}
