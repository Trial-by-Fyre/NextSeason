//
//  BetaBuildConfiguration.swift
//  NextSeason
//

import Foundation
import Observation
import StoreKit

/// Tracks whether beta-only diagnostics are available in the current build/runtime.
///
/// DEBUG builds are always allowed. A custom TESTFLIGHT compilation condition is
/// also supported for beta-only archives, but normal App Store production builds
/// rely on StoreKit's app transaction environment instead of the deprecated
/// appStoreReceiptURL API.
@MainActor
@Observable
final class BetaBuildAvailability {
    static let shared = BetaBuildAvailability()

    private(set) var appStoreEnvironment: AppStore.Environment?
    private(set) var detectionAttempted = false

    var isAvailable: Bool {
        #if DEBUG
            return true
        #elseif TESTFLIGHT
            return true
        #else
            return appStoreEnvironment == .sandbox || hasSandboxReceipt
        #endif
    }

    private var hasSandboxReceipt: Bool {
        // Runtime fallback for TestFlight. Accessed with KVC to avoid the iOS 18
        // deprecation warning from Bundle.appStoreReceiptURL while still handling
        // TestFlight builds where AppTransaction is unavailable or delayed.
        (Bundle.main.value(forKey: "appStoreReceiptURL") as? URL)?.lastPathComponent
            == "sandboxReceipt"
    }

    var channelDisplayName: String {
        #if DEBUG
            return String(localized: "Debug")
        #elseif TESTFLIGHT
            return String(localized: "TestFlight")
        #else
            guard detectionAttempted else { return String(localized: "Detecting…") }

            if hasSandboxReceipt {
                return String(localized: "TestFlight")
            }

            switch appStoreEnvironment {
            case .sandbox:
                return String(localized: "TestFlight / Sandbox")
            case .production:
                return String(localized: "App Store")
            case .xcode:
                return String(localized: "Xcode")
            case .none:
                return String(localized: "Production")
            default:
                return String(localized: "Unknown")
            }
        #endif
    }

    func refresh() async {
        #if DEBUG
            detectionAttempted = true
            appStoreEnvironment = .xcode
        #elseif TESTFLIGHT
            detectionAttempted = true
            appStoreEnvironment = .sandbox
        #else
            do {
                let result = try await AppTransaction.shared
                switch result {
                case .verified(let appTransaction):
                    appStoreEnvironment = appTransaction.environment
                case .unverified(let appTransaction, _):
                    appStoreEnvironment = appTransaction.environment
                }
            } catch {
                appStoreEnvironment = nil
            }
            detectionAttempted = true
        #endif
    }
}

/// Convenience wrapper for call sites that do not need to observe changes.
enum BetaBuildConfiguration {
    @MainActor
    static var isAvailable: Bool {
        BetaBuildAvailability.shared.isAvailable
    }

    @MainActor
    static var channelDisplayName: String {
        BetaBuildAvailability.shared.channelDisplayName
    }

    @MainActor
    static func refreshDetection() async {
        await BetaBuildAvailability.shared.refresh()
    }
}
