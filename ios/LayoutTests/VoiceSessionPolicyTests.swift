import XCTest

final class VoiceSessionPolicyTests: XCTestCase {
    func testOnlyConfiguredForegroundVisitCanStart() {
        var policy = VoiceSessionAutoStartPolicy()
        XCTAssertFalse(policy.shouldStart(enabled: false, configured: true, foreground: true, busy: false))
        XCTAssertFalse(policy.shouldStart(enabled: true, configured: false, foreground: true, busy: false))
        XCTAssertFalse(policy.shouldStart(enabled: true, configured: true, foreground: false, busy: false))
        XCTAssertTrue(policy.shouldStart(enabled: true, configured: true, foreground: true, busy: false))
        XCTAssertFalse(policy.shouldStart(enabled: true, configured: true, foreground: true, busy: false))
    }

    func testPermissionSheetAndFailedAttemptDoNotLoop() {
        var policy = VoiceSessionAutoStartPolicy()
        XCTAssertTrue(policy.shouldStart(enabled: true, configured: true, foreground: true, busy: false))
        // didBecomeActive may repeat when permission UI or Control Center closes.
        for _ in 0..<3 {
            XCTAssertFalse(policy.shouldStart(enabled: true, configured: true, foreground: true, busy: false))
        }
        policy.enteredBackground()
        XCTAssertTrue(policy.shouldStart(enabled: true, configured: true, foreground: true, busy: false))
    }

    func testExistingSessionConsumesVisitWithoutExtendingIt() {
        var policy = VoiceSessionAutoStartPolicy()
        XCTAssertFalse(policy.shouldStart(enabled: true, configured: true, foreground: true, busy: true))
        // The session can expire while Lab stays open. Do not silently re-arm it.
        XCTAssertFalse(policy.shouldStart(enabled: true, configured: true, foreground: true, busy: false))
    }

    func testManualStopPersistsUntilNewVisitOrExplicitConfigurationChange() {
        var policy = VoiceSessionAutoStartPolicy()
        policy.userStoppedOrStarted()
        XCTAssertFalse(policy.shouldStart(enabled: true, configured: true, foreground: true, busy: false))
        policy.configurationChanged()
        XCTAssertTrue(policy.shouldStart(enabled: true, configured: true, foreground: true, busy: false))
        policy.userStoppedOrStarted()
        policy.enteredBackground()
        XCTAssertTrue(policy.shouldStart(enabled: true, configured: true, foreground: true, busy: false))
    }
}
