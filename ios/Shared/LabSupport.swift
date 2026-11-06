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

struct HotwordFile: Decodable {
    var id: String
    var name: String
    var text: String
    var revision: String
    var writable: Bool
}

struct BridgeReply: Decodable {
    var hotword_files: [HotwordFile]?
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
        case .invalidAddress: return "请输入有效服务地址：局域网可用 HTTP，公网必须使用 HTTPS。"
        case .invalidToken: return "请输入识别服务的有效配对码"
        case .server(let code): return "识别服务返回 HTTP \(code)，请检查配对码和服务状态"
        case .invalidReply: return "识别服务的响应格式不正确"
        case .message(let text): return text
        }
    }
}

final class BridgeRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let original = task.originalRequest, let source = original.url, let destination = request.url,
              BridgeEndpoint.sameOrigin(source, destination) else { completionHandler(nil); return }
        var accepted = request
        if let bearer = original.value(forHTTPHeaderField: "Authorization") {
            accepted.setValue(bearer, forHTTPHeaderField: "Authorization")
        }
        completionHandler(accepted)
    }
}

final class BridgeClient {
    private static let redirectGuard = BridgeRedirectGuard()
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration, delegate: redirectGuard, delegateQueue: nil)
    }()
    static func request(address: String, token: String, text: String? = nil,
                        completion: @escaping (Result<BridgeReply, Error>) -> Void) {
        call(address: address, token: token, path: text == nil ? "/v1/status" : "/v1/correct",
             value: text.map { ["text": $0] }, completion: completion)
    }

    @discardableResult
    static func call(address: String, token: String, path: String, value: [String: Any]? = nil,
                     jobID: String? = nil, timeout: TimeInterval = 10,
                     completion: @escaping (Result<BridgeReply, Error>) -> Void) -> URLSessionDataTask? {
        guard let endpoint = BridgeEndpoint(address: address), let url = endpoint.requestURL(path: path, jobID: jobID) else {
            completion(.failure(BridgeError.invalidAddress)); return nil
        }
        guard isValidToken(token) else {
            completion(.failure(BridgeError.invalidToken)); return nil
        }
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
        BridgeEndpoint.isLocalHost(host)
    }

    static func isValidToken(_ token: String) -> Bool {
        !token.isEmpty && token.count <= 4096
            && !token.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) })
    }
}
