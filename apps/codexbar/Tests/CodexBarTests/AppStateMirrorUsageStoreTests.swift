import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

/// What the app writes to its state mirror (`~/.swift-app-state/codexbar.json`) for a hub-backed Codex card.
@MainActor
struct AppStateMirrorUsageStoreTests {
    private static var snapshot: String {
        #"""
        {"app": "opencodex-hub-accounts", "updatedAt": "\#(ISO8601DateFormatter().string(from: Date()))", "state": {
          "schemaVersion": 2, "hub": "hub-mac", "fetchedAt": "2026-10-19T03:14:58Z", "accounts": [],
          "providers": {
            "openai": {"switchable": false, "switchReason": "Switched only on hub-mac.", "accounts": [
              {"idSuffix": "cccc", "label": "pro", "email": "a***a@example.invalid", "active": true, "paused": false,
               "needsReauth": false, "health": "Healthy", "quotaUnavailable": false,
               "quota": {"weeklyPercent": 51, "weeklyResetAt": 1792889538000, "updatedAt": 1792386000000}},
              {"idSuffix": "dddd", "label": "go", "email": "b***b@example.invalid", "active": false, "paused": false,
               "needsReauth": false, "health": "Healthy", "quotaUnavailable": false,
               "quota": {"monthlyPercent": 0, "updatedAt": 1792386000000}}
            ]}
          },
          "lastRequests": []
        }}
        """#
    }

    private func makeFixture() throws -> (CodexWorkspacesNavigationFixture, URL) {
        let fixture = try CodexWorkspacesNavigationFixture(userDefaults: InMemoryUserDefaults())
        let snapshotURL = fixture.files.root.appendingPathComponent("opencodex-hub-accounts.json")
        try Self.snapshot.write(to: snapshotURL, atomically: true, encoding: .utf8)
        let executable = fixture.files.root.appendingPathComponent("ocx")
        let script = """
        #!/bin/sh
        case "$1 $2" in
          "status --json") echo '{"schemaVersion":1,"runtimeRole":"client"}' ;;
          *) echo 'Error: not_found' >&2; exit 1 ;;
        esac
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        fixture.settings.codexOpenCodexHubEnabled = true
        fixture.settings.codexOpenCodexHubExecutablePath = executable.path
        fixture.settings.codexOpenCodexHubSnapshotPath = snapshotURL.path
        return (fixture, snapshotURL)
    }

    @Test
    func `a hub-backed Codex card is mirrored with its source, accounts and role`() async throws {
        let (fixture, _) = try self.makeFixture()
        defer { fixture.cleanup() }
        #expect(await fixture.store.refreshOpenCodexHubCard(.codex, generation: nil))

        let state = fixture.store.appStateMirrorState()
        #expect(state.status == "ok")
        #expect(state.lastError == nil)
        #expect(state.hubRole == "client")
        let codex = try #require(state.providers.first { $0.id == "codex" })
        #expect(codex.source == "opencodex-hub")
        #expect(codex.accountSource == "opencodex-hub")
        #expect(codex.error == nil)
        #expect(!codex.stale)
        #expect(codex.lastRefreshAt != nil)
        #expect(codex.accounts.map(\.label) == ["pro (a***a@example.invalid)", "go (b***b@example.invalid)"])
        #expect(codex.accounts.map(\.active) == [true, false])
        #expect(codex.accounts[0].windows.map(\.name) == ["weekly"])
        #expect(codex.accounts[0].windows.first?.usedPercent == 51)
        #expect(codex.accounts[1].windows.map(\.name) == ["monthly"])
        #expect(!codex.windows.isEmpty)
    }

    @Test
    func `a full Codex refresh through the provider pipeline keeps the hub card`() async throws {
        let (fixture, _) = try self.makeFixture()
        defer { fixture.cleanup() }
        // Run the real provider pipeline (the fixture stubs it to catch unexpected transports).
        fixture.store._test_providerRefreshOverride = nil
        for layout in [MultiAccountMenuLayout.segmented, .stacked] {
            fixture.settings.multiAccountMenuLayout = layout
            await fixture.store.refreshProvider(.codex, allowDisabled: true)
            let codex = try #require(fixture.store.appStateMirrorState().providers.first { $0.id == "codex" })
            #expect(codex.source == "opencodex-hub", "\(layout)")
            #expect(codex.error == nil, "\(layout): \(codex.error ?? "")")
            #expect(codex.accounts.count == 2, "\(layout)")
            #expect(fixture.store.snapshots[UsageProvider.codex.instanceID] != nil, "\(layout)")
        }
    }

    @Test
    func `a hub read failure is mirrored as the card's error`() async throws {
        let (fixture, snapshotURL) = try self.makeFixture()
        defer { fixture.cleanup() }
        try "not json".write(to: snapshotURL, atomically: true, encoding: .utf8)
        #expect(await fixture.store.refreshOpenCodexHubCard(.codex, generation: nil))

        let state = fixture.store.appStateMirrorState()
        #expect(state.status == "error")
        let codex = try #require(state.providers.first { $0.id == "codex" })
        #expect(codex.error != nil)
        #expect(state.lastError?.hasPrefix("codex: ") == true)
    }

    @Test
    func `publishing writes the envelope once and skips an unchanged state`() async throws {
        let (fixture, _) = try self.makeFixture()
        defer { fixture.cleanup() }
        let url = fixture.files.root.appendingPathComponent("state/codexbar.json")
        fixture.store.appStateMirrorRecorder.fileURLOverride = url
        #expect(await fixture.store.refreshOpenCodexHubCard(.codex, generation: nil))

        let now = Date()
        fixture.store.publishAppStateMirror(now: now)
        let first = try CodexBarAppStateMirror.read(from: url)
        #expect(first.app == "codexbar")
        #expect(first.state.providers.first { $0.id == "codex" }?.accounts.count == 2)

        fixture.store.publishAppStateMirror(now: now.addingTimeInterval(5))
        #expect(try CodexBarAppStateMirror.read(from: url).updatedAt == first.updatedAt)
        fixture.store.publishAppStateMirror(now: now.addingTimeInterval(120))
        #expect(try CodexBarAppStateMirror.read(from: url).updatedAt != first.updatedAt)
    }
}
