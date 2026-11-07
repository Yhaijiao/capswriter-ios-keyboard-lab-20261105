import Foundation
import Security

@MainActor
enum BridgePairingStore {
    private static let service = "org.capswriterlab.voice-pairings"
    private static let sharedSeenKey = "bridge.sharedPairingSeen"
    private static var detectedSigningGroup: String?

    enum StoreError: LocalizedError {
        case unavailable

        var errorDescription: String? { "共享钥匙串不可用，请检查 Lab 与键盘的签名。" }
    }

    static var hasUsedSharedProfiles: Bool { UserDefaults.standard.bool(forKey: sharedSeenKey) }

    static var keyboardReady: Bool {
        guard let query = try? keyboardQuery() else { return false }
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func markKeyboardReady() {
        guard var query = try? keyboardQuery(),
              SecItemCopyMatching(query as CFDictionary, nil) == errSecItemNotFound else { return }
        query[kSecValueData as String] = Data([1])
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        _ = SecItemAdd(query as CFDictionary, nil)
    }

    static func activePairing() -> BridgePairing? {
        if let profiles = try? load() { return profiles.active }
        return hasUsedSharedProfiles ? nil : BridgePairing.legacy()
    }

    static func load() throws -> BridgeProfiles? {
        var query = try profilesQuery()
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw StoreError.unavailable }
        if !hasUsedSharedProfiles { UserDefaults.standard.set(true, forKey: sharedSeenKey) }
        return try JSONDecoder().decode(BridgeProfiles.self, from: data)
    }

    static func save(_ profiles: BridgeProfiles) throws {
        var query = try profilesQuery()
        let data = try JSONEncoder().encode(profiles)
        let changes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw StoreError.unavailable }
        } else if status != errSecSuccess {
            throw StoreError.unavailable
        }
        if !hasUsedSharedProfiles { UserDefaults.standard.set(true, forKey: sharedSeenKey) }
    }

    private static func keyboardQuery() throws -> [String: Any] {
        var query = try profilesQuery()
        query[kSecAttrAccount as String] = "keyboard-ready-v1"
        return query
    }

    private static func profilesQuery() throws -> [String: Any] {
        if detectedSigningGroup == nil {
            let identity: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                           kSecAttrService as String: service,
                                           kSecAttrAccount as String: UUID().uuidString]
            var probe = identity
            probe[kSecReturnAttributes as String] = true
            probe[kSecValueData as String] = Data([1])
            probe[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            var attributes: CFTypeRef?
            let status = SecItemAdd(probe as CFDictionary, &attributes)
            if status == errSecMissingEntitlement { detectedSigningGroup = "" }
            guard status == errSecSuccess else { throw StoreError.unavailable }
            _ = SecItemDelete(identity as CFDictionary)
            detectedSigningGroup = (attributes as? [String: Any])?[kSecAttrAccessGroup as String] as? String ?? ""
        }
        guard let group = detectedSigningGroup,
              let prefix = group.split(separator: ".").first,
              group == "\(prefix).\(service)" else { throw StoreError.unavailable }
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "profiles-v1",
                kSecAttrAccessGroup as String: group]
    }
}
