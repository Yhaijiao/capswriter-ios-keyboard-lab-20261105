import XCTest

final class HotwordAppendTests: XCTestCase {
    func testAppendsNewWordsAtTheEnd() {
        let result = HotwordAppend.merge(base: "# 注释\n张三", draft: " SayKey \n\n李四")
        XCTAssertEqual(result.text, "# 注释\n张三\nSayKey\n李四\n")
        XCTAssertEqual(result.added, ["SayKey", "李四"])
        XCTAssertEqual(result.skipped, [])
    }

    func testSkipsWordsAlreadyInTheFile() {
        let result = HotwordAppend.merge(base: "张三\n", draft: "张三\n王五\n王五")
        XCTAssertEqual(result.text, "张三\n王五\n")
        XCTAssertEqual(result.added, ["王五"])
        XCTAssertEqual(result.skipped, ["张三", "王五"])
    }

    func testNothingToAddKeepsTheFile() {
        let result = HotwordAppend.merge(base: "张三", draft: "  \n张三")
        XCTAssertEqual(result.text, "张三")
        XCTAssertTrue(result.added.isEmpty)
    }

    func testCountsEntriesWithoutComments() {
        XCTAssertEqual(HotwordAppend.entryCount("# a\n\n张三\n李四 | 理事\n"), 2)
    }

    func testRulesAreWrittenInCapsWriterFormat() {
        let result = HotwordAppend.merge(base: "毫安时 = mAh\n", draft: "赛基=SayKey\n 豆包 ＝ Doubao \n没有等号\n毫安时=mAh", fileID: "rule")
        XCTAssertEqual(result.text, "毫安时 = mAh\n赛基 = SayKey\n豆包 = Doubao\n")
        XCTAssertEqual(result.invalid, ["没有等号"])
        XCTAssertEqual(result.skipped, ["毫安时 = mAh"])
    }

    func testAliasesNeedAMisrecognition() {
        let result = HotwordAppend.merge(base: "", draft: "SayKey｜赛奇|赛基\nClaude", fileID: "aliases")
        XCTAssertEqual(result.text, "SayKey | 赛奇 | 赛基\n")
        XCTAssertEqual(result.invalid, ["Claude"])
    }
}
