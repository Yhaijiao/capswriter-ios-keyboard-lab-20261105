import Foundation

@main
struct PinyinSmoke {
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let lexicon = try JSONDecoder().decode([String: [String]].self, from: data)
        let engine = PinyinEngine(lexicon: lexicon)
        precondition(engine.candidates(for: "nihao").first?.text == "你好")
        precondition(engine.candidates(for: "zhongwen").first?.text == "中文")
        precondition(engine.candidates(for: "ceshi").first?.text == "测试")
        precondition(engine.candidates(for: "zhongguo").first?.text == "中国")
        let fixture = PinyinEngine(lexicon: ["nihao": ["你好"], "ma": ["吗"], "xing": ["行", "星"]])
        precondition(fixture.candidates(for: "nihaoma").first == PinyinCandidate(text: "你好", consumed: 5))
        precondition(fixture.candidates(for: "xing").count == 2)
        precondition(fixture.candidates(for: "xi").first?.consumed == 2)
        precondition(fixture.candidates(for: "").isEmpty)
        print("Pinyin smoke: 8 checks passed; bundled keys: \(lexicon.count)")
    }
}
