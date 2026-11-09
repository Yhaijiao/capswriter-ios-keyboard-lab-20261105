import XCTest

final class VoiceInsertionTests: XCTestCase {
    func testAutoNewlineAddsOneSeparator() {
        XCTAssertEqual(AutoNewlineMode.off.apply(to: "你好"), "你好")
        XCTAssertEqual(AutoNewlineMode.soft.apply(to: "你好"), "你好\u{2028}")
        XCTAssertEqual(AutoNewlineMode.hard.apply(to: "你好"), "你好\n")
        XCTAssertEqual(AutoNewlineMode.soft.apply(to: "你好\n"), "你好\n", "No second line break")
        XCTAssertEqual(AutoNewlineMode.soft.apply(to: ""), "")
    }

    func testAutoNewlineCyclesThroughAllModes() {
        XCTAssertEqual(AutoNewlineMode.off.next, .soft)
        XCTAssertEqual(AutoNewlineMode.soft.next, .hard)
        XCTAssertEqual(AutoNewlineMode.hard.next, .off)
    }

    func testUndoOnlyRemovesTheLastInsertAtTheCursor() {
        let field = UUID()
        var undo = VoiceUndoRecord()
        undo.record("今天天气不错。\u{2028}", documentID: field)
        XCTAssertEqual(undo.deletions(documentID: field, textBeforeCursor: "前面的字今天天气不错。\u{2028}"), 8)
        XCTAssertEqual(undo.deletions(documentID: field, textBeforeCursor: "天气不错。\u{2028}"), 8, "Host shows only a window")
        XCTAssertEqual(undo.deletions(documentID: field, textBeforeCursor: ""), 8, "Host shows only the new empty line")
        XCTAssertNil(undo.deletions(documentID: field, textBeforeCursor: "今天天气不错。\u{2028}又打了字"))
        XCTAssertNil(undo.deletions(documentID: UUID(), textBeforeCursor: "今天天气不错。\u{2028}"))
        undo.clear()
        XCTAssertFalse(undo.isAvailable)
        XCTAssertNil(undo.deletions(documentID: field, textBeforeCursor: "今天天气不错。\u{2028}"))
    }

    func testUndoWithoutNewlineNeedsMatchingText() {
        let field = UUID()
        var undo = VoiceUndoRecord()
        undo.record("你好", documentID: field)
        XCTAssertEqual(undo.deletions(documentID: field, textBeforeCursor: "你好"), 2)
        XCTAssertNil(undo.deletions(documentID: field, textBeforeCursor: ""))
        XCTAssertNil(undo.deletions(documentID: field, textBeforeCursor: nil))
    }
}
