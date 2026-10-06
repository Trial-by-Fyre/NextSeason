// Permanent complimentary Plus is independent of StoreKit purchases.
import Foundation
import Observation

@MainActor
@Observable
final class PlusEntitlementStore {
    static let grandfatheredKey = "plusGrandfathered"
    static let complimentaryKey = "plusComplimentaryPermanent"

    private let userDefaults: UserDefaults
    private let persistence: any ComplimentaryPlusPersistence
    private(set) var isComplimentary = false

    init(
        userDefaults: UserDefaults = .standard,
        persistence: any ComplimentaryPlusPersistence = KeychainComplimentaryPlusPersistence()
    ) {
        self.userDefaults = userDefaults
        self.persistence = persistence
        reconcile()
    }

    /// Only adds access. Failed/temporarily unavailable Keychain reads never revoke it.
    /// Repeated reconciliation also retries failed writes and discovers delayed iCloud sync.
    func reconcile() {
        isComplimentary =
            isComplimentary
            || userDefaults.bool(forKey: Self.complimentaryKey)
            || userDefaults.bool(forKey: Self.grandfatheredKey)
            || persistence.hasEntitlement()
        guard isComplimentary else { return }
        userDefaults.set(true, forKey: Self.complimentaryKey)
        if !persistence.saveEntitlement() {
            AppDiagnosticsLogger.breadcrumb("complimentary_plus_persistence_failed")
        }
    }

    func grantComplimentaryPlus() {
        isComplimentary = true
        reconcile()
    }
}
