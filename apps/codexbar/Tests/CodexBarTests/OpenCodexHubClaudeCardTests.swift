import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

/// The Claude card reads the opencodex hub's anthropic pool like the Codex and Grok cards: the hub pool is the
/// account the hub routes to, and the opencodex account adapter (the same pool) stays off.
@MainActor
struct OpenCodexHubClaudeCardTests {
    private static var snapshot: String {
        #"""
        {"app": "opencodex-hub-accounts", "updatedAt": "\#(ISO8601DateFormatter().string(from: Date()))", "state": {
          "schemaVersion": 2, "hub": "hub-mac", "fetchedAt": "2026-10-19T03:14:58Z",
          "accounts": [{"idSuffix": "4d1e", "label": "t***m@example.invalid", "active": true}],
          "providers": {
            "anthropic": {"switchable": true, "switchReason": null, "accounts": [
              {"idSuffix": "4d1e", "label": "t***m@example.invalid", "email": "t***m@example.invalid", "active": true,
               "paused": false, "needsReauth": false, "health": "Healthy", "quotaUnavailable": false,
               "quota": {"fiveHourPercent": 30, "weeklyPercent": 36, "updatedAt": 1792415528371}},
              {"idSuffix": "5592", "label": "u***5@example.invalid", "email": "u***5@example.invalid", "active": false,
               "paused": false, "needsReauth": false, "health": "Healthy", "quotaUnavailable": false,
               "quota": {"fiveHourPercent": 0, "weeklyPercent": 100, "updatedAt": 1792415528371}}
            ]}
          },
          "lastRequests": []
        }}
        """#
    }

    private func makeFixture() throws -> CodexWorkspacesNavigationFixture {
        let fixture = try CodexWorkspacesNavigationFixture(userDefaults: InMemoryUserDefaults())
        let snapshotURL = fixture.files.root.appendingPathComponent("opencodex-hub-accounts.json")
        try Self.snapshot.write(to: snapshotURL, atomically: true, encoding: .utf8)
        let executable = fixture.files.root.appendingPathComponent("ocx")
        try """
        #!/bin/sh
        case "$1 $2" in
          "status --json") echo '{"schemaVersion":1,"runtimeRole":"client"}' ;;
          *) echo 'Error: not_found' >&2; exit 1 ;;
        esac
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        fixture.settings.setOpenCodexHubEnabled(true, for: .claude)
        fixture.settings.setOpenCodexHubExecutablePath(executable.path, for: .claude)
        fixture.settings.setOpenCodexHubSnapshotPath(snapshotURL.path, for: .claude)
        fixture.settings.claudeSwapEnabled = true
        fixture.settings.claudeSwapSource = .openCodex
        fixture.settings.claudeSwapOpenCodexSnapshotPath = snapshotURL.path
        return fixture
    }

    @Test
    func `the Claude card shows the hub's active anthropic account and lists the pool`() async throws {
        let fixture = try self.makeFixture()
        defer { fixture.cleanup() }
        #expect(fixture.store.usesOpenCodexHub(for: .claude))
        #expect(await fixture.store.refreshOpenCodexHubCard(.claude, generation: nil))

        let pool = try #require(fixture.store.openCodexHubCardState(for: .claude)?.pool)
        #expect(pool.provider == .anthropic)
        #expect(pool.accounts.map(\.idSuffix) == ["4d1e", "5592"])
        #expect(pool.activeAccount?.idSuffix == "4d1e")
        let snapshot = try #require(fixture.store.snapshots[UsageProvider.claude.instanceID])
        #expect(snapshot.primary?.usedPercent == 30)
        #expect(fixture.store.errors[UsageProvider.claude.instanceID] == nil)
    }

    @Test
    func `the opencodex account adapter stays off while the Claude card reads the hub`() async throws {
        let fixture = try self.makeFixture()
        defer { fixture.cleanup() }
        fixture.settings.setProviderEnabled(
            provider: .claude,
            metadata: fixture.store.metadata(for: .claude),
            enabled: true)
        #expect(fixture.store.claudeCardReplacesOpenCodexAdapter)
        #expect(!fixture.store.shouldFetchClaudeSwapAccounts())

        await fixture.store.refreshClaudeSwapAccounts()
        #expect(fixture.store.claudeSwapAccountSnapshots.isEmpty)
        #expect(fixture.store.claudeSwapLastError == nil)

        // Another adapter source is a separate account store and keeps running.
        fixture.settings.claudeSwapSource = .claudeSwap
        #expect(!fixture.store.claudeCardReplacesOpenCodexAdapter)
    }
}
