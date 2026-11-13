import Foundation

/// Shift on the English page, like the iPhone keyboard: one tap capitalizes
/// the next letter only, a quick second tap locks capitals until tapped again.
enum ShiftState: Equatable {
    case off, once, locked

    static let doubleTapWindow: TimeInterval = 0.4

    /// State after a tap that came `interval` seconds after the previous tap.
    func tapped(sincePrevious interval: TimeInterval) -> ShiftState {
        switch self {
        case .off: return .once
        case .once: return interval < Self.doubleTapWindow ? .locked : .off
        case .locked: return .off
        }
    }
    /// State after one character was typed.
    var afterCharacter: ShiftState { self == .once ? .off : self }
    var isOn: Bool { self != .off }
    var symbolName: String {
        switch self {
        case .off: return "shift"
        case .once: return "shift.fill"
        case .locked: return "capslock.fill"
        }
    }
}

/// What one tap of the "delete line" key removes. Lines are split only by
/// line-break characters ("\n", the soft U+2028 the auto newline adds, ...),
/// never by how the host wraps text on screen.
enum LineDeletion {
    /// The end of `before` (the text before the cursor) to delete: back to,
    /// but not including, the previous line break. When the cursor sits right
    /// after a line break, that break and the line before it go together, so
    /// holding the key removes one whole line per step.
    static func suffix(before: String) -> Substring {
        var start = before.endIndex
        if let last = before.last, last.isNewline { start = before.index(before: start) }
        while start > before.startIndex {
            let previous = before.index(before: start)
            if before[previous].isNewline { break }
            start = previous
        }
        return before[start...]
    }
}
