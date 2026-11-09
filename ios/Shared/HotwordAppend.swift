import Foundation

/// Adds a few hotwords typed on the phone to the end of a hotword file
/// without the user having to see or edit the whole file.
enum HotwordAppend {
    struct Result: Equatable {
        var text: String
        var added: [String]
        var skipped: [String]
        var invalid: [String] = []
    }

    /// What one line looks like in each writable file, shown while typing.
    static func hint(fileID: String) -> String {
        switch fileID {
        case "rule": return "一行一条：错的写法 = 正确写法，点「插入」"
        case "aliases": return "一行一条：正确写法 | 常听错的说法，点「插入」"
        default: return "输入新热词，一行一个，点「插入」"
        }
    }

    /// Puts a typed line into the file's own format, or nil when it can't be.
    /// Rules need "错 = 对" with spaces around "=" (CapsWriter splits on " = ");
    /// aliases need "正确 | 误识别". Full-width marks typed on a Chinese
    /// keyboard are accepted.
    static func normalize(_ raw: String, fileID: String) -> String? {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }
        switch fileID {
        case "rule":
            guard let index = line.firstIndex(where: { $0 == "=" || $0 == "＝" }) else { return nil }
            let wrong = line[..<index].trimmingCharacters(in: .whitespaces)
            let right = line[line.index(after: index)...].trimmingCharacters(in: .whitespaces)
            return wrong.isEmpty || right.isEmpty ? nil : wrong + " = " + right
        case "aliases":
            let parts = line.split(whereSeparator: { $0 == "|" || $0 == "｜" })
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return parts.count >= 2 ? parts.joined(separator: " | ") : nil
        default: return line
        }
    }

    /// One entry per line. Blank lines and lines already in the file are
    /// skipped, so inserting twice never duplicates an entry.
    static func merge(base: String, draft: String, fileID: String = "hot") -> Result {
        let existing = Set(base.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        var added: [String] = [], skipped: [String] = [], invalid: [String] = [], seen = existing
        for raw in draft.components(separatedBy: .newlines) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let line = normalize(trimmed, fileID: fileID) else { invalid.append(trimmed); continue }
            if seen.contains(line) { skipped.append(line); continue }
            seen.insert(line); added.append(line)
        }
        guard !added.isEmpty else { return Result(text: base, added: [], skipped: skipped, invalid: invalid) }
        let separator = base.isEmpty || base.hasSuffix("\n") ? "" : "\n"
        return Result(text: base + separator + added.joined(separator: "\n") + "\n",
                      added: added, skipped: skipped, invalid: invalid)
    }

    /// Number of hotword entries (non-empty, non-comment lines).
    static func entryCount(_ text: String) -> Int {
        text.components(separatedBy: .newlines).filter {
            let line = $0.trimmingCharacters(in: .whitespaces)
            return !line.isEmpty && !line.hasPrefix("#")
        }.count
    }
}
