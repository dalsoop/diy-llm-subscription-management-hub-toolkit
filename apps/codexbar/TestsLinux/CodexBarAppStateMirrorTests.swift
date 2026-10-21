import Foundation
import Testing
@testable import CodexBarCore

/// The agent-readable app state mirror (`~/.swift-app-state/codexbar.json`): envelope, status, sanitizing and
/// the atomic file write the app and `codexbar app-state` share.
struct CodexBarAppStateMirrorTests {
    private static func provider(
        _ id: String,
        error: String? = nil,
        accountError: String? = nil,
        accounts: [CodexBarAppStateMirror.Account] = []) -> CodexBarAppStateMirror.Provider
    {
        CodexBarAppStateMirror.Provider(
            id: id,
            enabled: true,
            source: "opencodex-hub",
            lastRefreshAt: Date(timeIntervalSince1970: 1_792_400_000),
            lastSuccessAt: nil,
            error: error,
            accountError: accountError,
            stale: false,
            windows: [],
            accounts: accounts)
    }

    private static func state(_ providers: [CodexBarAppStateMirror.Provider]) -> CodexBarAppStateMirror.State {
        CodexBarAppStateMirror.State(
            appVersion: "0.77.1",
            appBuild: "17107",
            bundleID: "net.ranode.codexbar",
            gitCommit: "abcdef123",
            multiAccountMenuLayout: "stacked",
            hubRole: "client",
            providers: providers)
    }

