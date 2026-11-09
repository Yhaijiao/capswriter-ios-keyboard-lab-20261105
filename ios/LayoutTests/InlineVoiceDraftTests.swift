import XCTest

final class InlineVoiceDraftTests: XCTestCase {
    private let document = UUID()

    func testDraftIsMarkedOnceAndGrows() {
        var draft = InlineVoiceDraft()
        XCTAssertEqual(draft.update(draft: "今天", documentID: document, expectedDocument: document), .mark("今天"))
        XCTAssertEqual(draft.update(draft: "今天", documentID: document, expectedDocument: document), .none)
        XCTAssertEqual(draft.update(draft: "今天天气", documentID: document, expectedDocument: document), .mark("今天天气"))
        XCTAssertTrue(draft.isShown)
    }

    func testEmptyDraftDoesNotTouchTheField() {
        var draft = InlineVoiceDraft()
        XCTAssertEqual(draft.update(draft: "", documentID: document, expectedDocument: document), .none)
        XCTAssertEqual(draft.clear(), .none)
    }

    func testClearOnlyWhenSomethingIsMarked() {
        var draft = InlineVoiceDraft()
        _ = draft.update(draft: "你好", documentID: document, expectedDocument: document)
        XCTAssertEqual(draft.clear(), .clear)
        XCTAssertEqual(draft.clear(), .none)
        XCTAssertFalse(draft.isShown)
        // After a key press clears it, the next draft is marked again.
        XCTAssertEqual(draft.update(draft: "你好", documentID: document, expectedDocument: document), .mark("你好"))
    }

    func testNeverMarksInAnotherDocument() {
        var draft = InlineVoiceDraft()
        XCTAssertEqual(draft.update(draft: "你好", documentID: UUID(), expectedDocument: document), .none)
        XCTAssertEqual(draft.update(draft: "你好", documentID: document, expectedDocument: nil), .none)
        _ = draft.update(draft: "你好", documentID: document, expectedDocument: document)
        XCTAssertEqual(draft.update(draft: "你好吗", documentID: UUID(), expectedDocument: document), .clear)
        XCTAssertFalse(draft.isShown)
    }

    func testPlacementDefaultsToInlineAndToggles() {
        let defaults = UserDefaults(suiteName: "InlineVoiceDraftTests")!
        defaults.removePersistentDomain(forName: "InlineVoiceDraftTests")
        XCTAssertEqual(VoiceDraftPlacement.load(defaults), .inline)
        VoiceDraftPlacement.inline.next.save(defaults)
        XCTAssertEqual(VoiceDraftPlacement.load(defaults), .hint)
        XCTAssertEqual(VoiceDraftPlacement.hint.next, .inline)
    }
}
