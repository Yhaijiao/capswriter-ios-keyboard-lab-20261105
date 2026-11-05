import Foundation

@main
struct PinyinSmoke {
    static func check(_ value: @autoclosure () -> Bool, line: UInt = #line) {
        if !value() { fatalError("Pinyin smoke failed at line \(line)") }
    }
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let lexicon = try JSONDecoder().decode([String: [String]].self, from: data)
        let costsURL = URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent().appendingPathComponent("pinyin-costs.json")
        let costs = try JSONDecoder().decode([String: [String: Double]].self, from: Data(contentsOf: costsURL))
        let engine = PinyinEngine(lexicon: lexicon, costs: costs)
        for input in ["wom", "nihaom", "nihaoma", "woaini", "womendouyouyigejia"] {
            let values = engine.candidates(for: input).map { "\($0.text):\($0.consumed)" }.joined(separator: ", ")
            FileHandle.standardError.write(Data("\(input): \(values)\n".utf8))
        }
        check(engine.candidates(for: "nihao").first?.text == "你好")
        check(engine.candidates(for: "zhongwen").first?.text == "中文")
        check(engine.candidates(for: "ceshi").first?.text == "测试")
        check(engine.candidates(for: "zhongguo").first?.text == "中国")
        let fixture = PinyinEngine(lexicon: ["nihao": ["你好"], "ma": ["吗"], "xing": ["行", "星"]])
        check(fixture.candidates(for: "nihaoma").first == PinyinCandidate(text: "你好吗", consumed: 7))
        check(fixture.candidates(for: "xing").count == 2)
        check(fixture.candidates(for: "xi").first?.consumed == 2)
        check(fixture.candidates(for: "").isEmpty)
        check(engine.candidates(for: "wo").first == PinyinCandidate(text: "我", consumed: 2))
        check(engine.candidates(for: "wom").first == PinyinCandidate(text: "我们", consumed: 3))
        check(engine.candidates(for: "wome").first == PinyinCandidate(text: "我们", consumed: 4))
        check(engine.candidates(for: "women").first == PinyinCandidate(text: "我们", consumed: 5))
        check(engine.candidates(for: "WOM").first?.text == "我们")
        let mixed = PinyinEngine(lexicon: ["wo": ["我"], "women": ["我们"], "zhongguo": ["中国"], "zhong": ["中"]])
        check(mixed.candidates(for: "wom").first?.consumed == 3)
        check(mixed.candidates(for: "zhongg").first == PinyinCandidate(text: "中国", consumed: 6))
        check(mixed.candidates(for: "wog").first == PinyinCandidate(text: "我", consumed: 2))
        check(mixed.candidates(for: "woaini").first?.consumed == 2)
        check(mixed.candidates(for: String(repeating: "a", count: 65)).isEmpty)
        let wom = engine.candidates(for: "wom")
        check(wom.contains { $0.text == "我妈" && $0.consumed == 3 })
        check(wom.contains { $0.text == "我没" && $0.consumed == 3 })
        check(wom.filter { $0.consumed == 3 }.count >= 5)
        check(engine.candidates(for: "nihaom").first == PinyinCandidate(text: "你好吗", consumed: 6))
        check(engine.candidates(for: "nihaoma").first?.text == "你好吗")
        check(engine.candidates(for: "nihaom").contains { $0.text == "你好妈" && $0.consumed == 6 })
        check(engine.candidates(for: "woaini").contains { $0.text == "我爱你" && $0.consumed == 6 })
        let sentence = engine.candidates(for: "womendouyouyigejia")
        check(sentence.contains { $0.text == "我们都有一个家" && $0.consumed == 18 })
        check(sentence.contains { $0.text == "我们" && $0.consumed == 5 })
        check(engine.candidates(for: "wom").count <= 40)
        print("Pinyin smoke: 28 checks passed; bundled keys: \(lexicon.count)")
    }
}

