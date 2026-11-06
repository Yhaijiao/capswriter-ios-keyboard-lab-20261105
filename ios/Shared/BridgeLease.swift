import Foundation

/// Temporary server pairing expires before its public address is released.
enum BridgeLease {
    static func apply(address: String, expires: String?, defaults: UserDefaults = .standard) {
        guard let endpoint = BridgeEndpoint(address: address) else { return }
        if let expires = expires, let value = Double(expires), value.isFinite, value > 0 {
            defaults.set(endpoint.normalizedAddress, forKey: "bridge.lease.address")
            defaults.set(value, forKey: "bridge.lease.until")
        } else {
            defaults.removeObject(forKey: "bridge.lease.address")
            defaults.removeObject(forKey: "bridge.lease.until")
        }
    }

    static func expiry(address: String, defaults: UserDefaults = .standard) -> Double? {
        guard let endpoint = BridgeEndpoint(address: address),
              defaults.string(forKey: "bridge.lease.address") == endpoint.normalizedAddress else { return nil }
        let value = defaults.double(forKey: "bridge.lease.until")
        return value > 0 ? value : nil
    }
    static func isExpired(address: String, defaults: UserDefaults = .standard, now: Double = Date().timeIntervalSince1970) -> Bool {
        guard let value = expiry(address: address, defaults: defaults) else { return false }
        return now >= value
    }
}
