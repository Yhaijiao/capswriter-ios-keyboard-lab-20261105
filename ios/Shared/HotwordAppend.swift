import Foundation

/// Adds a few hotwords typed on the phone to the end of a hotword file
/// without the user having to see or edit the whole file.
enum HotwordAppend {
    struct Result: Equatable {
        var text: String
        var added: [String]
        var skipped: [String]
    }

    /// One word (or "正确词 | 误识别") per line. Blank lines and lines already
    /// in the file are skipped, so inserting twice never duplicates a word.
    static func merge(base: String, draft: String) -> Result {
        let existing = Set(base.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        var added: [String] = [], skipped: [String] = [], seen = existing
        for raw in draft.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if seen.contains(line) { skipped.append(line); continue }
            seen.insert(line); added.append(line)
        }
        guard !added.isEmpty else { return Result(text: base, added: [], skipped: skipped) }
        let separator = base.isEmpty || base.hasSuffix("\n") ? "" : "\n"
        return Result(text: base + separator + added.joined(separator: "\n") + "\n", added: added, skipped: skipped)
    }

    /// Number of hotword entries (non-empty, non-comment lines).
    static func entryCount(_ text: String) -> Int {
        text.components(separatedBy: .newlines).filter {
            let line = $0.trimmingCharacters(in: .whitespaces)
            return !line.isEmpty && !line.hasPrefix("#")
        }.count
    }
}
