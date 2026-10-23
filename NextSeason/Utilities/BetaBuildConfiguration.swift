//
//  BetaBuildConfiguration.swift
//  NextSeason
//

import Foundation
import Observation
import StoreKit

/// Tracks whether beta-only diagnostics are available in the current build/runtime.
///
/// DEBUG builds are always allowed. Release builds detect TestFlight through
/// StoreKit's app transaction environment, with a receipt fallback for Diagnostics
/// visibility only. Access overrides require verified app provenance.
@MainActor
@Observable
final class BetaBuildAvailability {
    static let shared = BetaBuildAvailability()

    private(set) var appStoreEnvironment: AppStore.Environment?
    private(set) var detectionAttempted = false
    private var hasVerifiedSandboxAppTransaction = false

    /// Stricter than Diagnostics visibility: never trust an unverified transaction
    /// or receipt fallback to override access in a release build.
    var allowsFreeTierSimulation: Bool {
        #if DEBUG
            return true
        #else
            return hasVerifiedSandboxAppTransaction
        #endif
    }

    /// App provenance only; subscription transaction environments are irrelevant.
    /// An App Store install making sandbox purchases is still a production app and
    /// must not gain access to the override. Unknown provenance also rejects it.
    static func releaseAllowsFreeTierSimulation(
        environment: AppStore.Environment?, isVerified: Bool
    ) -> Bool {
        isVerified && environment == .sandbox
    }

    /// General Diagnostics visibility may use the receipt fallback. Controls that
    /// change effective access must use `allowsFreeTierSimulation` instead.
    var isAvailable: Bool {
        #if DEBUG
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

    /// Refreshes display information and verified override eligibility separately.
    /// Verification failure clears eligibility even if a beta channel can still be
    /// displayed using unverified data or the receipt fallback. A thrown lookup
    /// never grants eligibility but keeps one already verified in this process.
    func refresh() async {
        #if DEBUG
            detectionAttempted = true
            appStoreEnvironment = .xcode
        #else
            // Access overrides depend on this flag, so log any change to it.
            let wasEligible = hasVerifiedSandboxAppTransaction
            defer {
                if hasVerifiedSandboxAppTransaction != wasEligible {
                    AppDiagnosticsLogger.breadcrumb(
                        "override_eligibility_changed=\(hasVerifiedSandboxAppTransaction)")
                }
            }
            do {
                let result = try await AppTransaction.shared
                switch result {
                case .verified(let appTransaction):
                    appStoreEnvironment = appTransaction.environment
                    hasVerifiedSandboxAppTransaction = Self.releaseAllowsFreeTierSimulation(
                        environment: appTransaction.environment, isVerified: true)
                case .unverified(let appTransaction, _):
                    hasVerifiedSandboxAppTransaction = false
                    appStoreEnvironment = appTransaction.environment
                }
            } catch {
                // A lookup failure (offline, or the calling view's task cancelled)
                // says nothing new about provenance, which cannot change within a
                // process. Keep an earlier verified sandbox result so access
                // overrides do not silently switch off and resume paused shows.
                if !hasVerifiedSandboxAppTransaction {
                    appStoreEnvironment = nil
                }
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
