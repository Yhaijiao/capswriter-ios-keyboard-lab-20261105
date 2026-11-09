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
        let installed = settings.cells.matching(NSPredicate(format: "label CONTAINS %@", "SayKey Lab")).firstMatch
        if !installed.exists {
            findAndTap(settings.cells["AddNewKeyboard"].firstMatch, in: settings)
            let thirdParty = settings.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "SayKey Lab")).firstMatch
            findAndTap(thirdParty, in: settings)
        }
        settings.terminate()

        let app = XCUIApplication()
        app.terminate()
        app.launch()
        let editor = app.textViews["lab-editor"]
        // Cold shared runners can return from launch before the app has a
        // foreground window (orientation 0, empty AX tree). Activate explicitly
        // rather than treating that setup delay as a keyboard input failure.
        if !editor.waitForExistence(timeout: 30) {
            attach(app, name: "Main app activation retry")
            app.activate()
        }
        XCTAssertTrue(editor.waitForExistence(timeout: 30), app.debugDescription)
        app.buttons["清空测试区"].firstMatch.tap()
        editor.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 15) {
            attach(app, name: "Keyboard activation retry")
            editor.tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 20), app.debugDescription)
        dismissSystemTypingIntroduction(in: app, wait: true)
        let testButton = app.buttons["keyboard-voice-button"]
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
        let pageBounds = app.scrollViews["keyboard-pages"].frame
        XCTAssertLessThanOrEqual(pageBounds.height, 216, "Normal compact body must not retain the extra footer row")
        XCTAssertGreaterThanOrEqual(testButton.frame.minY, pageBounds.minY)
        XCTAssertLessThanOrEqual(testButton.frame.maxY, pageBounds.maxY)
        app.buttons["keyboard-return"].tap()
        XCTAssertTrue((editor.value as? String ?? "").hasSuffix("\n"))
        let voiceReturnBottom = app.buttons["keyboard-return"].frame.maxY

        let selector = app.segmentedControls["keyboard-mode-selector"]
        app.scrollViews["keyboard-pages"].swipeLeft()
        XCTAssertTrue(app.buttons["key-h"].waitForExistence(timeout: 5))
        let englishTop = app.buttons["key-q"].frame.minY
        XCTAssertEqual(app.buttons["keyboard-return"].frame.maxY, voiceReturnBottom, accuracy: 1)
        for letter in "hello" { app.buttons["key-" + String(letter)].tap() }
        XCTAssertTrue((editor.value as? String ?? "").hasSuffix("hello"))
        attach(app, name: "English keyboard")

        app.scrollViews["keyboard-pages"].swipeLeft()
        waitForMode("拼", in: selector)
        XCTAssertEqual(app.buttons["key-q"].frame.minY, englishTop, accuracy: 1)
        XCTAssertEqual(app.buttons["keyboard-return"].frame.maxY, voiceReturnBottom, accuracy: 1)
        attach(app, name: "Aligned idle Chinese keyboard")
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
        XCTAssertTrue(app.buttons["candidate-我妈"].exists)
        attach(app, name: "Unfinished wom predicts women")
        app.buttons["pinyin-expand-candidates"].tap()
        let gridChoice = app.buttons["grid-candidate-我妈"]
        XCTAssertTrue(gridChoice.waitForExistence(timeout: 5))
        XCTAssertTrue(gridChoice.isHittable)
        XCTAssertFalse(app.buttons["grid-candidate-我们"].exists)
        XCTAssertTrue(unfinished.isHittable)
        attach(app, name: "Expanded pinyin candidate grid")
        unfinished.tap()
        XCTAssertFalse(gridChoice.isHittable, "Selecting the primary suggestion collapses the grid")
        XCTAssertTrue((editor.value as? String ?? "").hasSuffix("你好我们"))
        for letter in "nihaom" { app.buttons["key-" + String(letter)].tap() }
        XCTAssertTrue(app.buttons["candidate-你好吗"].waitForExistence(timeout: 5))
        attach(app, name: "Composed nihaom phrase")
        app.buttons["candidate-你好吗"].tap()
        XCTAssertTrue((editor.value as? String ?? "").hasSuffix("你好我们你好吗"))
        for (spelling, text) in [("wm", "我们"), ("nihm", "你好吗"), ("womxianz", "我们现在")] {
            for letter in spelling { app.buttons["key-" + String(letter)].tap() }
            let mixed = app.buttons["candidate-" + text]
            XCTAssertTrue(mixed.waitForExistence(timeout: 5))
            mixed.tap()
            XCTAssertTrue((editor.value as? String ?? "").hasSuffix(text))
        }
        attach(app, name: "Chinese pinyin keyboard")
        app.scrollViews["keyboard-pages"].swipeLeft()
        XCTAssertTrue(testButton.waitForExistence(timeout: 5))
        attach(app, name: "Voice test keyboard")
        app.scrollViews["keyboard-pages"].swipeRight()
        waitForMode("拼", in: selector)
        app.scrollViews["keyboard-pages"].swipeRight()
        XCTAssertTrue(app.buttons["key-h"].waitForExistence(timeout: 5))
        app.scrollViews["keyboard-pages"].swipeRight()
        XCTAssertTrue(testButton.waitForExistence(timeout: 5))
        // Direct mode selection uses the same sliding transition.
        selector.buttons["EN"].tap()
        XCTAssertTrue(app.buttons["key-h"].waitForExistence(timeout: 5))
        for _ in 0..<30 { app.buttons["key-a"].tap() }
        let before = (editor.value as? String ?? "").count
        app.buttons["keyboard-delete"].tap()
        XCTAssertEqual((editor.value as? String ?? "").count, before - 1)
        app.buttons["keyboard-delete"].press(forDuration: 1.6)
        let afterHold = editor.value as? String ?? ""
        XCTAssertLessThan(afterHold.count, before - 3)
        Thread.sleep(forTimeInterval: 0.35)
        XCTAssertEqual(editor.value as? String ?? "", afterHold, "Deletion must stop on release")
    }

    private func waitForMode(_ name: String, in selector: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: selector.buttons[name])
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
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
