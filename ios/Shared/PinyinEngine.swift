import Foundation

struct PinyinCandidate: Equatable {
    let text: String
    let consumed: Int
}

/// Offline phrase decoding with full spelling, initials and unfinished syllables.
final class PinyinEngine {
    private struct Choice { let text: String; let score: Double }
    private struct Word { let text: String; let cost: Double; let rank: Int }
    private final class Node {
        var children: [String: Node] = [:]
        var words: [Word] = []
    }
    private struct Visit: Hashable { let node: ObjectIdentifier; let offset: Int }
    private let root = Node()
    private let beamLimit = 16

    init(lexicon: [String: [String]], costs: [String: [Double]] = [:], syllables: [String: [String]] = [:]) {
        let patterns = syllables.isEmpty ? lexicon : syllables
        for (pattern, words) in patterns {
            let parts = pattern.split(separator: "'").map(String.init)
            guard !parts.isEmpty else { continue }
            let spelling = parts.joined()
            var node = root
            for part in parts {
                if node.children[part] == nil { node.children[part] = Node() }
                node = node.children[part]!
            }
            for text in words {
                let rank = lexicon[spelling]?.firstIndex(of: text) ?? 0
                let cost = costs[spelling].flatMap { $0.indices.contains(rank) ? $0[rank] : nil }
                    ?? (1 + Double(rank) * 0.18)
                node.words.append(Word(text: text, cost: cost, rank: rank))
            }
        }
    }

    convenience init() {
        let fallback = ["ni": ["你", "呢"], "hao": ["好", "号"], "nihao": ["你好"],
                        "wo": ["我"], "women": ["我们"], "ma": ["吗", "妈", "嘛"],
                        "me": ["么", "没"], "mai": ["买", "卖"], "men": ["们", "门"],
                        "shi": ["是", "时"], "de": ["的", "得"],
                        "zhongwen": ["中文"], "shuru": ["输入"], "ceshi": ["测试"]]
        func resource(_ name: String) -> [String: [String]]? {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode([String: [String]].self, from: data)
        }
        let lexicon = resource("pinyin-lexicon") ?? fallback
        var costs: [String: [Double]] = [:]
        if let url = Bundle.main.url(forResource: "pinyin-costs", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: [Double]].self, from: data) { costs = decoded }
        self.init(lexicon: lexicon, costs: costs, syllables: resource("pinyin-syllables") ?? [:])
    }

    func candidates(for raw: String) -> [PinyinCandidate] {
        let buffer = raw.lowercased().replacingOccurrences(of: "ü", with: "v")
        guard !buffer.isEmpty, buffer.count <= 64,
              buffer.allSatisfy({ $0 >= "a" && $0 <= "z" }) else { return [] }
        let letters = Array(buffer)
        let consonantsOnly = buffer.allSatisfy { !"aeiouv".contains($0) }
        var paths = Array(repeating: [Choice](), count: letters.count + 1)
        paths[0] = [Choice(text: "", score: 0)]
        var prefixes: [Int: [Choice]] = [:]
        for start in 0..<letters.count {
            paths[start] = ranked(paths[start], limit: beamLimit)
            guard !paths[start].isEmpty else { continue }
            let matches = matching(letters, from: start, consonantsOnly: consonantsOnly)
            if start == 0 { prefixes = matches }
            for (end, options) in matches {
                for path in paths[start] {
                    for option in options {
                        paths[end].append(Choice(text: path.text + option.text, score: path.score + option.score))
                    }
                }
                paths[end] = ranked(paths[end], limit: beamLimit * 2)
            }
        }
        var result = ranked(paths[letters.count], limit: 32).map { PinyinCandidate(text: $0.text, consumed: letters.count) }
        // Selecting a mixed prefix leaves exactly the unselected keystrokes.
        for end in prefixes.keys.sorted(by: >) where end < letters.count {
            for choice in ranked(prefixes[end] ?? [], limit: 8) {
                if !result.contains(where: { $0.text == choice.text }) {
                    result.append(PinyinCandidate(text: choice.text, consumed: end))
                }
                if result.count >= 40 { return result }
            }
        }
        return result
    }

    private func matching(_ input: [Character], from start: Int, consonantsOnly: Bool) -> [Int: [Choice]] {
        var found: [Int: [Choice]] = [:]
        var visited: [Visit: Double] = [:]
        func walk(_ node: Node, _ offset: Int, _ penalty: Double) {
            let visit = Visit(node: ObjectIdentifier(node), offset: offset)
            if let best = visited[visit], best <= penalty { return }
            visited[visit] = penalty
            if offset > start {
                for word in node.words.prefix(40) {
                    let exact = start == 0 && offset == input.count && penalty == 0 && !consonantsOnly
                    let score = exact ? Double(word.rank) * 0.12 : word.cost + penalty
                    found[offset, default: []].append(Choice(text: word.text, score: score))
                }
            }
            guard offset < input.count else { return }
            for (syllable, child) in node.children where syllable.first == input[offset] {
                let chars = Array(syllable), remaining = input.count - offset
                if remaining >= chars.count && Array(input[offset..<(offset + chars.count)]) == chars {
                    walk(child, offset + chars.count, penalty)
                }
                // Initials may occur anywhere, including zh/ch/sh or z/c/s.
                if chars.count > 1 {
                    walk(child, offset + 1, penalty + 1.2 + Double(chars.count - 1) * 0.35)
                    if chars.count > 2 && ["zh", "ch", "sh"].contains(String(chars.prefix(2))),
                       remaining >= 2 && Array(input[offset..<(offset + 2)]) == Array(chars.prefix(2)) {
                        walk(child, offset + 2, penalty + 1.2 + Double(chars.count - 2) * 0.35)
                    }
                }
                if remaining > 1 && remaining < chars.count && Array(input[offset...]) == Array(chars.prefix(remaining)) {
                    walk(child, input.count, penalty + 1 + Double(chars.count - remaining) * 0.7)
                }
            }
        }
        walk(root, start, 0)
        for end in found.keys { found[end] = ranked(found[end] ?? [], limit: 40) }
        return found
    }

    private func ranked(_ choices: [Choice], limit: Int) -> [Choice] {
        var best: [String: Double] = [:]
        for choice in choices { best[choice.text] = min(best[choice.text] ?? .infinity, choice.score) }
        return best.map { Choice(text: $0.key, score: $0.value) }.sorted {
            $0.score == $1.score ? $0.text < $1.text : $0.score < $1.score
        }.prefix(limit).map { $0 }
    }
}
