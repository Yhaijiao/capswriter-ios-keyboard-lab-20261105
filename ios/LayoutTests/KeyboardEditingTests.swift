import XCTest

final class KeyboardEditingTests: XCTestCase {
    func testShiftSingleTapIsOneShot() {
        let once = ShiftState.off.tapped(sincePrevious: 10)
        XCTAssertEqual(once, .once)
        XCTAssertEqual(once.afterCharacter, .off, "One capital letter, then back to lowercase")
        XCTAssertEqual(once.tapped(sincePrevious: 2), .off, "A slow second tap turns shift off")
    }

    func testShiftDoubleTapLocks() {
        let locked = ShiftState.off.tapped(sincePrevious: 10).tapped(sincePrevious: 0.2)
        XCTAssertEqual(locked, .locked)
        XCTAssertEqual(locked.afterCharacter, .locked, "Caps lock survives typing")
        XCTAssertEqual(locked.tapped(sincePrevious: 0.1), .off)
        XCTAssertTrue(locked.isOn)
        XCTAssertFalse(ShiftState.off.isOn)
    }

    func testLineDeletionStopsAtThePreviousLineBreak() {
        XCTAssertEqual(String(LineDeletion.suffix(before: "第一行\n第二行")), "第二行")
        XCTAssertEqual(String(LineDeletion.suffix(before: "one\u{2028}two")), "two", "Soft line breaks count")
        XCTAssertEqual(String(LineDeletion.suffix(before: "only line")), "only line")
        XCTAssertEqual(String(LineDeletion.suffix(before: "")), "")
    }

    func testLineDeletionAfterALineBreakRemovesThatLine() {
        XCTAssertEqual(String(LineDeletion.suffix(before: "第一行\n第二行\n")), "第二行\n")
        XCTAssertEqual(String(LineDeletion.suffix(before: "a\n\n")), "\n", "An empty line is one step")
        XCTAssertEqual(String(LineDeletion.suffix(before: "\n")), "\n")
        XCTAssertEqual(LineDeletion.suffix(before: "x\n👨‍👩‍👧y").count, 2, "Counts whole characters")
    }
}
