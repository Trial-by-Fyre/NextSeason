import Foundation
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
            return await evaluateEligibility(
                enabled: true,
                verifiedEnvironment: {
                    switch try await AppTransaction.shared {
                    case .verified(let transaction):
                        return transaction.environment
                    case .unverified(_, let error):
                        let error = error as NSError
                        AppDiagnosticsLogger.breadcrumb(
                            "complimentary_plus_transaction_unverified domain=\(error.domain) code=\(error.code)"
                        )
                        return nil
                    }
                },
                hasSandboxReceipt: {
                    // Same TestFlight fallback used by BetaBuildAvailability.
                    // This is a channel signal, not cryptographic verification.
                    (Bundle.main.value(forKey: "appStoreReceiptURL") as? URL)?
                        .lastPathComponent == "sandboxReceipt"
                }
            )
        #else
            AppDiagnosticsLogger.breadcrumb("complimentary_plus_grant_disabled")
            return false
        #endif
    }

    /// A nil environment means verification failed, not that StoreKit was unavailable.
    /// Receipt fallback is allowed only on a thrown lookup error. A verified
    /// production/Xcode transaction or failed verification always rejects access.
    static func evaluateEligibility(
        enabled: Bool,
        verifiedEnvironment: @MainActor () async throws -> AppStore.Environment?,
        hasSandboxReceipt: @MainActor () -> Bool,
        record: @MainActor (String) -> Void = AppDiagnosticsLogger.breadcrumb
    ) async -> Bool {
        guard enabled else {
            record("complimentary_plus_grant_disabled")
            return false
        }
        do {
            guard let environment = try await verifiedEnvironment() else {
                record("complimentary_plus_grant_rejected_unverified")
                return false
            }
            let eligible = allowsGrant(enabled: true, verifiedEnvironment: environment)
            record(
                "complimentary_plus_verified_environment=\(environment) eligible=\(eligible)"
            )
            return eligible
        } catch is CancellationError {
            record("complimentary_plus_grant_cancelled")
            return false
        } catch {
            let error = error as NSError
            record(
                "complimentary_plus_transaction_unavailable domain=\(error.domain) code=\(error.code)"
            )
            let eligible = hasSandboxReceipt()
            record("complimentary_plus_receipt_fallback eligible=\(eligible)")
            return eligible
        }
    }

    static func allowsGrant(enabled: Bool, verifiedEnvironment: AppStore.Environment?) -> Bool {
        enabled && verifiedEnvironment == .sandbox
    }
}
