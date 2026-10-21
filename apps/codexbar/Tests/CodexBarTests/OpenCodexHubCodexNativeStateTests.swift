import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

/// A Codex card that reads the opencodex hub must not be cleared or overwritten by Codex's own account
/// bookkeeping (usage owner reconciliation, credits, the OpenAI web dashboard), which only knows native sources.
@MainActor
struct OpenCodexHubCodexNativeStateTests {
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

    private func makeHubBackedCodexCard() async throws -> CodexWorkspacesNavigationFixture {
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
        fixture.settings.codexOpenCodexHubEnabled = true
        fixture.settings.codexOpenCodexHubExecutablePath = executable.path
        fixture.settings.codexOpenCodexHubSnapshotPath = snapshotURL.path
        #expect(await fixture.store.refreshOpenCodexHubCard(.codex, generation: nil))
        #expect(fixture.store.snapshots[UsageProvider.codex.instanceID] != nil)
        return fixture
    }

    @Test
    func `usage owner reconciliation keeps the hub card's snapshot`() async throws {
        let fixture = try await self.makeHubBackedCodexCard()
        defer { fixture.cleanup() }

        // Credits and dashboard refreshes call this with the local Codex account; the hub card has no local owner.
        let cleared = fixture.store.reconcileCodexPublishedUsageOwner(
            with: fixture.store.freshCodexAccountScopedRefreshGuard())
        #expect(!cleared)
        #expect(fixture.store.snapshots[UsageProvider.codex.instanceID] != nil)
        let sourceLabel = fixture.store.lastSourceLabels[UsageProvider.codex.instanceID]
        #expect(sourceLabel == OpenCodexHubUsageProjection.sourceLabel)

        fixture.store.clearCodexPublishedUsageState()
        #expect(fixture.store.snapshots[UsageProvider.codex.instanceID] != nil)

        let codex = try #require(fixture.store.appStateMirrorState().providers.first { $0.id == "codex" })
        #expect(codex.error == nil)
        #expect(codex.accounts.count == 2)
        #expect(!codex.windows.isEmpty)
    }

    @Test
    func `credits refresh leaves a hub-backed Codex card without a native credits error`() async throws {
        let fixture = try await self.makeHubBackedCodexCard()
        defer { fixture.cleanup() }
        let nativeError = "Codex is configured for a custom provider; ChatGPT rate limits are unavailable"
        var loaderCalls = 0
        fixture.store._test_codexCreditsLoaderOverride = {
            loaderCalls += 1
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: nativeError])
        }
        fixture.store.lastCreditsError = nativeError

        await fixture.store.refreshCreditsIfNeeded()
        #expect(loaderCalls == 0)
        #expect(fixture.store.lastCreditsError == nil)
        #expect(fixture.store.credits == nil)
        #expect(fixture.store.snapshots[UsageProvider.codex.instanceID] != nil)
    }

    @Test
    func `the OpenAI web dashboard is not read for a hub-backed Codex card`() async throws {
        let fixture = try await self.makeHubBackedCodexCard()
        defer { fixture.cleanup() }
        fixture.settings.openAIWebAccessEnabled = true
        var dashboardLoads = 0
        fixture.store._test_openAIDashboardLoaderOverride = { _, _, _, _ in
            dashboardLoads += 1
            throw NSError(domain: "test", code: 1)
        }

        await fixture.store.refreshOpenAIDashboardIfNeeded(force: true)
        #expect(dashboardLoads == 0)
        #expect(fixture.store.snapshots[UsageProvider.codex.instanceID] != nil)
        #expect(fixture.store.errors[UsageProvider.codex.instanceID] == nil)
    }
}
