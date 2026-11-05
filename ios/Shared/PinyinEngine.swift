import Foundation

struct PinyinCandidate: Equatable {
    let text: String
    let consumed: Int
}

/// Bounded offline phrase composition, including an unfinished final syllable.
final class PinyinEngine {
    private let lexicon: [String: [String]]
    private let keys: [String]
    private let longestKey: Int
    private let costs: [String: [Double]]
    private struct Choice { let text: String; let score: Double }
    private let beamLimit = 16

    init(lexicon: [String: [String]], costs: [String: [Double]] = [:]) {
        self.lexicon = lexicon
        self.costs = costs
        self.keys = lexicon.keys.sorted()
        self.longestKey = lexicon.keys.map(\.count).max() ?? 0
    }

    convenience init() {
        let fallback = ["ni": ["你", "呢"], "hao": ["好", "号"], "nihao": ["你好"],
                        "wo": ["我"], "women": ["我们"], "ma": ["吗", "妈", "嘛"],
                        "me": ["么", "没"], "mai": ["买", "卖"], "men": ["们", "门"],
                        "shi": ["是", "时"], "de": ["的", "得"],
                        "zhongwen": ["中文"], "shuru": ["输入"], "ceshi": ["测试"]]
        guard let url = Bundle.main.url(forResource: "pinyin-lexicon", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            self.init(lexicon: fallback); return
        }
        var costs: [String: [Double]] = [:]
        if let url = Bundle.main.url(forResource: "pinyin-costs", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: [Double]].self, from: data) { costs = decoded }
        self.init(lexicon: value, costs: costs)
    }

    func candidates(for raw: String) -> [PinyinCandidate] {
        let buffer = raw.lowercased().replacingOccurrences(of: "ü", with: "v")
        guard !buffer.isEmpty, buffer.count <= 64 else { return [] }
        let letters = Array(buffer)
        var complete: [Choice] = []
        let consonantsOnly = buffer.allSatisfy { !"aeiouv".contains($0) }
        if let words = lexicon[buffer] {
            for (rank, text) in words.prefix(40).enumerated() {
                complete.append(Choice(text: text, score: consonantsOnly ? wordCost(buffer, rank) : Double(rank) * 0.12))
            }
        }
        if lexicon[buffer] == nil || consonantsOnly {
            // Preserve known whole-phrase completions: wom -> 我们 first.
            for key in matchingKeys(buffer).prefix(80) where key != buffer {
                for (rank, text) in (lexicon[key] ?? []).prefix(8).enumerated() {
                    complete.append(Choice(text: text, score: wordCost(key, rank) + 1 + Double(key.count - letters.count) * 0.7))
                }
            }
        }

        // Segment into dictionary phrases. Retain alternative paths rather than
        // committing the first known prefix (nihao + m -> 你好吗 / 你好妈 / …).
        var paths = Array(repeating: [Choice](), count: letters.count + 1)
        paths[0] = [Choice(text: "", score: 0)]
        for start in 0..<letters.count {
            paths[start] = ranked(paths[start], limit: beamLimit)
            guard !paths[start].isEmpty else { continue }
            let last = min(letters.count, start + longestKey)
            if start < last {
                for end in (start + 1)...last {
                    let spelling = String(letters[start..<end])
                    guard let words = lexicon[spelling] else { continue }
                    for path in paths[start] {
                        for (rank, text) in words.prefix(8).enumerated() {
                            paths[end].append(Choice(text: path.text + text, score: path.score + wordCost(spelling, rank)))
                        }
                    }
                    paths[end] = ranked(paths[end], limit: beamLimit)
                }
            }
            // A partial syllable is only allowed at the end; this is not wm
            // initials decoding. Limit it to single-character syllable entries.
            let tail = String(letters[start...])
            if start > 0 && tail.count <= 6 {
                var options: [Choice] = []
                for key in matchingKeys(tail) where key.count <= 6 && key != tail {
                    for (rank, text) in (lexicon[key] ?? []).prefix(8).enumerated() where text.count == 1 {
                        options.append(Choice(text: text, score: wordCost(key, rank) + 1 + Double(key.count - tail.count) * 0.7))
                    }
                }
                let endings = ranked(options, limit: 64)
                for path in paths[start] {
                    for option in endings {
                        complete.append(Choice(text: path.text + option.text, score: path.score + option.score))
                    }
                }
            }
        }
        complete += paths[letters.count]
        var result = ranked(complete, limit: 32).map { PinyinCandidate(text: $0.text, consumed: letters.count) }
        // Also offer shorter words for staged selection in a long composition.
        // Selecting one consumes only its spelling and retains the remaining keys.
        if !result.isEmpty {
            if letters.count > 1 {
                for count in stride(from: letters.count - 1, through: 1, by: -1) {
                    for text in (lexicon[String(letters.prefix(count))] ?? []).prefix(8) {
                        let candidate = PinyinCandidate(text: text, consumed: count)
                        if !result.contains(where: { $0.text == text }) { result.append(candidate) }
                        if result.count == 40 { return result }
                    }
                }
            }
            return result
        }
        guard buffer.count > 1 else { return [] }
        for count in stride(from: buffer.count - 1, through: 1, by: -1) {
            let prefix = String(buffer.prefix(count))
            if let words = lexicon[prefix], !words.isEmpty {
                return words.prefix(40).map { PinyinCandidate(text: $0, consumed: count) }
            }
        }
        return []
    }

    private func ranked(_ choices: [Choice], limit: Int) -> [Choice] {
        var best: [String: Double] = [:]
        for choice in choices { best[choice.text] = min(best[choice.text] ?? .infinity, choice.score) }
        var ordered: [Choice] = []
        for (text, score) in best { ordered.append(Choice(text: text, score: score)) }
        ordered.sort { (left: Choice, right: Choice) -> Bool in
            if left.score == right.score { return left.text < right.text }
            return left.score < right.score
        }
        return Array(ordered.prefix(limit))
    }

    private func wordCost(_ spelling: String, _ rank: Int) -> Double {
        if let values = costs[spelling], values.indices.contains(rank) { return values[rank] }
        return 1 + Double(rank) * 0.18
    }

    private func matchingKeys(_ buffer: String) -> [String] {
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
        return matching
    }
}
