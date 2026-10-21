import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

/// Codex and Grok cards that read an opencodex hub pool, and the Claude adapter's switch request on a
/// Mac that is not the hub.
@MainActor
struct OpenCodexHubCardTests {
    /// The hub snapshot as just written (a switch is asked for only through a current snapshot).
    private static var snapshot: String {
        self.snapshotTemplate.replacingOccurrences(
            of: #""updatedAt": "2026-10-19T03:15:00Z""#,
            with: #""updatedAt": "\#(ISO8601DateFormatter().string(from: Date()))""#)
    }

    private static let snapshotTemplate = #"""
    {"app": "opencodex-hub-accounts", "updatedAt": "2026-10-19T03:15:00Z", "state": {
      "schemaVersion": 2, "hub": "hub-mac", "fetchedAt": "2026-10-19T03:14:58Z",
      "accounts": [],
      "providers": {
        "anthropic": {"switchable": true, "switchReason": null, "accounts": [
          {"idSuffix": "aaaa", "label": "a***a@example.invalid", "email": "a***a@example.invalid", "active": true,
           "paused": false, "needsReauth": false, "health": "Healthy", "quotaUnavailable": false,
           "quota": {"fiveHourPercent": 4, "weeklyPercent": 10, "updatedAt": 1792386686100}},
          {"idSuffix": "bbbb", "label": "b***b@example.invalid", "email": "b***b@example.invalid", "active": false,
           "paused": false, "needsReauth": false, "health": "Healthy", "quotaUnavailable": false,
           "quota": {"fiveHourPercent": 0, "weeklyPercent": 90, "updatedAt": 1792386686100}}
        ]},
        "openai": {"switchable": false, "switchReason": "Switched only on hub-mac.", "accounts": [
          {"idSuffix": "cccc", "label": "pro", "email": "a***a@example.invalid", "active": true, "paused": false,
           "needsReauth": false, "health": "Healthy", "quotaUnavailable": false,
           "quota": {"weeklyPercent": 51, "weeklyResetAt": 1792889538000, "updatedAt": 1792386000000}},
          {"idSuffix": "dddd", "label": "go", "email": "b***b@example.invalid", "active": false, "paused": false,
           "needsReauth": false, "health": "Healthy", "quotaUnavailable": false,
           "quota": {"monthlyPercent": 0, "updatedAt": 1792386000000}}
        ]},
        "xai": {"switchable": true, "switchReason": null, "accounts": [
          {"idSuffix": "eeee", "label": "a***a@example.invalid", "email": "a***a@example.invalid", "active": true,
           "paused": false, "needsReauth": false, "health": "Healthy", "quotaUnavailable": false,
           "quota": {"weeklyPercent": 43, "updatedAt": 1792386505020}},
          {"idSuffix": "ffff", "label": "b***b@example.invalid", "email": "b***b@example.invalid", "active": false,
           "paused": false, "needsReauth": false, "health": "Healthy", "quotaUnavailable": false,
           "quota": {"weeklyPercent": 0, "updatedAt": 1792386505020}}
        ]}
      },
      "lastRequests": []
    }}
    """#

    private func makeFixture() throws -> (CodexWorkspacesNavigationFixture, String, String) {
        let fixture = try CodexWorkspacesNavigationFixture(userDefaults: InMemoryUserDefaults())
        let snapshotURL = fixture.files.root.appendingPathComponent("opencodex-hub-accounts.json")
        try Self.snapshot.write(to: snapshotURL, atomically: true, encoding: .utf8)
        // A linked client: ocx reports the client role and refuses everything else here.
        let executable = fixture.files.root.appendingPathComponent("ocx")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$0.calls"
        case "$1 $2" in
          "status --json") echo '{"schemaVersion":1,"runtimeRole":"client"}' ;;
          *) echo 'Error: not_found' >&2; exit 1 ;;
        esac
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return (fixture, executable.path, snapshotURL.path)
    }

    private func requestFiles(_ fixture: CodexWorkspacesNavigationFixture) -> [String] {
        let directory = fixture.files.root.appendingPathComponent("opencodex-hub-requests")
        return (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    @Test
    func `hub source is off by default and only Claude, Codex and Grok cards read it through these settings`() throws {
        let (fixture, _, _) = try self.makeFixture()
        defer { fixture.cleanup() }
        #expect(!fixture.settings.codexOpenCodexHubEnabled)
        #expect(!fixture.store.usesOpenCodexHub(for: .codex))
        fixture.settings.codexOpenCodexHubEnabled = true
        fixture.settings.setOpenCodexHubEnabled(true, for: .claude)
        #expect(fixture.store.usesOpenCodexHub(for: .codex))
        #expect(!fixture.store.usesOpenCodexHub(for: .grok))
        #expect(fixture.store.usesOpenCodexHub(for: .claude))
        fixture.settings.setOpenCodexHubEnabled(true, for: .cursor)
        #expect(!fixture.store.usesOpenCodexHub(for: .cursor))
    }

    @Test
    func `a Mac with no hub source reads the card's own sources until a snapshot appears`() async throws {
        let (fixture, _, snapshotPath) = try self.makeFixture()
        defer { fixture.cleanup() }
        try FileManager.default.removeItem(atPath: snapshotPath)
        fixture.settings.codexOpenCodexHubEnabled = true
        fixture.settings.codexOpenCodexHubExecutablePath = fixture.files.root.appendingPathComponent("no-ocx").path
        fixture.settings.codexOpenCodexHubSnapshotPath = snapshotPath

        let handled = await fixture.store.refreshOpenCodexHubCard(.codex, generation: nil)
        #expect(!handled)
        #expect(!fixture.store.usesOpenCodexHub(for: .codex))
        #expect(fixture.store.openCodexHubCardState(for: .codex) == nil)
        #expect(fixture.store.errors[UsageProvider.codex.instanceID] == nil)

        try Self.snapshot.write(toFile: snapshotPath, atomically: true, encoding: .utf8)
        let handledAgain = await fixture.store.refreshOpenCodexHubCard(.codex, generation: nil)
        #expect(handledAgain)
        #expect(fixture.store.usesOpenCodexHub(for: .codex))
        #expect(fixture.store.openCodexHubCardState(for: .codex)?.pool?.accounts.count == 2)
    }

    @Test
    func `a linked copy names the hub and says why switching is off`() {
        let pool = OpenCodexHubPool(
            provider: .openai,
            accounts: [
                OpenCodexHubAccount(idSuffix: "aaaa", label: nil, email: "a***a@example.invalid", isActive: true),
            ],
            switchable: false,
            origin: .linkedCopy(hubName: "hub-mac"))
        #expect(OpenCodexHubPresentation.poolNotices(pool, now: .distantFuture) == [
            L("Accounts are managed on the hub %@.", "hub-mac"),
            L("Switching is off until the hub writes a current snapshot to this Mac."),
        ])
    }

    @Test
    func `codex card renders the active hub account and gates switching when the pool is hub only`() async throws {
        let (fixture, executable, snapshotPath) = try self.makeFixture()
        defer { fixture.cleanup() }
        fixture.settings.codexOpenCodexHubEnabled = true
        fixture.settings.codexOpenCodexHubExecutablePath = executable
        fixture.settings.codexOpenCodexHubSnapshotPath = snapshotPath
        fixture.store.errors[UsageProvider.codex.instanceID] =
            "Codex is configured for a custom provider; ChatGPT rate limits are unavailable."

        await fixture.store.refreshOpenCodexHubCard(.codex, generation: nil)

        let snapshot = try #require(fixture.store.snapshots[UsageProvider.codex.instanceID])
        #expect(snapshot.primary?.usedPercent == 51)
        #expect(snapshot.primary?.windowMinutes == 7 * 24 * 60)
        #expect(fixture.store.errors[UsageProvider.codex.instanceID] == nil)
        #expect(fixture.store.lastSourceLabels[UsageProvider.codex.instanceID] == "opencodex")
        let state = try #require(fixture.store.openCodexHubCardState(for: .codex))
        let pool = try #require(state.pool)
        #expect(!pool.switchable)
        #expect(OpenCodexHubPresentation.poolNotices(pool, now: pool.snapshotUpdatedAt ?? .now)
            == [L("Accounts are managed on the hub %@.", "hub-mac"), "Switched only on hub-mac."])
        #expect(OpenCodexHubPresentation.poolNotices(pool, now: .distantFuture).count == 3)

        let target = pool.accounts[1]
        fixture.store.switchOpenCodexHubAccount(target, provider: .codex, label: "b")
        #expect(fixture.store.openCodexHubCardState(for: .codex)?.isSwitching == false)
        #expect(self.requestFiles(fixture).isEmpty)
        let calls = (try? String(contentsOfFile: executable + ".calls", encoding: .utf8)) ?? ""
        #expect(!calls.contains("account use"))
    }

    @Test
    func `grok card asks the hub to switch and waits for the next snapshot`() async throws {
        let (fixture, executable, snapshotPath) = try self.makeFixture()
        defer {
            fixture.store.clearOpenCodexHubCardState(.grok)
            fixture.cleanup()
        }
        fixture.settings.grokOpenCodexHubEnabled = true
        fixture.settings.grokOpenCodexHubExecutablePath = executable
        fixture.settings.grokOpenCodexHubSnapshotPath = snapshotPath
        await fixture.store.refreshOpenCodexHubCard(.grok, generation: nil)
        let pool = try #require(fixture.store.openCodexHubCardState(for: .grok)?.pool)
        let target = pool.accounts[1]
        #expect(pool.canSwitch(to: target))

        fixture.store._test_providerRefreshOverride = { _ in }
        defer { fixture.store._test_providerRefreshOverride = nil }
        var progress = 0
        fixture.store.switchOpenCodexHubAccount(target, provider: .grok, label: "b***b") { progress += 1 }
        let deadline = Date().addingTimeInterval(10)
        while progress < 2, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(progress == 2)
        let status = try #require(fixture.store.openCodexHubCardState(for: .grok)?.switchStatus)
        #expect(status.isPending)
        #expect(status.menuLines(hidePersonalInfo: false) == [L("The hub is switching accounts…")])
        let files = self.requestFiles(fixture)
        #expect(files.count == 1)
        let requestID = try #require(files.first?.replacingOccurrences(of: ".json", with: ""))

        // The hub's next snapshot reports the request as done and lists the target as active.
        let done = Self.snapshot.replacingOccurrences(
            of: #""lastRequests": []"#,
            with: #""lastRequests": [{"requestId": "\#(requestID)", "from": "client", "provider": "xai", "#
                + #""target": {"idSuffix": "ffff", "email": "b***b@example.invalid"}, "result": "done", "#
                + #""code": "switched", "reason": null, "at": "2026-10-19T03:16:00Z"}]"#)
        try Self.activatingXAI("ffff", in: done).write(toFile: snapshotPath, atomically: true, encoding: .utf8)
        await fixture.store.refreshOpenCodexHubCard(.grok, generation: nil)
        let resolved = try #require(fixture.store.openCodexHubCardState(for: .grok)?.switchStatus)
        #expect(!resolved.isPending)
        #expect(resolved.menuLines(hidePersonalInfo: false) == [L("The hub switched to %@.", "b***b")])

        // The hub later moves back on its own: the menu follows the active account, not the old answer.
        try done.write(toFile: snapshotPath, atomically: true, encoding: .utf8)
        await fixture.store.refreshOpenCodexHubCard(.grok, generation: nil)
        let movedOn = try #require(fixture.store.openCodexHubCardState(for: .grok)?.switchStatus)
        #expect(movedOn.menuLines(hidePersonalInfo: false)
            == [L("The hub has since switched to %@.", "a***a@example.invalid")])
        #expect(movedOn.menuLines(hidePersonalInfo: true)
            == [L("The hub has since switched to %@.", L("Account %@", "1"))])
    }

    /// The xai pool of `snapshot` with `idSuffix` as its only active account.
    private static func activatingXAI(_ idSuffix: String, in snapshot: String) -> String {
        let rows = [
            ("eeee", "a***a@example.invalid"),
            ("ffff", "b***b@example.invalid"),
        ]
        var text = snapshot
        for (suffix, email) in rows {
            let prefix = #"{"idSuffix": "\#(suffix)", "label": "\#(email)", "email": "\#(email)", "active": "#
            for state in ["true", "false"] {
                text = text.replacingOccurrences(
                    of: prefix + state,
                    with: prefix + (suffix == idSuffix ? "true" : "false"))
            }
        }
        return text
    }

    @Test
    func `a switch answer is shown only while the hub keeps that account active`() {
        let pool = { (active: String) in
            OpenCodexHubPool(
                provider: .openai,
                accounts: ["aaaa", "bbbb"].map { suffix in
                    OpenCodexHubAccount(
                        idSuffix: suffix,
                        label: nil,
                        email: "\(suffix)@example.invalid",
                        isActive: suffix == active)
                },
                switchable: true,
                origin: .hubLocal)
        }
        var status = OpenCodexHubSwitchStatus()
        status.finish(.switched("bbbb"), activeAccount: .init(idSuffix: "bbbb", email: "bbbb@example.invalid"))
        // The menu can render before the next read; the answer stands until a newer pool contradicts it.
        #expect(status.menuLines(hidePersonalInfo: false) == [L("The hub switched to %@.", "bbbb")])
        let unchanged = status.reconcile(with: pool("bbbb"))
        #expect(!unchanged)
        #expect(status.menuLines(hidePersonalInfo: false) == [L("The hub switched to %@.", "bbbb")])
        let movedOn = status.reconcile(with: pool("aaaa"))
        #expect(movedOn)
        #expect(status.menuLines(hidePersonalInfo: false)
            == [L("The hub has since switched to %@.", "aaaa@example.invalid")])

        status.finish(.failed("busy"), activeAccount: .init(idSuffix: "aaaa", email: "aaaa@example.invalid"))
        let stillActive = status.reconcile(with: pool("aaaa"))
        #expect(!stillActive)
        #expect(status.menuLines(hidePersonalInfo: false) == [L("The hub could not switch: %@", "busy")])
        let movedAgain = status.reconcile(with: pool("bbbb"))
        #expect(movedAgain)
        #expect(status.menuLines(hidePersonalInfo: true)
            == [L("The hub has since switched to %@.", L("Account %@", "2"))])
    }

    @Test
    func `every hub switch confirmation keeps one button order and layout`() {
        _ = NSApplication.shared
        let short = OpenCodexHubSwitchConfirmation.makeAlert(
            accountLabel: "b***b@example.invalid",
            details: L("Every Mac that uses this hub moves to this account on its next request."))
        let nearLimit = L(
            "This account has used %@ or more of a limit. The hub may switch away again soon, " +
                "or requests may stop until the limit resets.",
            "80%")
        let long = OpenCodexHubSwitchConfirmation.makeAlert(
            accountLabel: "b***b@example.invalid",
            details: [
                L("Every Mac that uses this hub moves to this Claude account on its next request."),
                L("Quota: %@", "5h 9% · Weekly 100% · Fable 76%"),
                nearLimit,
                L("This Mac asks the hub to switch; the result shows after the hub's next update."),
                nearLimit,
            ].joined(separator: "\n\n"))
        for alert in [short, long] {
            #expect(alert.buttons.map(\.title) == [L("Switch Account..."), L("Cancel")])
            #expect(alert.buttons.map(\.keyEquivalent) == ["\r", "\u{1B}"])
            alert.layout()
        }
        #expect(short.window.frame.width == long.window.frame.width)
        #expect(short.buttons.map(\.frame) == long.buttons.map(\.frame))
    }

    @Test
    func `claude adapter on a linked Mac writes a request instead of switching`() async throws {
        let (fixture, executable, snapshotPath) = try self.makeFixture()
        defer {
            fixture.store.clearClaudeSwapAccountState()
            fixture.cleanup()
        }
        let metadata = try #require(ProviderRegistry.shared.metadata[.claude])
        fixture.settings.setProviderEnabled(provider: .claude, metadata: metadata, enabled: true)
        fixture.settings.claudeSwapExecutablePath = executable
        fixture.settings.claudeSwapSource = .openCodex
        fixture.settings.claudeSwapOpenCodexSnapshotPath = snapshotPath
        fixture.settings.claudeSwapEnabled = true
        let result = try OpenCodexAccountReader.readSnapshot(path: snapshotPath)
        fixture.store.claudeSwapRemoteCopy = result.list.remoteCopy
        fixture.store.claudeSwapAccountSnapshots = ClaudeSwapAccountProjection.accountSnapshots(
            from: result.list,
            source: .openCodex)
        let target = try #require(fixture.store.claudeSwapAccountSnapshots.first { !$0.isActive })
        #expect(target.canActivate)

        fixture.store.switchClaudeSwapAccount(target.id)
        let task = try #require(fixture.store.claudeSwapTransientState.task)
        await task.value

        #expect(fixture.store.claudeSwapTransientState.lastError == nil)
        #expect(fixture.store.claudeSwapHubSwitchStatus.isPending)
        #expect(self.requestFiles(fixture).count == 1)
    }
}
