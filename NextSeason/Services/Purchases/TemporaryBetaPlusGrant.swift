import StoreKit

#if COMPLIMENTARY_PLUS_BETA_GRANT && !NEXTSEASON_BETA_COMPLIMENTARY_CONFIGURATION
    #error("Complimentary Plus granting requires the dedicated BetaComplimentary configuration.")
#endif

/// TEMPORARY: only the dedicated final beta configuration can enable granting.
/// Delete that configuration/scheme after distribution; recognition stays intact.
@MainActor
enum TemporaryBetaPlusGrant {
    static func isEligible() async -> Bool {
        #if COMPLIMENTARY_PLUS_BETA_GRANT
            guard let result = try? await AppTransaction.shared,
                case .verified(let transaction) = result
            else { return false }
            return allowsGrant(enabled: true, verifiedEnvironment: transaction.environment)
        #else
            return false
        #endif
    }

    static func allowsGrant(enabled: Bool, verifiedEnvironment: AppStore.Environment?) -> Bool {
        enabled && verifiedEnvironment == .sandbox
    }
}
