import Foundation
import StoreKit

/// Local StoreKit can expose an Ask to Buy transaction as a current entitlement
/// while its renewal state is unknown (raw 0). Do not change App Store or sandbox
/// access policy to compensate for that Xcode-only inconsistency.
@MainActor
enum XcodeSubscriptionValidation {
    struct Status {
        let id: UInt64
        let originalID: UInt64
        let purchaseDate: Date
        let state: Product.SubscriptionInfo.RenewalState
        let isVerified: Bool
    }

    static func check(
        isXcode: Bool, transactionID: UInt64, originalID: UInt64, purchaseDate: Date,
        loadStatuses: () async throws -> [Status]
    ) async -> PlusEntitlementCheck {
        guard isXcode else { return .active }
        guard let statuses = try? await loadStatuses() else { return .unverified }
        var sawInactive = false
        var sawUnknown = false
        for status in statuses {
            // A newer transaction in the same lineage can resolve a historical
            // unfinished transaction. An older or unrelated one cannot approve it.
            guard status.originalID == originalID,
                status.id == transactionID || status.purchaseDate > purchaseDate
            else { continue }
            guard status.isVerified else {
                sawUnknown = true
                continue
            }
            switch status.state {
            case .subscribed, .inGracePeriod:
                return .active
            case .expired, .inBillingRetryPeriod, .revoked:
                sawInactive = true
            default:
                sawUnknown = true
            }
        }
        if sawInactive && !sawUnknown { return .inactive }
        return .unverified
    }
}
