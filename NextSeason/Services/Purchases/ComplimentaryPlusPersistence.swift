import Foundation
import Security

@MainActor
protocol ComplimentaryPlusPersistence {
    func hasEntitlement() -> Bool
    func saveEntitlement() -> Bool
}

/// App-private synchronizable Keychain item. Keep the service/account and signing
/// identity stable across TestFlight and production. No expiration or renewal data.
@MainActor
struct KeychainComplimentaryPlusPersistence: ComplimentaryPlusPersistence {
    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.TrialByFyre.NextSeason.complimentaryPlus",
            kSecAttrAccount as String: "permanent",
            kSecAttrSynchronizable as String: true,
        ]
    }

    func hasEntitlement() -> Bool {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess else {
            return false
        }
        return (result as? Data) == Data("permanent-plus-v1".utf8)
    }

    func saveEntitlement() -> Bool {
        let value = Data("permanent-plus-v1".utf8)
        var item = query
        item[kSecValueData as String] = value
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem {
            return SecItemUpdate(
                query as CFDictionary,
                [kSecValueData as String: value] as CFDictionary) == errSecSuccess
        }
        return status == errSecSuccess
    }
}
