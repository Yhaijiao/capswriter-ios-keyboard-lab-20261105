import Foundation
import XCTest

final class BridgeLeaseTests: XCTestCase {
    func testTemporaryPairingStopsBeforeReleasedAddressIsContacted() {
        let name = "CapsWriterLeaseTest." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        BridgeLease.apply(address: "https://192.0.2.1", expires: "100", defaults: defaults)
        XCTAssertFalse(BridgeLease.isExpired(address: "https://192.0.2.1/ignored", defaults: defaults, now: 99))
        XCTAssertTrue(BridgeLease.isExpired(address: "https://192.0.2.1", defaults: defaults, now: 100))
        XCTAssertFalse(BridgeLease.isExpired(address: "http://192.168.1.66:8765", defaults: defaults, now: 101))
        BridgeLease.apply(address: "https://192.0.2.1", expires: nil, defaults: defaults)
        XCTAssertNil(BridgeLease.expiry(address: "https://192.0.2.1", defaults: defaults))
    }
}
