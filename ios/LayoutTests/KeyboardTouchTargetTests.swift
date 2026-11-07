import UIKit
import XCTest

final class KeyboardTouchTargetTests: XCTestCase {
    @MainActor func testHorizontalGapAndActions() {
        let row = KeyboardKeyRow(frame: CGRect(x: 0, y: 0, width: 93, height: 44))
        row.axis = .horizontal; row.spacing = 5; row.distribution = .fillEqually
        let left = KeyboardKeyButton(type: .system)
        let right = KeyboardKeyButton(type: .system)
        row.addArrangedSubview(left); row.addArrangedSubview(right); row.layoutIfNeeded()
        var commits = 0
        left.addAction(UIAction { _ in commits += 1 }, for: .primaryActionTriggered)
        XCTAssertTrue(row.hitTest(CGPoint(x: 45, y: 22), with: nil) === left)
        XCTAssertTrue(row.hitTest(CGPoint(x: 48, y: 22), with: nil) === right)
        XCTAssertEqual(commits, 0)
        left.sendActions(for: .touchDown)
        XCTAssertEqual(commits, 0)
        left.sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(commits, 1)
        right.isEnabled = false
        XCTAssertFalse(row.hitTest(CGPoint(x: 48, y: 22), with: nil) === left)
    }

    @MainActor func testVerticalGapAndPageBoundary() {
        let page = UIStackView(frame: CGRect(x: 0, y: 0, width: 93, height: 96))
        page.axis = .vertical; page.spacing = 8; page.distribution = .fillEqually
        let upper = KeyboardKeyRow(); let lower = KeyboardKeyRow()
        let upperKey = KeyboardKeyButton(type: .system)
        let lowerKey = KeyboardKeyButton(type: .system)
        upper.addArrangedSubview(upperKey); lower.addArrangedSubview(lowerKey)
        page.addArrangedSubview(upper); page.addArrangedSubview(lower)
        page.layoutIfNeeded(); upper.layoutIfNeeded(); lower.layoutIfNeeded()
        XCTAssertTrue(page.hitTest(CGPoint(x: 20, y: 47), with: nil) === upperKey)
        XCTAssertTrue(page.hitTest(CGPoint(x: 20, y: 49), with: nil) === lowerKey)
        XCTAssertNil(page.hitTest(CGPoint(x: 20, y: -1), with: nil))
        XCTAssertNil(page.hitTest(CGPoint(x: 20, y: 97), with: nil))
    }

    @MainActor func testLargeSpacerIsNotCaptured() {
        let row = KeyboardKeyRow(frame: CGRect(x: 0, y: 0, width: 118, height: 44))
        row.axis = .horizontal
        let left = KeyboardKeyButton(type: .system)
        let right = KeyboardKeyButton(type: .system)
        let spacer = UIView()
        row.addArrangedSubview(left); row.addArrangedSubview(spacer); row.addArrangedSubview(right)
        NSLayoutConstraint.activate([left.widthAnchor.constraint(equalToConstant: 44), spacer.widthAnchor.constraint(equalToConstant: 30), right.widthAnchor.constraint(equalToConstant: 44)])
        row.layoutIfNeeded()
        XCTAssertTrue(row.hitTest(CGPoint(x: 48, y: 22), with: nil) === left)
        XCTAssertFalse(row.hitTest(CGPoint(x: 59, y: 22), with: nil) is KeyboardKeyButton)
        XCTAssertTrue(row.hitTest(CGPoint(x: 70, y: 22), with: nil) === right)
    }

    @MainActor func testProductionPagerCanCancelKeyTouches() {
        let controller = KeyboardViewController()
        controller.loadViewIfNeeded()
        func descendants(_ view: UIView) -> [UIView] {
            view.subviews.flatMap { [$0] + descendants($0) }
        }
        let pager = descendants(controller.view).first { $0.accessibilityIdentifier == "keyboard-pages" } as? UIScrollView
        XCTAssertNotNil(pager)
        XCTAssertEqual(pager?.canCancelContentTouches, true)
        XCTAssertEqual(pager?.delaysContentTouches, false)
        XCTAssertEqual(pager?.touchesShouldCancel(in: KeyboardKeyButton(type: .system)), true)
    }
}