    @Test
    func `the envelope uses the fleet slug and leaves lastError out when every provider is fine`() throws {
        let data = try CodexBarAppStateMirror.encode(
            Self.state([Self.provider("codex"), Self.provider("grok")]),
            now: Date(timeIntervalSince1970: 1_792_400_060))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["app"] as? String == "codexbar")
        #expect(object["updatedAt"] as? String == "2026-10-19T08:54:20Z")
        let state = try #require(object["state"] as? [String: Any])
        #expect(state["status"] as? String == "ok")
        #expect(state["lastError"] == nil)
        #expect(state["schemaVersion"] as? Int == 1)
        #expect(state["multiAccountMenuLayout"] as? String == "stacked")
        let providers = try #require(state["providers"] as? [[String: Any]])
        #expect(providers.map { $0["id"] as? String } == ["codex", "grok"])
        #expect(providers[0]["error"] == nil)
        #expect(providers[0]["lastRefreshAt"] as? String == "2026-10-19T08:53:20Z")
    }

    @Test
    func `the first failing provider sets status error and lastError`() {
        let state = Self.state([
            Self.provider("claude"),
            Self.provider("codex", error: "Codex is configured for a custom provider"),
            Self.provider("grok", accountError: "ocx timed out"),
        ])
        #expect(state.status == "error")
        #expect(state.lastError == "codex: Codex is configured for a custom provider")

        let accountsOnly = Self.state([Self.provider("claude", accountError: "ocx timed out")])
        #expect(accountsOnly.lastError == "claude: ocx timed out")
    }

    @Test
    func `errors are one sanitized line without credentials`() throws {
        let raw = """
        Request failed: Authorization: Bearer abc.def-ghi
          token=sk-ant-oat01-SECRETSECRET for user jane.doe@example.com
        key ocx_admin_1234567890 eyJhbGciOiJIUzI1NiJ9.payload 0123456789abcdef0123456789abcdef01
        """
        let text = try #require(CodexBarAppStateMirror.sanitizedError(raw))
        #expect(!text.contains("\n"))
        for secret in ["abc.def-ghi", "SECRETSECRET", "ocx_admin_1234567890", "eyJhbGci", "0123456789abcdef0123"] {
            #expect(!text.contains(secret), "\(secret) leaked: \(text)")
        }
        #expect(text.contains("j***e@example.com"))
        #expect(!text.contains("jane.doe@"))
        #expect(CodexBarAppStateMirror.sanitizedError("  \n ") == nil)
        let long = try #require(CodexBarAppStateMirror.sanitizedError(String(repeating: "word ", count: 200)))
        #expect(long.count == 300)
    }

    @Test
    func `account labels keep masked emails and mask plain ones`() {
        let masked = CodexBarAppStateMirror.Account(label: "pro (a***e@example.com)", active: true, windows: [])
        #expect(masked.label == "pro (a***e@example.com)")
        let plain = CodexBarAppStateMirror.Account(label: "someone@example.com", active: false, windows: [])
        #expect(plain.label == "s***e@example.com")
        let window = CodexBarAppStateMirror.Window(name: "weekly", usedPercent: 57.6666, resetAt: nil)
        #expect(window.usedPercent == 57.7)
    }

    @Test
    func `a tenant state root gets the mirror and the home keeps a copy`() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-app-state-home-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let tenant = ["TENANT_ID": "tenant:personal"]
        #expect(CodexBarAppStateMirror.fileURLs(environment: tenant, homeDirectory: "/Users/me").map(\.path) == [
            "/Users/me/.tenants/personal/.swift-app-state/codexbar.json",
            "/Users/me/.swift-app-state/codexbar.json",
        ])
        #expect(CodexBarAppStateMirror.fileURLs(
            environment: ["SWIFT_APP_STATE_ROOT": "/state/root"],
            homeDirectory: "/Users/me").map(\.path) == [
            "/state/root/.swift-app-state/codexbar.json",
            "/Users/me/.swift-app-state/codexbar.json",
        ])
        #expect(CodexBarAppStateMirror.fileURLs(environment: ["TENANT_ID": "../escape"], homeDirectory: "/Users/me")
            .map(\.path) == ["/Users/me/.swift-app-state/codexbar.json"])

        // The tenant context file the fleet's tenant manager keeps.
        let context = home.appendingPathComponent(".agent-tenant-isolation-manager/current-context.json")
        try FileManager.default.createDirectory(
            at: context.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try #"{"setAt": "2026-09-02T19:46:35Z", "tenantID": "tenant:personal"}"#
            .write(to: context, atomically: true, encoding: .utf8)
        let urls = CodexBarAppStateMirror.fileURLs(environment: [:], homeDirectory: home.path)
        #expect(urls.map(\.path) == [
            home.appendingPathComponent(".tenants/personal/.swift-app-state/codexbar.json").path,
            home.appendingPathComponent(".swift-app-state/codexbar.json").path,
        ])
        #expect(CodexBarAppStateMirror.existingFileURL(environment: [:], homeDirectory: home.path) == nil)
        try CodexBarAppStateMirror.write(Self.state([]), to: urls[1])
        #expect(CodexBarAppStateMirror.existingFileURL(environment: [:], homeDirectory: home.path)?.path
            == urls[1].path)
    }

    @Test
    func `the file goes to the state directory override and reads back`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-app-state-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = [CodexBarAppStateMirror.directoryOverrideKey: root.appendingPathComponent("state").path]
        let url = CodexBarAppStateMirror.fileURL(environment: environment, homeDirectory: "/nonexistent")
        #expect(url.path == root.appendingPathComponent("state/codexbar.json").path)
        #expect(CodexBarAppStateMirror.fileURLs(environment: [:], homeDirectory: "/nonexistent/me").map(\.path)
            == ["/nonexistent/me/.swift-app-state/codexbar.json"])

        let accounts = [
            CodexBarAppStateMirror.Account(
                label: "pro (a***e@example.com)",
                active: true,
                windows: [.init(name: "weekly", usedPercent: 58, resetAt: Date(timeIntervalSince1970: 1_792_889_538))]),
            CodexBarAppStateMirror.Account(label: "go (b***b@example.com)", active: false, windows: []),
        ]
        let state = Self.state([Self.provider("codex", accounts: accounts)])
        try CodexBarAppStateMirror.write(state, to: url)
        let envelope = try CodexBarAppStateMirror.read(from: url)
        #expect(envelope.app == "codexbar")
        #expect(envelope.state == state)
        #expect(envelope.state.providers[0].accounts.count == 2)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(leftovers == ["codexbar.json"])
    }
}
