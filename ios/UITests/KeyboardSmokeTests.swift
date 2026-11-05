import XCTest

final class KeyboardSmokeTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func findAndTap(_ element: XCUIElement, in app: XCUIApplication) {
        // XCTest scrolls table cells into view before tapping. Stale cell frames
        // during Settings navigation must not be used as screen coordinates.
        XCTAssertTrue(element.waitForExistence(timeout: 15), app.debugDescription)
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
        settings.terminate()

        let app = XCUIApplication()
        app.launch()
        let editor = app.textViews["lab-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        app.buttons["清空测试区"].firstMatch.tap()
        editor.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 15) {
            attach(app, name: "Keyboard activation retry")
            editor.tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 20), app.debugDescription)
        dismissSystemTypingIntroduction(in: app, wait: true)
        let testButton = app.buttons["keyboard-test-button"]
        for _ in 0..<6 {
            if testButton.exists { break }
            dismissSystemTypingIntroduction(in: app, wait: false)
            let next = app.buttons["Next keyboard"].firstMatch
            if next.waitForExistence(timeout: 5) {
                next.tap()
                if testButton.waitForExistence(timeout: 30) { break }
            }
            // On a cold shared runner, UIKit may take >40s to launch the
            // extension and its first host connection can expire. Refocus the
            // editor so the now-warm extension gets a fresh host connection.
            if !app.keyboards.firstMatch.exists {
                attach(app, name: "Cold extension connection retry")
                editor.tap()
                if testButton.waitForExistence(timeout: 15) { break }
            }
        }
        XCTAssertTrue(testButton.waitForExistence(timeout: 10), app.debugDescription)
        testButton.tap()
        XCTAssertTrue((editor.value as? String ?? "").contains("这是 CapsWriter 手机键盘测试。"))
        app.buttons["keyboard-return"].tap()
        XCTAssertTrue((editor.value as? String ?? "").hasSuffix("\n"))

        let selector = app.segmentedControls["keyboard-mode-selector"]
        app.scrollViews["keyboard-pages"].swipeLeft()
        XCTAssertTrue(app.buttons["key-h"].waitForExistence(timeout: 5))
        for letter in "hello" { app.buttons["key-" + String(letter)].tap() }
        XCTAssertTrue((editor.value as? String ?? "").hasSuffix("hello"))
        attach(app, name: "English keyboard")

        app.scrollViews["keyboard-pages"].swipeLeft()
        XCTAssertTrue(app.staticTexts["pinyin-composition"].waitForExistence(timeout: 5))
        for letter in "nihao" { app.buttons["key-" + String(letter)].tap() }
        let candidate = app.buttons["candidate-你好"]
        XCTAssertTrue(candidate.waitForExistence(timeout: 5))
        attach(app, name: "Chinese pinyin candidates")
        candidate.tap()
        XCTAssertTrue((editor.value as? String ?? "").hasSuffix("你好"))
        for letter in "wo" { app.buttons["key-" + String(letter)].tap() }
        XCTAssertTrue(app.buttons["candidate-我"].waitForExistence(timeout: 5))
        // Candidate scrolling belongs to the candidate row, not the page pager.
        app.scrollViews["pinyin-candidates"].swipeLeft()
        XCTAssertTrue(app.staticTexts["pinyin-composition"].exists)
        app.buttons["key-m"].tap()
        let unfinished = app.buttons["candidate-我们"]
        XCTAssertTrue(unfinished.waitForExistence(timeout: 5))
        attach(app, name: "Unfinished wom predicts women")
        unfinished.tap()
        XCTAssertTrue((editor.value as? String ?? "").hasSuffix("你好我们"))
        attach(app, name: "Chinese pinyin keyboard")
        app.scrollViews["keyboard-pages"].swipeLeft()
        XCTAssertTrue(testButton.waitForExistence(timeout: 5))
        attach(app, name: "Voice test keyboard")
        app.scrollViews["keyboard-pages"].swipeRight()
        XCTAssertTrue(app.staticTexts["pinyin-composition"].waitForExistence(timeout: 5))
        app.scrollViews["keyboard-pages"].swipeRight()
        XCTAssertTrue(app.buttons["key-h"].waitForExistence(timeout: 5))
        app.scrollViews["keyboard-pages"].swipeRight()
        XCTAssertTrue(testButton.waitForExistence(timeout: 5))
        // Direct mode selection uses the same sliding transition.
        selector.buttons["EN"].tap()
        XCTAssertTrue(app.buttons["key-h"].waitForExistence(timeout: 5))
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func dismissSystemTypingIntroduction(in app: XCUIApplication, wait: Bool) {
        let introduction = app.staticTexts.matching(NSPredicate(format:
            "label BEGINSWITH %@", "Speed up your typing by sliding your finger")).firstMatch
        let visible = wait ? introduction.waitForExistence(timeout: 3) : introduction.exists
        if visible {
            let proceed = app.buttons["Continue"].firstMatch
            XCTAssertTrue(proceed.waitForExistence(timeout: 3))
            proceed.tap()
        }
    }
}
