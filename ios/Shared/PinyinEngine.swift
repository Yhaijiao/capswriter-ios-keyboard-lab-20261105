import Foundation

struct PinyinCandidate: Equatable {
    let text: String
    let consumed: Int
}

/// Offline full-pinyin lookup and unfinished-spelling completion.
/// Longest known prefix lets a user select phrases one at a time from a sentence.
final class PinyinEngine {
    private let lexicon: [String: [String]]
    private let keys: [String]

    init(lexicon: [String: [String]]) {
        self.lexicon = lexicon
        self.keys = lexicon.keys.sorted()
    }

    convenience init() {
        let fallback = ["ni": ["你", "呢"], "hao": ["好", "号"], "nihao": ["你好"],
                        "wo": ["我"], "women": ["我们"], "shi": ["是", "时"], "de": ["的", "得"],
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
        // An exact spelling wins (wo -> 我). Otherwise complete the whole buffer
        // before falling back to its shorter prefix (wom -> 我们, not 我 + m).
        if let words = lexicon[buffer], !words.isEmpty {
            return words.prefix(40).map { PinyinCandidate(text: $0, consumed: buffer.count) }
        }
        let completed = completions(for: buffer)
        if !completed.isEmpty { return completed }
        guard buffer.count > 1 else { return [] }
        for count in stride(from: buffer.count - 1, through: 1, by: -1) {
            let prefix = String(buffer.prefix(count))
            if let words = lexicon[prefix], !words.isEmpty {
                return words.prefix(40).map { PinyinCandidate(text: $0, consumed: count) }
            }
        }
        return []
    }

    private func completions(for buffer: String) -> [PinyinCandidate] {
        // Binary search narrows the lexicon to one prefix range per keystroke.
        var low = 0, high = keys.count
        while low < high {
            let middle = (low + high) / 2
            if keys[middle] < buffer { low = middle + 1 } else { high = middle }
        }
        var matching: [String] = []
        while low < keys.count && keys[low].hasPrefix(buffer) {
            matching.append(keys[low]); low += 1
        }
        matching.sort { $0.count == $1.count ? $0 < $1 : $0.count < $1.count }
        var result: [PinyinCandidate] = []
        var seen = Set<String>()
        for key in matching {
            for text in (lexicon[key] ?? []).prefix(2) where !seen.contains(text) {
                result.append(PinyinCandidate(text: text, consumed: buffer.count))
                seen.insert(text)
                if result.count >= 12 { return result }
            }
        }
        return result
    }
}
