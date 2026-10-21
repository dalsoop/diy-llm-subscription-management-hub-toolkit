import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct ClaudeSwapOpenCodexSwitchTests {
    private static let list = """
    {"accounts": [
      {"provider": "anthropic", "id": "aaaa1111", "email": "a***a@example.invalid", "active": true,
       "quota": {"fiveHourPercent": 4, "weeklyPercent": 10}},
      {"provider": "anthropic", "id": "bbbb2222", "email": "b***b@example.invalid", "active": false,
       "quota": {"fiveHourPercent": 0, "weeklyPercent": 20}}
    ], "notes": []}
    """

    private func makeFixture() throws -> (CodexWorkspacesNavigationFixture, URL) {
        let fixture = try CodexWorkspacesNavigationFixture(userDefaults: InMemoryUserDefaults())
        let listFile = fixture.files.root.appendingPathComponent("ocx-list.json")
        try Self.list.write(to: listFile, atomically: true, encoding: .utf8)
        let executable = fixture.files.root.appendingPathComponent("ocx")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$0.calls"
        case "$1 $2" in
          "status --json") echo '{"schemaVersion":1,"runtimeRole":"hub"}' ;;
          "account list") cat '\(listFile.path)' ;;
          "account use") printf '{"ok":true,"provider":"anthropic","type":"oauth","activeId":"%s"}\\n' "$4" ;;
          *) exit 64 ;;
        esac
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let metadata = try #require(ProviderRegistry.shared.metadata[.claude])
        fixture.settings.setProviderEnabled(provider: .claude, metadata: metadata, enabled: true)
        fixture.settings.claudeSwapExecutablePath = executable.path
        fixture.settings.claudeSwapSource = .openCodex
        fixture.settings.claudeSwapEnabled = true
        return (fixture, executable)
    }

    @Test
    func `hub switch selects the listed opencodex account id and reconciles`() async throws {
        let (fixture, executable) = try self.makeFixture()
        defer { fixture.cleanup() }
        let list = try OpenCodexAccountListParser.parseLiveList(Data(Self.list.utf8)).list
        fixture.store.claudeSwapAccountSnapshots = ClaudeSwapAccountProjection.accountSnapshots(
            from: list,
            source: .openCodex)
        let target = try #require(fixture.store.claudeSwapAccountSnapshots.first { !$0.isActive })
        #expect(target.canActivate)
        #expect(target.id == ProviderAccountIdentity(source: "opencodex", opaqueID: "2"))
        fixture.store._test_providerRefreshOverride = { provider in
            #expect(provider == .claude)
        }
        defer { fixture.store._test_providerRefreshOverride = nil }

        fixture.store.switchClaudeSwapAccount(target.id)
        let task = try #require(fixture.store.claudeSwapTransientState.task)
        await task.value

        #expect(fixture.store.claudeSwapTransientState.lastError == nil)
        #expect(fixture.store.claudeSwapTransientState.task == nil)
        let calls = try String(contentsOfFile: executable.path + ".calls", encoding: .utf8)
        #expect(calls.split(separator: "\n") == [
            "status --json",
            "account list anthropic --quota --json",
            "account use anthropic bbbb2222 --json",
        ])
    }

    @Test
    func `a read only hub snapshot never starts a switch`() throws {
        let (fixture, executable) = try self.makeFixture()
        defer { fixture.cleanup() }
        let snapshot = try OpenCodexAccountListParser.parseSnapshot(Data(Self.list.utf8)).list
        fixture.store.claudeSwapAccountSnapshots = ClaudeSwapAccountProjection.accountSnapshots(
            from: snapshot,
            source: .openCodex)
        let target = try #require(fixture.store.claudeSwapAccountSnapshots.first { !$0.isActive })
        #expect(!target.canActivate)
        #expect(ClaudeSwapAccountMenuDisplay.actionLabel(
            for: target,
            switchingAccountID: nil,
            switchInFlight: false,
            switchPhase: nil) == nil)

        fixture.store.switchClaudeSwapAccount(target.id)
        #expect(fixture.store.claudeSwapTransientState.task == nil)
        #expect(!FileManager.default.fileExists(atPath: executable.path + ".calls"))
    }
}
