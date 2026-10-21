import Foundation
import Testing
@testable import CodexBarCore

/// opencodex (`ocx account list anthropic --quota --json`) lists the hub pool's
/// Anthropic OAuth accounts; these tests pin its wire shape (opencodex 2.83) and
/// the read-only snapshot a linked Mac reads instead.
struct OpenCodexAccountListTests {
    static let liveList = #"""
    {
      "accounts": [
        {
          "provider": "anthropic", "type": "oauth", "id": "978bdedac54d52d7c63cff74d0904d1e",
          "label": "a***e@example.com", "email": "a***e@example.com", "active": true, "health": "Healthy",
          "autoSwitchThresholdOverride": null, "plan": null,
          "quota": {
            "fiveHourPercent": 9, "fiveHourResetAt": 1792380599703,
            "weeklyPercent": 20, "weeklyResetAt": 1792861199703,
            "customWindows": [{"label": "Fable", "scope": "model", "percent": 5, "resetAt": 1792861199703}],
            "updatedAt": 1792379749856
          },
          "quotaUnavailable": false
        },
        {
          "provider": "anthropic", "type": "oauth", "id": "377b0c1d2e3f40516273849506a75592",
          "label": "b***b@example.com", "email": "b***b@example.com", "active": false, "health": "Healthy",
          "paused": true,
          "quota": {
            "fiveHourPercent": 0, "weeklyPercent": 100, "weeklyResetAt": 1792580399774,
            "customWindows": [{"label": "Fable", "scope": "model", "percent": 76, "resetAt": 1792580399775}],
            "updatedAt": 1792379749909
          },
          "quotaUnavailable": false
        },
        {
          "provider": "anthropic", "type": "oauth", "id": "c0ffee00c0ffee00c0ffee00c0ffee00",
          "label": "Team seat", "email": "c***c@example.com", "active": false,
          "health": "Reauthentication required", "needsReauth": true, "quota": null
        }
      ],
      "notes": []
    }
    """#

    /// A fake `ocx` that reports `role` for `ocx status --json` and runs `body` for every other command.
    private func makeFakeOCX(_ body: String, role: String = "hub") throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencodex-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let listFile = directory.appendingPathComponent("list.json")
        try Self.liveList.write(to: listFile, atomically: true, encoding: .utf8)
        let url = directory.appendingPathComponent("ocx")
        let script = """
        LIST='\(listFile.path)'
        printf '%s\\n' "$*" >> '\(url.path).calls'
        if [ "$1 $2" = "status --json" ]; then
          printf '{"schemaVersion":1,"runtimeRole":"%s"}\\n' '\(role)'
          exit 0
        fi
        \(body)
        """
        try FakeExecutable.install(script, at: url)
        return url.path
    }

    private func calls(_ executable: String) -> [String] {
        ((try? String(contentsOfFile: executable + ".calls", encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
    }

    @Test
    func `live hub list maps to slots in listing order with quota windows`() throws {
        let result = try OpenCodexAccountListParser.parseLiveList(Data(Self.liveList.utf8))
        let list = result.list
        #expect(list.supportsAccountSwitching)
        #expect(list.remoteCopy == nil)
        #expect(list.activeAccountNumber == 1)
        #expect(list.accounts.map(\.number) == [1, 2, 3])
        #expect(result.accountIDs[1] == "978bdedac54d52d7c63cff74d0904d1e")
        #expect(result.accountIDs[3] == "c0ffee00c0ffee00c0ffee00c0ffee00")

        let first = list.accounts[0]
        #expect(first.email == "a***e@example.com")
        #expect(first.alias == nil)
        #expect(first.usageStatus == .ok)
        #expect(first.fiveHour?.usedPercent == 9)
        #expect(first.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_792_380_599.703))
        #expect(first.sevenDay?.usedPercent == 20)
        #expect(first.scoped.map(\.name) == ["Fable"])
        #expect(first.usageFetchedAt == Date(timeIntervalSince1970: 1_792_379_749.856))

        #expect(list.accounts[1].isDisabled)
        #expect(list.accounts[1].sevenDay?.usedPercent == 100)
        #expect(list.accounts[2].usageStatus == .reloginRequired)
        #expect(list.accounts[2].alias == "Team seat")
    }

    @Test
    func `projected opencodex rows use their own identity and only inactive healthy rows switch`() throws {
        let now = Date(timeIntervalSince1970: 1_792_379_800)
        let list = try OpenCodexAccountListParser.parseLiveList(Data(Self.liveList.utf8)).list
        let accounts = ClaudeSwapAccountProjection.accountSnapshots(from: list, source: .openCodex, now: now)

        #expect(accounts.map(\.id.source) == ["opencodex", "opencodex", "opencodex"])
        #expect(accounts.map(\.id.opaqueID) == ["1", "2", "3"])
        #expect(accounts.allSatisfy { $0.sourceLabel == "opencodex" })
        #expect(accounts[0].isActive && !accounts[0].canActivate)
        #expect(accounts[1].canActivate)
        #expect(accounts[1].displayLabel == "b***b@example.com (disabled)")
        #expect(!accounts[2].canActivate)
        #expect(accounts[0].snapshot?.identity?.accountID == "opencodex:1")
        #expect(accounts[0].snapshot?.extraRateWindows?.map(\.window.usedPercent) == [5])
    }

    @Test
    func `rows from other providers and lists with two active accounts are handled strictly`() throws {
        let mixed = #"""
        {"accounts": [
          {"provider": "openai", "id": "x1", "active": true},
          {"provider": "anthropic", "id": "a1", "email": "a@example.com", "active": false,
           "quota": {"weeklyPercent": 3}}
        ]}
        """#
        let result = try OpenCodexAccountListParser.parseLiveList(Data(mixed.utf8))
        #expect(result.list.accounts.map(\.email) == ["a@example.com"])
        #expect(result.list.activeAccountNumber == nil)

        let twoActive = #"{"accounts": [{"id": "a1", "active": true}, {"id": "a2", "active": true}]}"#
        #expect(throws: OpenCodexAccountListError.self) {
            try OpenCodexAccountListParser.parseLiveList(Data(twoActive.utf8))
        }
        // An id `ocx account use` cannot take keeps its row but gets no switch target.
        let optionShapedID = #"{"accounts": [{"id": "--all", "active": false}, {"id": "__main__", "active": true}]}"#
        let unusable = try OpenCodexAccountListParser.parseLiveList(Data(optionShapedID.utf8))
        #expect(unusable.list.accounts.map(\.number) == [1, 2])
        #expect(unusable.accountIDs == [2: "__main__"])
    }

    @Test
    func `schema 1 snapshot is read only and names the hub and the time it was taken`() throws {
        let snapshot = #"""
        {"app": "opencodex-hub-accounts", "updatedAt": "2026-10-19T03:15:00Z", "state": {
          "schemaVersion": 1, "hub": "hub-mac", "fetchedAt": "2026-10-19T03:14:59Z",
          "accounts": [
            {"idSuffix": "4d1e", "label": "a***e@example.com", "active": true,
             "quota": {"fiveHourPercent": 9, "weeklyPercent": 20}},
            {"idSuffix": "5592", "label": "b***b@example.com", "active": false,
             "quota": {"fiveHourPercent": 0, "weeklyPercent": 100}}
          ]}}
        """#
        let result = try OpenCodexAccountListParser.parseSnapshot(Data(snapshot.utf8))
        let fetchedAt = try #require(ISO8601DateFormatter().date(from: "2026-10-19T03:14:59Z"))
        #expect(result.accountIDs.isEmpty)
        #expect(!result.list.supportsAccountSwitching)
        #expect(result.list.remoteCopy?.managerName == "hub-mac")
        #expect(result.list.remoteCopy?.fetchedAt == fetchedAt)
        #expect(result.list.remoteCopy?.isSwitchable == false)
        #expect(result.list.accounts.map(\.email) == ["a***e@example.com", "b***b@example.com"])
        #expect(result.list.accounts.allSatisfy { $0.usageFetchedAt == fetchedAt })

        let accounts = ClaudeSwapAccountProjection.accountSnapshots(from: result.list, source: .openCodex)
        #expect(accounts.allSatisfy { !$0.canActivate })
        #expect(accounts[0].isActive)
    }

    @Test
    func `reader uses the live list on the hub`() async throws {
        let ocx = try self.makeFakeOCX(#"cat "$LIST""#)
        let list = try await ClaudeSwapAccountReader.readAccountList(executablePath: ocx, source: .openCodex)
        #expect(list.accounts.count == 3)
        #expect(list.supportsAccountSwitching)
        #expect(self.calls(ocx) == ["status --json", "account list anthropic --quota --json"])
    }

    @Test
    func `a linked client falls back to the snapshot file or explains where accounts live`() async throws {
        let ocx = try self.makeFakeOCX(#"echo "Error: not_found" >&2; exit 4"#, role: "client")
        await #expect(throws: OpenCodexAccountListError.hubAccountsUnavailable("Error: not_found")) {
            _ = try await ClaudeSwapAccountReader.readAccountList(executablePath: ocx, source: .openCodex)
        }

        let snapshotURL = URL(fileURLWithPath: ocx).deletingLastPathComponent().appendingPathComponent("snap.json")
        let snapshot = #"{"hub": "hub-mac", "fetchedAt": 1792379749856, "#
            + #""accounts": [{"label": "a***e@example.com", "active": true}]}"#
        try snapshot.write(to: snapshotURL, atomically: true, encoding: .utf8)
        let list = try await ClaudeSwapAccountReader.readAccountList(
            executablePath: ocx,
            source: .openCodex,
            openCodexSnapshotPath: snapshotURL.path)
        #expect(list.remoteCopy?.managerName == "hub-mac")
        #expect(list.accounts.map(\.isActive) == [true])
        #expect(!list.supportsAccountSwitching)
    }

    @Test
    func `switch re-reads the hub list and selects the account by its opencodex id`() async throws {
        let ocx = try self.makeFakeOCX(#"""
        case "$1 $2" in
          "account list") cat "$LIST" ;;
          "account use") printf '{"ok":true,"provider":"%s","type":"oauth","activeId":"%s"}\n' "$3" "$4" ;;
          *) exit 64 ;;
        esac
        """#)
        let result = try await ClaudeSwapAccountReader.switchAccount(
            executablePath: ocx,
            accountNumber: 2,
            source: .openCodex,
            expectedEmail: "b***b@example.com")
        #expect(result == ClaudeSwapAccountSwitchResult(
            switched: true,
            fromAccountNumber: 1,
            toAccountNumber: 2,
            reason: "switched"))
        #expect(self.calls(ocx) == [
            "status --json",
            "account list anthropic --quota --json",
            "account use anthropic 377b0c1d2e3f40516273849506a75592 --json",
        ])
    }

    @Test
    func `switch refuses a slot that now holds another account and reports opencodex errors`() async throws {
        let ocx = try self.makeFakeOCX(#"""
        case "$1 $2" in
          "account list") cat "$LIST" ;;
          "account use") echo "Error: failed to switch anthropic" >&2; exit 1 ;;
        esac
        """#)
        await #expect(throws: OpenCodexAccountListError.accountChanged(slot: 2)) {
            _ = try await ClaudeSwapAccountReader.switchAccount(
                executablePath: ocx, accountNumber: 2, source: .openCodex, expectedEmail: "someone@else.example")
        }
        #expect(self.calls(ocx) == ["status --json", "account list anthropic --quota --json"])
        await #expect(throws: OpenCodexAccountListError.switchFailed("Error: failed to switch anthropic")) {
            _ = try await ClaudeSwapAccountReader.switchAccount(
                executablePath: ocx, accountNumber: 2, source: .openCodex, expectedEmail: "b***b@example.com")
        }
        await #expect(throws: OpenCodexAccountListError.accountNotFound(slot: 9)) {
            _ = try await ClaudeSwapAccountReader.switchAccount(
                executablePath: ocx, accountNumber: 9, source: .openCodex)
        }
    }

    @Test
    func `the executable directory leads PATH so a node launcher finds its interpreter`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencodex-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.liveList.write(to: directory.appendingPathComponent("list.json"), atomically: true, encoding: .utf8)
        // `fake-node` is found only through PATH, like `#!/usr/bin/env node` in the real launcher.
        try FakeExecutable.install(
            """
            if [ "$1 $2" = "status --json" ]; then echo '{"runtimeRole":"hub"}'; exit 0; fi
            cat '\(directory.appendingPathComponent("list.json").path)'

            """,
            at: directory.appendingPathComponent("fake-node"))
        let ocx = directory.appendingPathComponent("ocx").path
        try FakeExecutable.install("exec fake-node \"$@\"\n", at: URL(fileURLWithPath: ocx))

        #expect(OpenCodexAccountReader.environment(for: ocx, base: ["PATH": "/usr/bin:/bin"])["PATH"]
            == directory.path + ":/usr/bin:/bin")
        let list = try await ClaudeSwapAccountReader.readAccountList(executablePath: ocx, source: .openCodex)
        #expect(list.accounts.count == 3)
    }

    @Test
    func `opencodex config keys resolve the source and the snapshot path`() {
        var config = ProviderConfig(id: .claude)
        config.claudeSwapSource = "opencodex"
        config.openCodexHubSnapshotPath = "  ~/hub.json  "
        #expect(config.resolvedClaudeSwapSource == .openCodex)
        #expect(config.sanitizedOpenCodexHubSnapshotPath == "~/hub.json")
        #expect(ClaudeSwapAccountSource.openCodex.canSwitchAccounts)
        #expect(!ClaudeSwapAccountSource.tcr.canSwitchAccounts)
    }
}
