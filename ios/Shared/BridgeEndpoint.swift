import Foundation

/// A paired server origin. Public servers require ordinary, system-validated
/// HTTPS; plaintext HTTP remains limited to the existing local bridge scope.
struct BridgeEndpoint {
    let baseURL: URL
    let scheme: String
    let host: String
    let port: Int

    var normalizedAddress: String { baseURL.absoluteString }

    init?(address: String) {
        let raw = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty,
              !raw.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              !raw.contains("\\"),
              var parts = URLComponents(string: raw),
              let parsedScheme = parts.scheme?.lowercased(), ["http", "https"].contains(parsedScheme),
              raw.lowercased().hasPrefix(parsedScheme + "://"),
              parts.user == nil, parts.password == nil else { return nil }

        let authority = String(raw.dropFirst(parsedScheme.count + 3).prefix { $0 != "/" && $0 != "?" && $0 != "#" })
        guard !authority.isEmpty, !authority.contains("@"), !authority.contains("%") else { return nil }
        let rawHost: String
        let rawPort: String?
        if authority.hasPrefix("[") {
            guard let closing = authority.firstIndex(of: "]") else { return nil }
            rawHost = String(authority[authority.index(after: authority.startIndex)..<closing])
            let suffix = String(authority[authority.index(after: closing)...])
            guard suffix.isEmpty || suffix.hasPrefix(":") else { return nil }
            rawPort = suffix.isEmpty ? nil : String(suffix.dropFirst())
            guard Self.validIPv6(rawHost) else { return nil }
        } else {
            let fields = authority.split(separator: ":", omittingEmptySubsequences: false)
            guard fields.count <= 2 else { return nil }
            rawHost = String(fields[0]); rawPort = fields.count == 2 ? String(fields[1]) : nil
            guard !rawHost.isEmpty, !rawHost.contains("["), !rawHost.contains("]") else { return nil }
            // Reject alternative/octal/integer IPv4 notation before Foundation
            // can canonicalize it into a different destination.
            if rawHost.allSatisfy({ "0123456789.".contains($0) }), Self.ipv4(rawHost) == nil { return nil }
        }
        let explicitPort: Int?
        if let value = rawPort {
            guard !value.isEmpty, value.allSatisfy({ $0 >= "0" && $0 <= "9" }),
                  let number = Int(value), (1...65535).contains(number) else { return nil }
            explicitPort = number
        } else { explicitPort = nil }

        guard let parsedURL = parts.url, let parsedHost = parsedURL.host, !parsedHost.isEmpty else { return nil }
        let normalizedHost: String
        if rawHost.contains(":") {
            normalizedHost = rawHost.lowercased()
            parts.host = "[" + normalizedHost + "]"
        } else {
            normalizedHost = parsedHost.lowercased()
            guard Self.validDNSOrIPv4(normalizedHost) else { return nil }
            parts.host = normalizedHost
        }
        guard parsedScheme == "https" || Self.isLocalHost(normalizedHost) else { return nil }
        parts.scheme = parsedScheme; parts.port = explicitPort
        parts.path = ""; parts.query = nil; parts.fragment = nil
        guard let baseURL = parts.url else { return nil }
        self.baseURL = baseURL; scheme = parsedScheme; host = normalizedHost
        port = explicitPort ?? (parsedScheme == "https" ? 443 : 80)
    }

    func requestURL(path: String, jobID: String? = nil) -> URL? {
        guard path.hasPrefix("/"), !path.hasPrefix("//"),
              var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        parts.path = path; parts.query = nil; parts.fragment = nil
        if let jobID = jobID { parts.queryItems = [URLQueryItem(name: "id", value: jobID)] }
        return parts.url
    }

    static func sameOrigin(_ first: URL, _ second: URL) -> Bool {
        guard let lhs = BridgeEndpoint(address: first.absoluteString),
              let rhs = BridgeEndpoint(address: second.absoluteString) else { return false }
        return lhs.scheme == rhs.scheme && lhs.host == rhs.host && lhs.port == rhs.port
    }

    static func isLocalHost(_ host: String) -> Bool {
        let value = host.lowercased()
        guard validDNSOrIPv4(value) else { return false }
        if value == "localhost" || value == "127.0.0.1" || value.hasSuffix(".local") { return true }
        guard let numbers = ipv4(value) else { return false }
        return numbers[0] == 10 || (numbers[0] == 192 && numbers[1] == 168)
            || (numbers[0] == 172 && (16...31).contains(numbers[1]))
    }

    private static func ipv4(_ host: String) -> [Int]? {
        let groups = host.split(separator: ".", omittingEmptySubsequences: false)
        guard groups.count == 4 else { return nil }
        var values: [Int] = []
        for group in groups {
            guard !group.isEmpty, group.count <= 3,
                  group.allSatisfy({ $0 >= "0" && $0 <= "9" }),
                  !(group.count > 1 && group.first == "0"),
                  let value = Int(group), (0...255).contains(value) else { return nil }
            values.append(value)
        }
        return values
    }

    private static func validDNSOrIPv4(_ host: String) -> Bool {
        guard !host.isEmpty else { return false }
        if host.allSatisfy({ "0123456789.".contains($0) }) { return ipv4(host) != nil }
        let value = host.hasSuffix(".") ? String(host.dropLast()) : host
        guard !value.isEmpty, value.utf8.count <= 253 else { return false }
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-"
                && label.allSatisfy { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") || $0 == "-" }
        }
    }

    private static func validIPv6(_ host: String) -> Bool {
        let sections = host.components(separatedBy: "::")
        guard sections.count <= 2, host.contains(":") else { return false }
        var groups: [String] = []
        for section in sections where !section.isEmpty {
            let values = section.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard !values.contains(where: { $0.isEmpty }) else { return false }
            groups += values
        }
        var count = 0
        for (index, group) in groups.enumerated() {
            if group.contains(".") {
                guard index == groups.count - 1, host.hasSuffix(group), ipv4(group) != nil else { return false }
                count += 2
            } else {
                guard (1...4).contains(group.count), group.allSatisfy({ "0123456789abcdefABCDEF".contains($0) }) else { return false }
                count += 1
            }
        }
        return sections.count == 2 ? count < 8 : count == 8
    }
}
