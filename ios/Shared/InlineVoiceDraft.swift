import Foundation

/// Where the live voice draft is shown while recording.
enum VoiceDraftPlacement: String {
    /// In the text field itself as iOS marked text (underlined, like pinyin
    /// composition), replaced by the accurate result after stop.
    case inline
    /// Only in the keyboard's hint line; the text field stays untouched.
    case hint

    static let defaultsKey = "voice.draftPlacement"
    static func load(_ defaults: UserDefaults = .standard) -> VoiceDraftPlacement {
        defaults.string(forKey: defaultsKey).flatMap(VoiceDraftPlacement.init(rawValue:)) ?? .inline
    }
    func save(_ defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.defaultsKey) }
    var next: VoiceDraftPlacement { self == .inline ? .hint : .inline }
    var hint: String {
        self == .inline ? "实时草稿显示在输入框（点此行切换）" : "实时草稿只显示在这一行（点此行切换）"
    }
}

/// Tracks the draft currently placed in the host as marked text, so it is
/// always cleared before anything else touches the text field and is never
/// left behind in a different document.
struct InlineVoiceDraft {
    enum Action: Equatable {
        case none
        /// Replace the marked text with this draft (cursor at its end).
        case mark(String)
        /// Remove the marked text without inserting anything.
        case clear
    }

    private(set) var shown = ""
    private var documentID: UUID?

    var isShown: Bool { !shown.isEmpty }

    /// A new draft arrived. `expectedDocument` is the document the recording
    /// started in; a draft never goes into any other one.
    mutating func update(draft: String, documentID current: UUID, expectedDocument: UUID?) -> Action {
        guard let expected = expectedDocument, expected == current else { return clear() }
        if let documentID, documentID != current { return clear() }
        guard !draft.isEmpty, draft != shown else { return .none }
        shown = draft; documentID = current
        return .mark(draft)
    }

    /// Before the final text, a key press, a cancel or leaving the keyboard.
    mutating func clear() -> Action {
        guard isShown else { documentID = nil; return .none }
        shown = ""; documentID = nil
        return .clear
    }
}
