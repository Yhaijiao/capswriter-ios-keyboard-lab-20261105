import XCTest

final class KeyboardSmokeTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func findAndTap(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 {
            if element.exists {
                let frame = element.frame
                if !frame.isEmpty && app.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) {
                    element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                    return
                }
            }
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), app.debugDescription)
        element.tap()
    }

    func testKeyboardInputAndModeCycle() {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        findAndTap(settings.staticTexts["General"].firstMatch, in: settings)
        findAndTap(settings.cells["Keyboard"].firstMatch, in: settings)
        findAndTap(settings.cells["KEYBOARDS"].firstMatch, in: settings)
        findAndTap(settings.cells["AddNewKeyboard"].firstMatch, in: settings)
        let thirdParty = settings.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "CapsWriter Lab")).firstMatch
        findAndTap(thirdParty, in: settings)

        let app = XCUIApplication()
        app.launch()
        let editor = app.textViews["lab-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        app.buttons["清空测试区"].firstMatch.tap()
        editor.tap()
        let testButton = app.buttons["keyboard-test-button"]
        for _ in 0..<6 {
            if testButton.exists { break }
            let next = app.buttons["Next keyboard"].firstMatch
            XCTAssertTrue(next.waitForExistence(timeout: 5), app.debugDescription)
            next.tap()
        }
        XCTAssertTrue(testButton.waitForExistence(timeout: 10), app.debugDescription)
        testButton.tap()
        XCTAssertTrue((editor.value as? String ?? "").contains("这是 CapsWriter 手机键盘测试。"))
        app.buttons["keyboard-return"].tap()
        XCTAssertTrue((editor.value as? String ?? "").hasSuffix("\n"))

        let selector = app.segmentedControls["keyboard-mode-selector"]
        selector.swipeLeft()
        XCTAssertTrue(app.buttons["key-h"].waitForExistence(timeout: 5))
        for letter in "hello" { app.buttons["key-" + String(letter)].tap() }
        XCTAssertTrue((editor.value as? String ?? "").hasSuffix("hello"))
        attach(app, name: "English keyboard")

        selector.swipeLeft()
        XCTAssertTrue(app.staticTexts["pinyin-composition"].waitForExistence(timeout: 5))
        for letter in "nihao" { app.buttons["key-" + String(letter)].tap() }
        let candidate = app.buttons["candidate-你好"]
        XCTAssertTrue(candidate.waitForExistence(timeout: 5))
        candidate.tap()
        XCTAssertTrue((editor.value as? String ?? "").hasSuffix("你好"))
        attach(app, name: "Chinese pinyin keyboard")
        selector.swipeLeft()
        XCTAssertTrue(testButton.waitForExistence(timeout: 5))
        attach(app, name: "Voice test keyboard")
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
