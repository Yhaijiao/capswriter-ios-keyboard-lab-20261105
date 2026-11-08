import Foundation
import XCTest

final class BridgeEndpointTests: XCTestCase {
    func testLANHTTPAndPublicHTTPS() {
        XCTAssertNotNil(BridgeEndpoint(address: "http://192.168.1.20:8765"))
        XCTAssertNotNil(BridgeEndpoint(address: "http://computer.local"))
        XCTAssertNotNil(BridgeEndpoint(address: "https://203.0.113.10"))
        XCTAssertNotNil(BridgeEndpoint(address: "https://speech.example.com:8443"))
        XCTAssertNil(BridgeEndpoint(address: "http://203.0.113.10"))
        XCTAssertNil(BridgeEndpoint(address: "https://user:password@speech.example.com"))
        XCTAssertNil(BridgeEndpoint(address: "https://speech.example.com:65536"))
    }

    func testBinaryUploadQueryKeepsJobAndMetadata() {
        let endpoint = BridgeEndpoint(address: "https://speech.example.com/unused?secret=discard")!
        let url = endpoint.requestURL(path: "/v1/voice/audio", query: [
            URLQueryItem(name: "id", value: "job"), URLQueryItem(name: "encoding", value: "s16le")])!
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(url.path, "/v1/voice/audio")
        XCTAssertEqual(items.map(\.name), ["id", "encoding"])
        XCTAssertFalse(url.absoluteString.contains("secret"))
    }

    func testOnlyNetworkAndGatewayFailuresAreTransient() {
        XCTAssertTrue(BridgeError.isTransient(URLError(.timedOut)))
        XCTAssertTrue(BridgeError.isTransient(URLError(.networkConnectionLost)))
        XCTAssertTrue(BridgeError.isTransient(BridgeError.server(502)))
        XCTAssertFalse(BridgeError.isTransient(BridgeError.server(401)))
        XCTAssertFalse(BridgeError.isTransient(BridgeError.message("录音任务已过期，请重新开始。")))
        XCTAssertFalse(BridgeError.isTransient(BridgeError.invalidReply))
    }

    func testRequestReplacesAddressPathAndQuery() {
        let endpoint = BridgeEndpoint(address: "HTTPS://SPEECH.EXAMPLE.COM/unused?secret=discard#fragment")!
        let request = endpoint.requestURL(path: "/v1/status")!
        XCTAssertEqual(request.scheme, "https")
        XCTAssertEqual(request.host, "speech.example.com")
        XCTAssertEqual(request.path, "/v1/status")
        XCTAssertNil(request.query)
        XCTAssertNil(request.fragment)
        XCTAssertTrue(BridgeEndpoint.sameOrigin(request, URL(string: "https://speech.example.com:443/other")!))
        XCTAssertFalse(BridgeEndpoint.sameOrigin(request, URL(string: "https://speech.example.com:8443/other")!))
    }

    func testRedirectGuardNeverForwardsBearerAcrossOrigin() {
        let source = URL(string: "https://speech.example.com/v1/status")!
        var original = URLRequest(url: source)
        original.setValue("Bearer fixture-pairing-token", forHTTPHeaderField: "Authorization")
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: original)
        defer { task.cancel(); session.invalidateAndCancel() }
        let response = HTTPURLResponse(url: source, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: nil)!
        let delegate = BridgeRedirectGuard()
        for target in ["https://other.example.com/path", "http://speech.example.com/path", "https://speech.example.com:8443/path"] {
            var completed = false
            delegate.urlSession(session, task: task, willPerformHTTPRedirection: response,
                                newRequest: URLRequest(url: URL(string: target)!)) { redirected in
                completed = true; XCTAssertNil(redirected)
            }
            XCTAssertTrue(completed)
        }
        var accepted: URLRequest?
        delegate.urlSession(session, task: task, willPerformHTTPRedirection: response,
                            newRequest: URLRequest(url: URL(string: "https://speech.example.com:443/next")!)) { accepted = $0 }
        XCTAssertEqual(accepted?.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-pairing-token")
        XCTAssertEqual(accepted?.url?.path, "/next")
    }
}
