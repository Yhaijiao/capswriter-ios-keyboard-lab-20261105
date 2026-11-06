import Foundation

@main
struct EndpointSmoke {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, line: UInt = #line) {
        count += 1
        if !condition() { fatalError("Endpoint check failed at line \(line)") }
    }
    static func main() {
        for address in ["http://192.168.1.20:8765", "http://10.0.0.1", "http://172.16.0.1",
                        "http://172.31.255.255", "http://localhost:8765", "HTTP://LOCALHOST", "http://computer.local"] {
            check(BridgeEndpoint(address: address) != nil)
        }
        for address in ["https://speech.example.com", "https://203.0.113.10", "https://speech.example.com:8443",
                        "https://[2001:db8::1]:443", "https://[::1]", "https://a-b.example.com"] {
            check(BridgeEndpoint(address: address) != nil)
        }
        for address in ["", "example.com", "http://", "https:///path", "ftp://example.com", "file:///tmp/file",
                        "http://example.com", "http://203.0.113.10", "http://172.15.0.1", "http://172.32.0.1",
                        "https://user@example.com", "https://user:password@example.com", "https://@example.com",
                        "https://example.com:0", "https://example.com:65536", "https://example.com:-1",
                        "https://example.com:", "https://example.com:abc", "https://example.com:999999999999999999999999",
                        "https://example..com", "https://bad_host.example", "https://-bad.example", "https://bad-.example",
                        "https://999.1.2.3", "http://010.1.2.3", "https://example.com\\other", "https://exa mple.com",
                        "https://[1:2:3]", "https://[1::2::3]", "https://[fe80::1%25en0]"] {
            check(BridgeEndpoint(address: address) == nil)
        }
        let endpoint = BridgeEndpoint(address: " \nHTTPS://SPEECH.EXAMPLE.COM:443/old/path?discard=value#fragment\n ")!
        check(endpoint.scheme == "https")
        check(endpoint.host == "speech.example.com")
        check(endpoint.port == 443)
        check(URLComponents(url: endpoint.baseURL, resolvingAgainstBaseURL: false)?.query == nil)
        check(endpoint.baseURL.fragment == nil)
        let request = endpoint.requestURL(path: "/v1/voice/result", jobID: "fixture&value=中文")!
        check(request.path == "/v1/voice/result")
        let query = URLComponents(url: request, resolvingAgainstBaseURL: false)?.queryItems
        check(query?.count == 1 && query?.first?.name == "id" && query?.first?.value == "fixture&value=中文")
        check(endpoint.requestURL(path: "https://other.example") == nil)
        check(endpoint.requestURL(path: "//other.example/path") == nil)
        for (first, second, allowed) in [
            ("https://speech.example.com/a", "https://SPEECH.EXAMPLE.COM:443/b", true),
            ("http://10.0.0.1/a", "http://10.0.0.1:80/b", true),
            ("https://203.0.113.10/a", "https://203.0.113.10/b", true),
            ("https://speech.example.com/a", "https://other.example.com/b", false),
            ("https://speech.example.com/a", "https://speech.example.com:8443/b", false),
            ("https://speech.example.com/a", "http://speech.example.com/b", false),
            ("http://10.0.0.1/a", "https://10.0.0.1/b", false),
            ("https://speech.example.com/a", "https://user@speech.example.com/b", false)
        ] {
            check(BridgeEndpoint.sameOrigin(URL(string: first)!, URL(string: second)!) == allowed)
        }
        print("Endpoint validation: \(count) checks passed")
    }
}
