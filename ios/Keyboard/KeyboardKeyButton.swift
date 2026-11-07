import UIKit

final class KeyboardKeyButton: UIButton {
    fileprivate var keyboardHitArea: CGRect?
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        (keyboardHitArea ?? bounds).contains(point)
    }
}

/// Opt-in for physical key rows only. No touchDown action or gesture override.
final class KeyboardKeyRow: UIStackView {
    private let maximumExpansion: CGFloat = 6
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: 0, dy: -4).contains(point)
    }
    override func layoutSubviews() { super.layoutSubviews(); updateHitAreas() }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01, self.point(inside: point, with: event) else { return nil }
        for key in updateHitAreas() where key.point(inside: convert(point, to: key), with: event) { return key }
        return super.hitTest(point, with: event)
    }
    @discardableResult private func updateHitAreas() -> [KeyboardKeyButton] {
        let all = arrangedSubviews.compactMap { $0 as? KeyboardKeyButton }
        for key in all { key.keyboardHitArea = nil }
        let visible = all.filter { !$0.isHidden && $0.alpha > 0.01 }.sorted { $0.frame.minX < $1.frame.minX }
        var active: [KeyboardKeyButton] = []
        for (index, key) in visible.enumerated() {
            guard key.isEnabled && key.isUserInteractionEnabled else { continue }
            let frame = key.convert(key.bounds, to: self)
            let previous = index > 0 ? visible[index - 1].convert(visible[index - 1].bounds, to: self) : nil
            let next = index + 1 < visible.count ? visible[index + 1].convert(visible[index + 1].bounds, to: self) : nil
            let left = max(bounds.minX, max(frame.minX - maximumExpansion, previous.map { ($0.maxX + frame.minX) / 2 } ?? bounds.minX))
            let right = min(bounds.maxX, min(frame.maxX + maximumExpansion, next.map { (frame.maxX + $0.minX) / 2 } ?? bounds.maxX))
            key.keyboardHitArea = convert(CGRect(x: left, y: bounds.minY - 4, width: max(0, right - left), height: bounds.height + 8), to: key)
            active.append(key)
        }
        return active
    }
}
