import Foundation
import XCTest

final class BridgePairingTests: XCTestCase {
    func testSwitchKeepsSeparatePairingsAndCloudExpiry() throws {
        let cloud = try XCTUnwrap(BridgePairing(address: "https://192.0.2.1", token: "cloud-fixture", expires: 100))
        let home = try XCTUnwrap(BridgePairing(address: "http://192.168.1.66:8765", token: "home-fixture"))
        var profiles = BridgeProfiles(legacy: cloud)
        XCTAssertEqual(profiles.selected, .aws)
        profiles.selected = .home
        XCTAssertNil(profiles.active)
        profiles[.home] = home

        var restored = try JSONDecoder().decode(BridgeProfiles.self, from: JSONEncoder().encode(profiles))
        XCTAssertEqual(restored.active, home)
        XCTAssertFalse(home.isExpired(now: 100))
        restored.selected = .aws
        XCTAssertEqual(restored.active, cloud)
        XCTAssertTrue(restored.active?.isExpired(now: 100) == true)
    }

    func testLegacyLANPairingMigratesToHome() throws {
        let home = try XCTUnwrap(BridgePairing(address: "http://192.168.1.66:8765", token: "home-fixture"))
        let profiles = BridgeProfiles(legacy: home)
        XCTAssertEqual(profiles.selected, .home)
        XCTAssertEqual(profiles.active, home)
        XCTAssertNil(profiles[.aws])
    }
}
