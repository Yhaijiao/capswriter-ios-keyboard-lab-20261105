import UIKit
import XCTest

final class KeyboardLayoutTests: XCTestCase {
    @MainActor func testFreshKeyboardConstructionAndAlignedRows() {
        let controller = KeyboardViewController()
        // This exercises the production UIKit code, including all three pages.
        // Activating constraints between unattached keys crashes at this point.
        controller.loadViewIfNeeded()
        let root = controller.view!
        root.overrideUserInterfaceStyle = .dark
        root.frame = CGRect(x: 0, y: 0, width: 430, height: 324)
        root.setNeedsLayout(); root.layoutIfNeeded()
        let views = descendants(root)
        let firstKeys = views.filter { $0.accessibilityIdentifier == "key-q" }
        let returns = views.filter { $0.accessibilityIdentifier == "keyboard-return" }
        XCTAssertEqual(firstKeys.count, 2, "English and pinyin pages must both be constructed")
        XCTAssertEqual(returns.count, 3, "Voice and both text pages must be constructed")
        guard firstKeys.count == 2, returns.count == 3 else { return }
        let firstTop = firstKeys[0].convert(firstKeys[0].bounds, to: root).minY
        XCTAssertGreaterThan(firstKeys[0].bounds.width, 0)
        XCTAssertEqual(firstKeys[1].convert(firstKeys[1].bounds, to: root).minY, firstTop, accuracy: 1)
        let bottom = returns[0].convert(returns[0].bounds, to: root).maxY
        for key in returns {
            XCTAssertEqual(key.bounds.height, 44, accuracy: 1)
            XCTAssertEqual(key.convert(key.bounds, to: root).maxY, bottom, accuracy: 1)
        }
        let image = UIGraphicsImageRenderer(size: root.bounds.size).image { context in
            root.layer.render(in: context.cgContext)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Fresh keyboard layout"; attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }
}
