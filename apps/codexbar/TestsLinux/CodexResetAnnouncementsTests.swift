import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct CodexResetAnnouncementsTests {
    @Test
    func `scheduled and observed resets stay distinct from forecasts`() throws {
        let value = try CodexResetAnnouncements.decode(Data(Self.status.utf8))
        #expect(value.latest?.kind == .reset)
        #expect(value.latest?.isObserved == true)
        #expect(value.scheduled?.kind == .scheduled)
        #expect(value.scheduled?.date == Date(timeIntervalSince1970: 1_792_774_800))
        #expect(value.watch?.text == "A possible reset")
        #expect(value.generatedAt != nil)
    }

    @Test
    func `tokenusage posts remain announcements and use the upstream poll time`() throws {
        let data = Data("""
        {"generatedAt":"2026-10-23T16:00:00Z","lastPolledAt":"2026-10-23T15:00:00Z","resets":[
          {"postId":"older","postedAt":"2026-10-22T04:00:00Z","url":"https://x.com/example/status/1"},
          {"postId":"newer","postedAt":"2026-10-23T04:00:00Z","resetType":"automatic"}
        ]}
        """.utf8)
        let value = try CodexResetAnnouncements.decode(data)
        #expect(value.latest?.id == "newer")
        #expect(value.latest?.kind == .announcement)
        #expect(value.generatedAt == Date(timeIntervalSince1970: 1_792_767_600))
    }

    @Test
    func `an undelivered codexreset event is not shown as a completed reset`() throws {
        let data = Data("""
        {"events":[{"id":"one","kind":"regular","announced_at":"2026-10-23T04:00:00Z",
        "delivered_at":null,"summary":"Reset soon","url":"https://x.com/example/status/1"}],
        "scheduled":{"url":"https://x.com/example/status/2","scheduled_for":null}}
        """.utf8)
        let value = try CodexResetAnnouncements.decode(data)
        #expect(value.latest?.kind == .announcement)
        #expect(value.scheduled?.kind == .scheduled)
        #expect(value.scheduled?.date == nil)
    }

    @Test(arguments: ["{}", "[]", "{\"error\":\"unavailable\"}", "{\"resets\":[{}]}", "<html>error</html>"])
    func `unknown payloads fail without inventing reset data`(json: String) {
        #expect(throws: (any Error).self) { try CodexResetAnnouncements.decode(Data(json.utf8)) }
    }

    @Test(arguments: [
        "http://example.com/api", "file:///tmp/feed", "https://name:password@example.com/api",
        "https://example.com/api?token=secret", "https://example.com/api#secret", "relative/api",
    ])
    func `provider URLs reject credentials and unsupported transports`(address: String) {
        #expect(CodexResetAnnouncements.providerURL(address) == nil)
    }

    @Test
    func `empty history is a valid feed and unsafe source links are omitted`() throws {
        #expect(try CodexResetAnnouncements.decode(Data("{\"resets\":[]}".utf8)).latest == nil)
        let data = Data("{\"resets\":[{\"postId\":\"one\",\"url\":\"javascript:alert(1)\"}]}".utf8)
        #expect(try CodexResetAnnouncements.decode(data).latest?.sourceURL == nil)
    }

    @Test
    func `provider settings survive a JSON round trip`() throws {
        var config = ProviderConfig(id: .codex)
        config.codexResetAnnouncementsEnabled = true
        config.codexResetAnnouncementsProviderURL = "https://tokenusage.dev/api/resets"
        let decoded = try JSONDecoder().decode(
            ProviderConfig.self,
            from: JSONEncoder().encode(config))
        #expect(decoded.codexResetAnnouncementsEnabled)
        #expect(decoded.codexResetAnnouncementsProviderURL == "https://tokenusage.dev/api/resets")
        #expect(!ProviderConfig(id: .codex).codexResetAnnouncementsEnabled)
    }

    @Test
    func `HTTP client ignores the local cache and sends no account headers`() async throws {
        let client = Self.client()
        let value = try await client.fetch(from: #require(URL(string: "https://reset-test.invalid/success")))
        #expect(value.latest == nil)
    }

    @Test
    func `HTTP client respects provider throttling and rejects unexpected bodies`() async throws {
        let client = Self.client()
        await #expect(throws: CodexResetAnnouncementsError.retryLater(3600)) {
            try await client.fetch(from: #require(URL(string: "https://reset-test.invalid/limited")))
        }
        await #expect(throws: CodexResetAnnouncementsError.unsupportedResponse) {
            try await client.fetch(from: #require(URL(string: "https://reset-test.invalid/invalid")))
        }
    }

    private static func client() -> CodexResetAnnouncementsClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ResetAnnouncementsURLProtocol.self]
        return CodexResetAnnouncementsClient(session: URLSession(configuration: config))
    }

    private static let status = """
    {"data":{
      "latest_reset":{"id":"observed-one","reset_type":"regular","announced_at":"2026-10-22T17:00:00Z",
        "text":"Observed","source":{"type":"observed","url":"https://x.com/example/status/1"}},
      "scheduled_reset":{"id":"two","scheduled_for":"2026-10-23T17:00:00.000Z"},
      "active_watch":{"text":"A possible reset","expires_at":"2026-10-24T17:00:00Z"}
    },"meta":{"generated_at":"2026-10-23T15:00:00.000Z"}}
    """
}

private final class ResetAnnouncementsURLProtocol: URLProtocol {
    override static func canInit(with _: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        #expect(self.request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(self.request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(self.request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == nil)
        #expect(self.request.cachePolicy == .reloadIgnoringLocalCacheData)
        guard let url = self.request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: url.path == "/limited" ? 429 : 200,
                  httpVersion: nil,
                  headerFields: ["Retry-After": "3600"])
        else { return }
        self.client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed)
        let body = url.path == "/invalid" ? "<html>Unavailable</html>" : "{\"resets\":[]}"
        self.client?.urlProtocol(
            self,
            didLoad: Data(body.utf8))
        self.client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
