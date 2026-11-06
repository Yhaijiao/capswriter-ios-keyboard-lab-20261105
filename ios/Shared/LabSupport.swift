import UIKit

enum Lab {
    static let version = "0.4.3"
    static let maxRecordingSeconds = 300
    static let chineseSample = "这是 CapsWriter 手机键盘测试。"
    static let englishSample = "CapsWriter keyboard test. "
    static let background = UIColor(red: 0.075, green: 0.075, blue: 0.085, alpha: 1)
    static let surface = UIColor(white: 0.17, alpha: 1)
    static let muted = UIColor(white: 0.67, alpha: 1)

    static func button(_ title: String, symbol: String? = nil, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseBackgroundColor = surface
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 15, bottom: 12, trailing: 15)
        if let symbol = symbol { config.image = UIImage(systemName: symbol); config.imagePadding = 8 }
        let button = UIButton(configuration: config, primaryAction: UIAction { _ in action() })
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        return button
    }

    static func label(_ text: String, size: CGFloat = 16, color: UIColor = .white) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = color
        label.font = .systemFont(ofSize: size)
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }
}

struct BridgeReply: Decodable {
    var version: String?
    var source_version: String?
    var engine: String?
    var terms: Int?
    var text: String?
    var mode: String?
    var id: String?
    var state: String?
    var error: String?
    var voice_enabled: Bool?
    var agent_ready: Bool?
    var asr_ready: Bool?
    var max_seconds: Int?
}

enum BridgeError: LocalizedError {
    case invalidAddress, invalidToken, server(Int), invalidReply, message(String)
    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "请输入局域网地址，例如 http://192.168.1.20:8765"
        case .invalidToken: return "请输入电脑端显示的配对码"
        case .server(let code): return "电脑服务返回 HTTP \(code)，请检查配对码和服务状态"
        case .invalidReply: return "电脑服务的响应格式不正确"
        case .message(let text): return text
        }
    }
}

final class BridgeClient {
    private static let session = URLSession(configuration: .ephemeral)
    static func request(address: String, token: String, text: String? = nil,
                        completion: @escaping (Result<BridgeReply, Error>) -> Void) {
        call(address: address, token: token, path: text == nil ? "/v1/status" : "/v1/correct",
             value: text.map { ["text": $0] }, completion: completion)
    }

    @discardableResult
    static func call(address: String, token: String, path: String, value: [String: Any]? = nil,
                     jobID: String? = nil, timeout: TimeInterval = 10,
                     completion: @escaping (Result<BridgeReply, Error>) -> Void) -> URLSessionDataTask? {
        // This experimental bridge is deliberately LAN-only; no arbitrary internet destinations.
        guard let parts = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "http", parts.user == nil, parts.password == nil,
              let host = parts.host, isLocal(host),
              var urlParts = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            completion(.failure(BridgeError.invalidAddress)); return nil
        }
        guard !token.isEmpty else { completion(.failure(BridgeError.invalidToken)); return nil }
        urlParts.path = path
        urlParts.query = nil; urlParts.fragment = nil
        if let jobID = jobID { urlParts.queryItems = [URLQueryItem(name: "id", value: jobID)] }
        guard let url = urlParts.url else { completion(.failure(BridgeError.invalidAddress)); return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let value = value {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: value)
        }
        let task = session.dataTask(with: request) { data, response, error in
            let result: Result<BridgeReply, Error>
            if let error = error { result = .failure(error) }
            else if let response = response as? HTTPURLResponse, response.statusCode != 200 {
                if let data = data, let reply = try? JSONDecoder().decode(BridgeReply.self, from: data), let message = reply.error {
                    result = .failure(BridgeError.message(message))
                } else { result = .failure(BridgeError.server(response.statusCode)) }
            } else if let data = data, let reply = try? JSONDecoder().decode(BridgeReply.self, from: data) {
                result = .success(reply)
            } else { result = .failure(BridgeError.invalidReply) }
            DispatchQueue.main.async { completion(result) }
        }
        task.resume(); return task
    }

    static func isLocal(_ host: String) -> Bool {
        if host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local") { return true }
        let pieces = host.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 4, pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0 >= "0" && $0 <= "9" }) }) else { return false }
        let octets = pieces.compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
        return octets[0] == 10 || (octets[0] == 192 && octets[1] == 168)
            || (octets[0] == 172 && (16...31).contains(octets[1]))
    }
}
