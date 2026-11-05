import Foundation

struct PinyinCandidate: Equatable {
    let text: String
    let consumed: Int
}

/// Small, offline full-pinyin lookup. No remote requests, user history or learning.
/// Longest known prefix lets a user select phrases one at a time from a sentence.
final class PinyinEngine {
    private let lexicon: [String: [String]]
    private let keys: [String]

    init(lexicon: [String: [String]]) {
        self.lexicon = lexicon
        self.keys = lexicon.keys.sorted { $0.count == $1.count ? $0 < $1 : $0.count < $1.count }
    }

    convenience init() {
        let fallback = ["ni": ["你", "呢"], "hao": ["好", "号"], "nihao": ["你好"],
                        "wo": ["我"], "shi": ["是", "时"], "de": ["的", "得"],
                        "zhongwen": ["中文"], "shuru": ["输入"], "ceshi": ["测试"]]
        guard let url = Bundle.main.url(forResource: "pinyin-lexicon", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            self.init(lexicon: fallback); return
        }
        self.init(lexicon: value)
    }

    func candidates(for raw: String) -> [PinyinCandidate] {
        let buffer = raw.lowercased().replacingOccurrences(of: "ü", with: "v")
        guard !buffer.isEmpty, buffer.count <= 64 else { return [] }
        for count in stride(from: buffer.count, through: 1, by: -1) {
            let prefix = String(buffer.prefix(count))
            if let words = lexicon[prefix], !words.isEmpty {
                return words.prefix(40).map { PinyinCandidate(text: $0, consumed: count) }
            }
        }
        var result: [PinyinCandidate] = []
        var seen = Set<String>()
        for key in keys where key.hasPrefix(buffer) {
            for text in (lexicon[key] ?? []).prefix(2) where !seen.contains(text) {
                result.append(PinyinCandidate(text: text, consumed: buffer.count))
                seen.insert(text)
                if result.count >= 12 { return result }
            }
        }
        return result
    }
}
