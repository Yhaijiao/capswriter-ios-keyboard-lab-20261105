import UIKit
import XCTest

final class KeyboardLayoutTests: XCTestCase {
    @MainActor func testFreshKeyboardConstructionAndAlignedRows() async {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let previousKeyWindow = scene?.windows.first { $0.isKeyWindow }
        let window: UIWindow
        if let scene = scene { window = UIWindow(windowScene: scene) }
        else { window = UIWindow(frame: UIScreen.main.bounds) }
        let host = UIViewController()
        host.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousKeyWindow?.makeKeyAndVisible() }
        host.loadViewIfNeeded()
        let controller = KeyboardViewController()
        // This exercises the production UIKit code, including all three pages.
        // Activating constraints between unattached keys crashes at this point.
        controller.loadViewIfNeeded()
        let root = controller.view!
        root.overrideUserInterfaceStyle = .dark
        // Host the controller so UIKit invokes its layout lifecycle. A detached
        // view's layoutIfNeeded does not invoke viewDidLayoutSubviews reliably.
        host.addChild(controller)
        root.translatesAutoresizingMaskIntoConstraints = false
        host.view.addSubview(root)
        let hostHeight = root.heightAnchor.constraint(equalToConstant: 500)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            root.topAnchor.constraint(equalTo: host.view.topAnchor),
            hostHeight
        ])
        controller.didMove(toParent: host)
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        root.setNeedsLayout(); root.layoutIfNeeded()
        // Let the new window finish its appearance/display transaction before
        // inspecting its rendered state and restoring the previous key window.
        try? await Task.sleep(nanoseconds: 150_000_000)
        host.view.layoutIfNeeded(); root.layoutIfNeeded()
        let views = descendants(root)
        let pager = views.first { $0.accessibilityIdentifier == "keyboard-pages" } as! UIScrollView
        XCTAssertEqual(pager.contentSize.width, pager.bounds.width * 3, accuracy: 1)
        XCTAssertEqual(pager.contentOffset.x, pager.bounds.width, accuracy: 1, "Initial page must be the center voice page")
        let mic = views.first { $0.accessibilityIdentifier == "keyboard-voice-button" }!
        let micFrame = mic.convert(mic.bounds, to: root)
        XCTAssertEqual(micFrame.midX, root.bounds.midX, accuracy: 1)
        XCTAssertGreaterThanOrEqual(micFrame.minX, 0)
        XCTAssertLessThanOrEqual(micFrame.maxX, root.bounds.width)
        // Reproduce the cold extension's size negotiation, not only a detached
        // screenshot at one fixed size. No page may scroll vertically.
        for height in [CGFloat(272), 380, 272] {
            hostHeight.constant = height
            host.view.layoutIfNeeded(); root.layoutIfNeeded()
            XCTAssertEqual(pager.contentSize.height, pager.bounds.height, accuracy: 1)
            XCTAssertEqual(pager.contentOffset.y, 0, accuracy: 1)
            let inPager = mic.convert(mic.bounds, to: pager)
            XCTAssertGreaterThanOrEqual(inPager.minY, 0)
            XCTAssertLessThanOrEqual(inPager.maxY, pager.bounds.height, "Entire mic must be visible without vertical scrolling")
        }
        let hotwords = views.first { $0.accessibilityIdentifier == "keyboard-hotwords" }!
        let hotFrame = hotwords.convert(hotwords.bounds, to: pager)
        XCTAssertGreaterThanOrEqual(hotFrame.minY, 0)
        XCTAssertLessThanOrEqual(hotFrame.maxY, pager.bounds.height)
        let firstKeys = views.filter { $0.accessibilityIdentifier == "key-q" }
        let returns = views.filter { $0.accessibilityIdentifier == "keyboard-return" }
        XCTAssertEqual(firstKeys.count, 2, "English and pinyin pages must both be constructed")
        XCTAssertEqual(returns.count, 3, "Voice and both text pages must be constructed")
        guard firstKeys.count == 2, returns.count == 3 else { return }
        let voiceReturns = returns.filter { $0.bounds.width > 100 }
        XCTAssertEqual(voiceReturns.count, 1)
        if let voiceReturn = voiceReturns.first {
            XCTAssertEqual(voiceReturn.convert(voiceReturn.bounds, to: root).midX, root.bounds.midX, accuracy: 1)
        }
        let firstTop = firstKeys[0].convert(firstKeys[0].bounds, to: root).minY
        XCTAssertGreaterThan(firstKeys[0].bounds.width, 0)
        XCTAssertEqual(firstKeys[1].convert(firstKeys[1].bounds, to: root).minY, firstTop, accuracy: 1)
        let bottom = returns[0].convert(returns[0].bounds, to: root).maxY
        for key in returns {
            XCTAssertEqual(key.bounds.height, 44, accuracy: 1)
            XCTAssertEqual(key.convert(key.bounds, to: root).maxY, bottom, accuracy: 1)
        }
        let image = UIGraphicsImageRenderer(size: root.bounds.size).image { _ in
            root.drawHierarchy(in: root.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Fresh keyboard layout"; attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testHotwordEditorUsesOwnTextAndUnicodeDelete() async {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let previousKeyWindow = scene?.windows.first { $0.isKeyWindow }
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        let host = UIViewController(); host.overrideUserInterfaceStyle = .dark
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; previousKeyWindow?.makeKeyAndVisible() }
        host.loadViewIfNeeded()
        let controller = KeyboardViewController(); controller.loadViewIfNeeded()
        host.addChild(controller)
        let root = controller.view!; root.translatesAutoresizingMaskIntoConstraints = false
        host.view.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: host.view.topAnchor),
            root.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            root.heightAnchor.constraint(equalToConstant: 416)
        ])
        controller.didMove(toParent: host)
        controller.showHotwordEditor(HotwordFile(id: "hot", name: "hot.txt", text: "开始\n🧑🏽‍💻", revision: "fixture", writable: true))
        host.view.layoutIfNeeded(); root.layoutIfNeeded()
        let editor = descendants(root).first { $0.accessibilityIdentifier == "hotword-editor-text" } as! UITextView
        let delete = visibleButton("keyboard-delete", in: root)
        delete.sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(editor.text, "开始\n", "One delete removes the entire composed emoji")
        for letter in "wom" { visibleButton("key-" + String(letter), in: root).sendActions(for: .primaryActionTriggered) }
        visibleButton("candidate-我们", in: root).sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(editor.text, "开始\n我们", "Pinyin selection edits the hotword draft")
        visibleButton("keyboard-return", in: root).sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(editor.text, "开始\n我们\n")
        let image = UIGraphicsImageRenderer(size: root.bounds.size).image { _ in
            root.drawHierarchy(in: root.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Hotword editor with internal keyboard"; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor func testHotwordBrowserRespectsWritableFileFlag() {
        let manager = HotwordManagerView(frame: CGRect(x: 0, y: 0, width: 430, height: 272))
        let files = [HotwordFile(id: "hot", name: "hot.txt", text: "CapsWriter", revision: "a", writable: true),
                     HotwordFile(id: "asr", name: "hot-server.txt", text: "演示", revision: "b", writable: false)]
        var editedID: String?
        manager.onEdit = { editedID = $0.id }
        manager.show(files: files)
        let edit = descendants(manager).first { $0.accessibilityIdentifier == "hotword-edit" } as! UIButton
        XCTAssertTrue(edit.isEnabled)
        edit.sendActions(for: .touchUpInside)
        XCTAssertEqual(editedID, "hot")
        manager.show(files: files, selectedID: "asr")
        XCTAssertFalse(edit.isEnabled)
        let content = descendants(manager).first { $0.accessibilityIdentifier == "hotword-file-content" } as! UITextView
        XCTAssertEqual(content.text, "演示")
        XCTAssertFalse(content.isEditable)
    }

    @MainActor private func visibleButton(_ identifier: String, in root: UIView) -> UIButton {
        let match = descendants(root).first { view in
            guard view.accessibilityIdentifier == identifier else { return false }
            var current: UIView? = view
            while let item = current {
                if item.isHidden || item.accessibilityElementsHidden { return false }
                current = item.superview
            }
            return true
        }
        XCTAssertNotNil(match, "Missing visible button: " + identifier)
        return match as! UIButton
    }

    @MainActor private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }
}
