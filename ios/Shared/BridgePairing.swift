import Foundation

enum BridgeTarget: String, Codable, CaseIterable {
    case home, aws

    var title: String { self == .home ? "家里电脑" : "AWS 云端" }
}

struct BridgePairing: Codable, Equatable {
    let address: String
    let token: String
    let expires: Double?

    init?(address: String, token: String, expires: Double? = nil) {
        guard let endpoint = BridgeEndpoint(address: address), BridgeClient.isValidToken(token),
              expires.map({ $0.isFinite && $0 > 0 }) ?? true else { return nil }
        self.address = endpoint.normalizedAddress
        self.token = token
        self.expires = expires
    }

    func isExpired(now: Double = Date().timeIntervalSince1970) -> Bool {
        expires.map { now >= $0 } ?? false
    }

    static func legacy(defaults: UserDefaults = .standard) -> BridgePairing? {
        let address = defaults.string(forKey: "bridge.address") ?? ""
        return BridgePairing(address: address, token: defaults.string(forKey: "bridge.token") ?? "",
                             expires: BridgeLease.expiry(address: address, defaults: defaults))
    }

    func saveLegacy(defaults: UserDefaults = .standard) {
        defaults.set(address, forKey: "bridge.address")
        defaults.set(token, forKey: "bridge.token")
        BridgeLease.apply(address: address, expires: expires.map { String($0) }, defaults: defaults)
    }
}

struct BridgeProfiles: Codable {
    var selected: BridgeTarget = .aws
    private var pairings: [BridgeTarget: BridgePairing] = [:]

    init(legacy: BridgePairing? = nil) {
        guard let legacy, let endpoint = BridgeEndpoint(address: legacy.address) else { return }
        selected = BridgeEndpoint.isLocalHost(endpoint.host) ? .home : .aws
        pairings[selected] = legacy
    }

    subscript(target: BridgeTarget) -> BridgePairing? {
        get { pairings[target] }
        set { pairings[target] = newValue }
    }

    var active: BridgePairing? { self[selected] }
}
