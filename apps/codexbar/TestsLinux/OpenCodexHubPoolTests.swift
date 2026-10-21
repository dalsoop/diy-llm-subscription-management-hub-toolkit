import Foundation
import Testing
@testable import CodexBarCore

/// The opencodex hub snapshot (schema 1 and 2), switch request files and the hub-local `ocx` path for
/// the Anthropic, OpenAI and xAI pools.
struct OpenCodexHubPoolTests {
    /// Schema 2 as the hub writes it: quota times in epoch milliseconds, `state.accounts` kept for schema 1.
    static let snapshotV2 = #"""
    {"app": "opencodex-hub-accounts", "updatedAt": "2026-10-19T03:15:00Z", "state": {
      "schemaVersion": 2, "hub": "hub-mac", "host": "client-mac", "fetchedAt": "2026-10-19T03:14:58Z",
      "accounts": [{"idSuffix": "4d1e", "label": "a***e@example.com", "active": true}],
      "providers": {
        "anthropic": {"switchable": true, "switchReason": null, "accounts": [
          {"idSuffix": "4d1e", "label": "a***e@example.com", "email": "a***e@example.com", "active": true,
           "paused": false, "needsReauth": false, "health": "Healthy", "quotaUnavailable": false,
           "quota": {"fiveHourPercent": 13, "fiveHourResetAt": 1792398600000, "weeklyPercent": 24,
                     "weeklyResetAt": 1792861200000,
                     "customWindows": [{"label": "Fable", "percent": 5, "resetAt": 1792861200493}],
                     "updatedAt": 1792386686100}},
          {"idSuffix": "5592", "label": "b***b@example.com", "email": "b***b@example.com", "active": false,
           "paused": false, "needsReauth": false, "health": "Healthy", "quotaUnavailable": false,
           "quota": {"fiveHourPercent": 0, "weeklyPercent": 100, "updatedAt": 1792386347723}},
          {"idSuffix": "ee00", "label": "c***c@example.com", "email": "c***c@example.com", "active": false,
           "paused": true, "needsReauth": false, "health": "Healthy", "quotaUnavailable": false, "quota": null}
        ]},
        "openai": {"switchable": false, "switchReason": "Automation on hub-mac uses this pool.", "accounts": [
          {"idSuffix": "0f0f", "label": "go", "email": "b***b@example.com", "active": false, "paused": false,
           "needsReauth": false, "health": "Healthy", "quotaUnavailable": false,
           "quota": {"monthlyPercent": 0, "monthlyResetAt": 1794978623000, "updatedAt": 1792386000000}},
          {"idSuffix": "1a2b", "label": "pro", "email": "a***e@example.com", "active": true, "paused": false,
           "needsReauth": false, "health": "Healthy", "quotaUnavailable": false,
           "quota": {"weeklyPercent": 51, "weeklyResetAt": 1792889538000, "updatedAt": 1792386000000}}
        ]},
        "xai": {"switchable": true, "switchReason": null, "accounts": [
          {"idSuffix": "9999", "label": "b***b@example.com", "email": "b***b@example.com", "active": false,
           "paused": false, "needsReauth": false, "health": "Healthy", "quotaUnavailable": false,
           "quota": {"weeklyPercent": 0, "weeklyResetAt": 1792733805850, "updatedAt": 1792386505019}},
          {"idSuffix": "7777", "label": "a***e@example.com", "email": "a***e@example.com", "active": true,
           "paused": false, "needsReauth": true, "health": "Reauthentication required", "quotaUnavailable": true,
           "quota": {"weeklyPercent": 43, "updatedAt": 1792386505020}}
        ]}
      },
      "lastRequests": [
        {"requestId": "req-1", "from": "client-mac", "provider": "anthropic",
         "target": {"idSuffix": "5592", "email": "b***b@example.com"}, "result": "refused",
         "code": "superseded", "reason": "A newer request replaced this one.", "at": "2026-10-19T03:14:00Z"},
        {"requestId": "req-2", "from": "client-mac", "provider": "xai",
         "target": {"idSuffix": "9999", "email": "b***b@example.com"}, "result": "done",
         "code": "switched", "reason": null, "at": "2026-10-19T03:14:30Z"},
        {"requestId": "../bad", "result": "done"}
      ]
    }}
    """#

    static let updatedAt = Date(timeIntervalSince1970: 1_792_379_700) // 2026-10-19T03:15:00Z

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencodex-hub-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeSnapshot(_ text: String = Self.snapshotV2, in directory: URL) throws -> String {
        let url = directory.appendingPathComponent("opencodex-hub-accounts.json")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    /// A fake `ocx` that reports the hub role, prints `list-<provider>.json` for `account list` and a receipt for
    /// `account use`.
    private func makeFakeOCX(in directory: URL, lists: [String: String], body: String? = nil) throws -> String {
        for (provider, list) in lists {
            try list.write(
                to: directory.appendingPathComponent("list-\(provider).json"),
                atomically: true,
                encoding: .utf8)
        }
        let url = directory.appendingPathComponent("ocx")
        let script = """
        DIR='\(directory.path)'
        printf '%s\\n' "$*" >> "$DIR/ocx.calls"
        \(body ?? #"""
        case "$1 $2" in
          "status --json") echo '{"schemaVersion":1,"runtimeRole":"hub"}' ;;
          "account list") cat "$DIR/list-$3.json" ;;
          "account use") printf '{"ok":true,"provider":"%s","type":"oauth","activeId":"%s"}\n' "$3" "$4" ;;
          *) exit 64 ;;
        esac
        """#)
        """
        try FakeExecutable.install(script, at: url)
        return url.path
    }

    private func calls(_ executable: String) -> [String] {
        ((try? String(contentsOfFile: executable + ".calls", encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
    }

    // MARK: Snapshot parsing

    @Test
    func `schema 2 snapshot gives each provider its own pool, quota windows and switchability`() throws {
        let data = Data(Self.snapshotV2.utf8)
        let anthropic = try OpenCodexHubPoolParser.parseSnapshot(data, provider: .anthropic)
        #expect(anthropic.pool.origin == .snapshot(hubName: "hub-mac", updatedAt: Self.updatedAt))
        #expect(anthropic.fetchedAt == Date(timeIntervalSince1970: 1_792_379_698))
        #expect(anthropic.pool.switchable)
        #expect(anthropic.pool.accounts.map(\.idSuffix) == ["4d1e", "5592", "ee00"])
        let first = anthropic.pool.accounts[0]
        #expect(first.isActive)
        #expect(first.quota.fiveHour == OpenCodexHubQuotaWindow(
            usedPercent: 13, resetsAt: Date(timeIntervalSince1970: 1_792_398_600)))
        #expect(first.quota.weekly?.usedPercent == 24)
        #expect(first.quota.custom.map(\.label) == ["Fable"])
        #expect(first.quota.updatedAt == Date(timeIntervalSince1970: 1_792_386_686.1))
        #expect(anthropic.pool.accounts[1].isNearLimit)
        #expect(anthropic.pool.accounts[2].isPaused)
        #expect(anthropic.pool.lastRequests.map(\.requestID) == ["req-1"])
        #expect(anthropic.pool.lastRequests.first?.code == "superseded")

        let openai = try OpenCodexHubPoolParser.parseSnapshot(data, provider: .openai).pool
        #expect(!openai.switchable)
        #expect(openai.switchReason == "Automation on hub-mac uses this pool.")
        #expect(openai.activeAccount?.idSuffix == "1a2b")
        #expect(openai.activeAccount?.displayAlias == "pro")
        #expect(openai.accounts[0].quota.monthly == OpenCodexHubQuotaWindow(
            usedPercent: 0, resetsAt: Date(timeIntervalSince1970: 1_794_978_623)))
        #expect(openai.accounts[0].quota.weekly == nil)
        #expect(openai.accounts[1].quota.weekly?.usedPercent == 51)
        #expect(openai.lastRequests.isEmpty)

        let xai = try OpenCodexHubPoolParser.parseSnapshot(data, provider: .xai).pool
        #expect(xai.switchable)
        #expect(xai.accounts.map(\.email) == ["b***b@example.com", "a***e@example.com"])
        #expect(xai.accounts[1].requiresReauthentication)
        #expect(xai.accounts[1].quotaUnavailable)
        #expect(xai.lastRequests.map(\.outcome) == [.done])
    }

    @Test
    func `schema 1 snapshot is the read only Anthropic pool`() throws {
        let snapshot = #"""
        {"app": "opencodex-hub-accounts", "updatedAt": "2026-10-19T03:15:00Z", "state": {
          "schemaVersion": 1, "hub": "hub-mac",
          "accounts": [{"idSuffix": "4d1e", "label": "a***e@example.com", "active": true,
                        "quota": {"weeklyPercent": 20}}]}}
        """#
        let data = Data(snapshot.utf8)
        let pool = try OpenCodexHubPoolParser.parseSnapshot(data, provider: .anthropic).pool
        #expect(!pool.switchable)
        #expect(pool.accounts.map(\.email) == ["a***e@example.com"])
        #expect(throws: OpenCodexHubPoolError.providerMissing(.openai)) {
            try OpenCodexHubPoolParser.parseSnapshot(data, provider: .openai)
        }
        #expect(throws: OpenCodexHubPoolError.providerMissing(.xai)) {
            try OpenCodexHubPoolParser.parseSnapshot(data, provider: .xai)
        }
    }

    @Test
    func `the Claude adapter reads the schema 2 pool and switches by request except to paused accounts`() throws {
        let result = try OpenCodexAccountListParser.parseSnapshot(Data(Self.snapshotV2.utf8))
        #expect(result.list.supportsAccountSwitching)
        #expect(result.list.remoteCopy?.isSwitchable == true)
        #expect(result.list.remoteCopy?.managerName == "hub-mac")
        #expect(result.accountIDs.isEmpty)
        let accounts = ClaudeSwapAccountProjection.accountSnapshots(from: result.list, source: .openCodex)
        #expect(accounts.map(\.canActivate) == [false, true, false])
    }

    @Test
    func `snapshot older than five minutes is stale and a live list never is`() throws {
        let pool = try OpenCodexHubPoolParser.parseSnapshot(Data(Self.snapshotV2.utf8), provider: .xai).pool
        #expect(!pool.isStale(now: Self.updatedAt.addingTimeInterval(4 * 60)))
        #expect(pool.isStale(now: Self.updatedAt.addingTimeInterval(5 * 60 + 1)))
        let undated = OpenCodexHubPool(
            provider: .xai, accounts: [], switchable: true, origin: .snapshot(hubName: nil, updatedAt: nil))
        #expect(undated.isStale())
        let live = OpenCodexHubPool(provider: .xai, accounts: [], switchable: true, origin: .hubLocal)
        #expect(!live.isStale(now: .distantFuture))
    }

    // MARK: Switch requests

    @Test
    func `request file is written atomically with the hub's fields`() throws {
        let directory = try self.makeDirectory()
        let requestsDirectory = directory.appendingPathComponent(OpenCodexHubSwitchRequestWriter.requestsDirectoryName)
        let request = OpenCodexHubSwitchRequest(
            requestID: "6F1C2A4E-1B2C-4D5E-8F90-0123456789AB",
            provider: .xai,
            targetIDSuffix: "9999",
            targetEmail: "b***b@example.com",
            requestedAt: Date(timeIntervalSince1970: 1_792_379_745))
        let url = try OpenCodexHubSwitchRequestWriter.write(request, to: requestsDirectory)

        #expect(url.lastPathComponent == "6F1C2A4E-1B2C-4D5E-8F90-0123456789AB.json")
        let files = try FileManager.default.contentsOfDirectory(atPath: requestsDirectory.path)
        #expect(files == ["6F1C2A4E-1B2C-4D5E-8F90-0123456789AB.json"])
        let data = try Data(contentsOf: url)
        #expect(data.count <= OpenCodexHubSwitchRequest.maximumFileBytes)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == [
            "schemaVersion", "requestId", "provider", "targetIdSuffix", "targetEmail", "requestedAt",
        ])
        #expect(object["schemaVersion"] as? Int == 1)
        #expect(object["requestId"] as? String == request.requestID)
        #expect(object["provider"] as? String == "xai")
        #expect(object["targetIdSuffix"] as? String == "9999")
        #expect(object["targetEmail"] as? String == "b***b@example.com")
        #expect(object["requestedAt"] as? String == "2026-10-19T03:15:45Z")
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }

    @Test
    func `request ids follow the hub's pattern`() throws {
        #expect(OpenCodexHubSwitchRequest.isValidRequestID(UUID().uuidString))
        #expect(OpenCodexHubSwitchRequest.isValidRequestID(String(repeating: "a", count: 64)))
        #expect(!OpenCodexHubSwitchRequest.isValidRequestID(String(repeating: "a", count: 65)))
        #expect(!OpenCodexHubSwitchRequest.isValidRequestID(""))
        #expect(!OpenCodexHubSwitchRequest.isValidRequestID("../escape"))
        #expect(!OpenCodexHubSwitchRequest.isValidRequestID("a.b"))
        #expect(!OpenCodexHubSwitchRequest.isValidRequestID("ä"))

        let directory = try self.makeDirectory()
        let bad = OpenCodexHubSwitchRequest(
            requestID: "../escape", provider: .anthropic, targetIDSuffix: "5592", targetEmail: "b***b@example.com")
        #expect(throws: OpenCodexHubRequestError.invalidRequestID) {
            try OpenCodexHubSwitchRequestWriter.write(bad, to: directory)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test
    func `requests are refused locally when the pool is not switchable or the target is paused`() throws {
        let directory = try self.makeDirectory()
        let data = Data(Self.snapshotV2.utf8)
        let openai = try OpenCodexHubPoolParser.parseSnapshot(data, provider: .openai).pool
        #expect(!openai.canSwitch(to: openai.accounts[0]))
        #expect(throws: OpenCodexHubReaderError.switchNotAllowed("Automation on hub-mac uses this pool.")) {
            try OpenCodexHubReader.requestSwitch(
                pool: openai, idSuffix: "0f0f", email: "b***b@example.com", requestsDirectory: directory)
        }
        let anthropic = try OpenCodexHubPoolParser.parseSnapshot(data, provider: .anthropic).pool
        #expect(throws: OpenCodexHubReaderError.switchNotAllowed(nil)) {
            try OpenCodexHubReader.requestSwitch(
                pool: anthropic, idSuffix: "ee00", email: "c***c@example.com", requestsDirectory: directory)
        }
        #expect(throws: OpenCodexHubReaderError.accountNotFound) {
            try OpenCodexHubReader.requestSwitch(
                pool: anthropic, idSuffix: "5592", email: "someone@else.example", requestsDirectory: directory)
        }
        #expect(try OpenCodexHubReader.requestSwitch(
            pool: anthropic, idSuffix: "4d1e", email: "a***e@example.com", requestsDirectory: directory)
            == .alreadyActive)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)

        // Switching to a full account is allowed; the hub may move away again.
        let outcome = try OpenCodexHubReader.requestSwitch(
            pool: anthropic,
            idSuffix: "5592",
            email: "b***b@example.com",
            requestsDirectory: directory,
            requestID: "req-3")
        #expect(outcome == .requested(OpenCodexHubSwitchRequest(
            requestID: "req-3",
            provider: .anthropic,
            targetIDSuffix: "5592",
            targetEmail: "b***b@example.com",
            requestedAt: outcomeDate(outcome))))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["req-3.json"])
    }

    @Test
    func `a pending request resolves from lastRequests, the active account or expiry`() throws {
        let data = Data(Self.snapshotV2.utf8)
        let anthropic = try OpenCodexHubPoolParser.parseSnapshot(data, provider: .anthropic).pool
        let refused = OpenCodexHubPendingSwitch(request: OpenCodexHubSwitchRequest(
            requestID: "req-1", provider: .anthropic, targetIDSuffix: "5592", targetEmail: "b***b@example.com",
            requestedAt: Self.updatedAt))
        #expect(refused.resolution(in: anthropic, now: Self.updatedAt)
            == .refused(code: "superseded", reason: "A newer request replaced this one."))

        let becameActive = OpenCodexHubPendingSwitch(request: OpenCodexHubSwitchRequest(
            requestID: "req-9", provider: .anthropic, targetIDSuffix: "4d1e", targetEmail: "a***e@example.com",
            requestedAt: Self.updatedAt))
        #expect(becameActive.resolution(in: anthropic, now: Self.updatedAt) == .done)

        let waiting = OpenCodexHubPendingSwitch(request: OpenCodexHubSwitchRequest(
            requestID: "req-8", provider: .anthropic, targetIDSuffix: "5592", targetEmail: "b***b@example.com",
            requestedAt: Self.updatedAt))
        #expect(waiting.resolution(in: anthropic, now: Self.updatedAt.addingTimeInterval(60)) == .pending)
        #expect(waiting.resolution(in: anthropic, now: Self.updatedAt.addingTimeInterval(12 * 60)) == .expired)
    }

    // MARK: Hub-local and client paths

    static let liveOpenAI = #"""
    {"accounts": [
      {"provider": "openai", "type": "codex", "id": "acct0f0f", "label": "go", "email": "b***b@example.com",
       "plan": "go", "active": false, "needsReauth": false, "health": "Healthy", "paused": false,
       "quota": {"monthlyPercent": 0, "monthlyResetAt": 1794978623}},
      {"provider": "openai", "type": "codex", "id": "acct-pro-0001a2b", "label": "pro",
       "email": "a***e@example.com", "plan": "pro", "active": true, "needsReauth": false,
       "health": "Healthy", "paused": false, "quota": {"weeklyPercent": 51, "weeklyResetAt": 1792889538}}
    ], "notes": []}
    """#

    static let liveXAI = #"""
    {"accounts": [
      {"provider": "xai", "type": "oauth", "id": "000000000000000000000000000x9999", "label": "b***b@example.com",
       "email": "b***b@example.com", "active": false, "health": "Healthy",
       "quota": {"weeklyPercent": 0, "weeklyResetAt": 1792733805850, "updatedAt": 1792386505019},
       "quotaUnavailable": false},
      {"provider": "xai", "type": "oauth", "id": "000000000000000000000000000x7777", "label": "a***e@example.com",
       "email": "a***e@example.com", "active": true, "health": "Healthy",
       "quota": {"weeklyPercent": 43, "weeklyResetAt": 1792554588277, "updatedAt": 1792386505020},
       "quotaUnavailable": false}
    ], "notes": []}
    """#

    @Test
    func `on the hub OpenAI and xAI pools are read and switched through ocx`() async throws {
        let directory = try self.makeDirectory()
        let ocx = try self.makeFakeOCX(in: directory, lists: ["openai": Self.liveOpenAI, "xai": Self.liveXAI])

        let openai = try await OpenCodexHubReader.readPool(provider: .openai, executablePath: ocx, snapshotPath: nil)
        #expect(openai.isHubLocal)
        #expect(openai.switchable)
        #expect(openai.accounts.map(\.idSuffix) == ["0f0f", "1a2b"])
        #expect(openai.accounts[0].quota.monthly?.resetsAt == Date(timeIntervalSince1970: 1_794_978_623))

        let xaiOutcome = try await OpenCodexHubReader.switchAccount(
            provider: .xai,
            idSuffix: "9999",
            email: "b***b@example.com",
            executablePath: ocx,
            snapshotPath: nil)
        #expect(xaiOutcome == .switched)
        let openaiOutcome = try await OpenCodexHubReader.switchAccount(
            provider: .openai,
            idSuffix: "0f0f",
            email: "b***b@example.com",
            executablePath: ocx,
            snapshotPath: nil)
        #expect(openaiOutcome == .switched)
        #expect(self.calls(ocx) == [
            "status --json",
            "account list openai --quota --json",
            "account list xai --quota --json",
            "account use xai 000000000000000000000000000x9999 --json",
            "account list openai --quota --json",
            "account use openai acct0f0f --json",
        ])
    }

    /// `ocx account list openai` lists the Codex App's own login as `__main__` next to `chatgpt-<epoch ms>`
    /// and 32-hex ids (opencodex on the hub, 2026-10-19).
    static let liveOpenAIWithMainLogin = #"""
    {"accounts": [
      {"provider": "openai", "type": "codex", "id": "__main__", "label": "main", "email": "m***n@example.com",
       "active": false, "needsReauth": false, "health": "Healthy", "paused": false,
       "quota": {"weeklyPercent": 12}},
      {"provider": "openai", "type": "codex", "id": "chatgpt-1791743623093", "label": "pro",
       "email": "a***e@example.com", "active": true, "health": "Healthy", "paused": false,
       "quota": {"weeklyPercent": 51}},
      {"provider": "openai", "type": "codex", "id": "978bdedac54d52d7c63cff74d0904d1e",
       "email": "c***c@example.com", "active": false, "health": "Healthy", "quota": {"weeklyPercent": 3}}
    ], "notes": []}
    """#

    @Test
    func `the Codex App login and opencodex id forms are switch targets on the hub`() async throws {
        let directory = try self.makeDirectory()
        let ocx = try self.makeFakeOCX(in: directory, lists: ["openai": Self.liveOpenAIWithMainLogin])

        let live = try OpenCodexHubPoolParser.parseLiveList(Data(Self.liveOpenAIWithMainLogin.utf8), provider: .openai)
        #expect(live.accountIDs == ["__main__", "chatgpt-1791743623093", "978bdedac54d52d7c63cff74d0904d1e"])
        #expect(live.pool.accounts.map(\.idSuffix) == ["in__", "3093", "4d1e"])
        #expect(live.pool.accounts.map { live.pool.canSwitch(to: $0) } == [true, false, true])

        let outcome = try await OpenCodexHubReader.switchAccount(
            provider: .openai,
            idSuffix: "in__",
            email: "m***n@example.com",
            executablePath: ocx,
            snapshotPath: nil)
        #expect(outcome == .switched)
        #expect(self.calls(ocx) == [
            "status --json",
            "account list openai --quota --json",
            "account use openai __main__ --json",
        ])
    }

    @Test(arguments: [
        "--all", "-x", "has space", "tab\tid", "line\nbreak", "nul\u{0}id", "nön-ascii",
        String(repeating: "a", count: 129), "",
    ])
    func `an id ocx account use cannot take keeps its row without a switch target`(id: String) throws {
        let row: [String: Any] = ["provider": "openai", "id": id, "email": "b***b@example.com", "active": false]
        let list: [String: Any] = ["accounts": [
            row,
            ["provider": "openai", "id": "__main__", "email": "a***e@example.com", "active": true],
        ]]
        let data = try JSONSerialization.data(withJSONObject: list)
        let live = try OpenCodexHubPoolParser.parseLiveList(data, provider: .openai)
        #expect(live.accountIDs == [nil, "__main__"])
        #expect(live.pool.accounts.map(\.email) == ["b***b@example.com", "a***e@example.com"])
        #expect(live.pool.accounts[0].idSuffix == nil)
        #expect(!live.pool.canSwitch(to: live.pool.accounts[0]))
        #expect(live.pool.activeAccount?.idSuffix == "in__")
    }

    @Test
    func `a repeated id or a row without an id does not fail the pool`() throws {
        let list = #"""
        {"accounts": [
          {"provider": "openai", "id": "chatgpt-1", "email": "a***e@example.com", "active": true},
          {"provider": "openai", "id": "chatgpt-1", "email": "b***b@example.com", "active": false},
          {"provider": "openai", "email": "c***c@example.com", "active": false},
          {"provider": "openai", "id": 42, "email": "d***d@example.com", "active": false}
        ]}
        """#
        let live = try OpenCodexHubPoolParser.parseLiveList(Data(list.utf8), provider: .openai)
        #expect(live.accountIDs == ["chatgpt-1", nil, nil, nil])
        #expect(live.pool.accounts.count == 4)
        #expect(live.pool.accounts.filter { live.pool.canSwitch(to: $0) }.isEmpty)
    }

    @Test
    func `snapshot suffixes of opencodex ids address requests`() throws {
        #expect(OpenCodexHubPoolParser.isValidIDSuffix("in__"))
        #expect(OpenCodexHubPoolParser.isValidIDSuffix("-123"))
        #expect(!OpenCodexHubPoolParser.isValidIDSuffix("a b"))
        #expect(!OpenCodexHubPoolParser.isValidIDSuffix(String(repeating: "a", count: 17)))
    }

    @Test
    func `without a reported role the pool comes from the snapshot and a switch leaves a request`() async throws {
        let directory = try self.makeDirectory()
        // An opencodex that answers nothing useful (no role, no list) is not treated as the hub.
        let ocx = try self.makeFakeOCX(in: directory, lists: [:], body: #"echo "Error: not_found" >&2"#)
        let snapshotPath = try self.writeSnapshot(in: directory)
        let now = Self.updatedAt.addingTimeInterval(60)

        let xai = try await OpenCodexHubReader.readPool(
            provider: .xai, executablePath: ocx, snapshotPath: snapshotPath, now: now)
        #expect(!xai.isHubLocal)
        #expect(xai.hubName == "hub-mac")

        let outcome = try await OpenCodexHubReader.switchAccount(
            provider: .xai,
            idSuffix: "9999",
            email: "b***b@example.com",
            executablePath: ocx,
            snapshotPath: snapshotPath,
            now: now)
        guard case let .requested(request) = outcome else {
            Issue.record("expected a request, got \(outcome)")
            return
        }
        let requests = directory.appendingPathComponent("opencodex-hub-requests")
        #expect(try FileManager.default.contentsOfDirectory(atPath: requests.path) == ["\(request.requestID).json"])
        // The role is asked once and cached; no list and no `account use` run off the hub.
        #expect(self.calls(ocx) == ["status --json"])

        await #expect(throws: OpenCodexHubReaderError.switchNotAllowed("Automation on hub-mac uses this pool.")) {
            _ = try await OpenCodexHubReader.switchAccount(
                provider: .openai,
                idSuffix: "0f0f",
                email: "b***b@example.com",
                executablePath: ocx,
                snapshotPath: snapshotPath,
                now: now)
        }
        await #expect(throws: OpenCodexHubReaderError.snapshotNotCurrent) {
            _ = try await OpenCodexHubReader.switchAccount(
                provider: .xai,
                idSuffix: "9999",
                email: "b***b@example.com",
                executablePath: ocx,
                snapshotPath: snapshotPath,
                now: now.addingTimeInterval(OpenCodexHubPool.staleInterval))
        }
        await #expect(throws: OpenCodexHubReaderError.noHubSource("opencodex did not report this Mac's role")) {
            _ = try await OpenCodexHubReader.readPool(provider: .xai, executablePath: ocx, snapshotPath: nil)
        }
    }

    @Test
    func `the Claude adapter asks the hub to switch from a linked Mac`() async throws {
        let directory = try self.makeDirectory()
        let ocx = try self.makeFakeOCX(in: directory, lists: [:], body: #"""
        case "$1 $2" in
          "status --json") echo '{"schemaVersion":1,"runtimeRole":"client"}' ;;
          *) echo "Error: not_found" >&2; exit 1 ;;
        esac
        """#)
        let snapshotPath = try self.writeSnapshot(in: directory)
        let now = Self.updatedAt.addingTimeInterval(60)
        let result = try await OpenCodexAccountReader.switchAccount(
            executablePath: ocx,
            accountNumber: 2,
            expectedEmail: "b***b@example.com",
            snapshotPath: snapshotPath,
            now: now)
        #expect(result.reason == "requested")
        #expect(!result.switched)
        let request = try #require(result.hubRequest)
        #expect(request.provider == .anthropic)
        #expect(request.targetIDSuffix == "5592")
        let requests = directory.appendingPathComponent("opencodex-hub-requests")
        #expect(FileManager.default.fileExists(atPath: requests.appendingPathComponent(request.fileName).path))

        await #expect(throws: OpenCodexAccountListError.accountChanged(slot: 2)) {
            _ = try await OpenCodexAccountReader.switchAccount(
                executablePath: ocx,
                accountNumber: 2,
                expectedEmail: "someone@else.example",
                snapshotPath: snapshotPath,
                now: now)
        }
        #expect(self.calls(ocx) == ["status --json"])
    }

    @Test
    func `hub accounts project onto provider lanes with their durations`() throws {
        let data = Data(Self.snapshotV2.utf8)
        let openai = try OpenCodexHubPoolParser.parseSnapshot(data, provider: .openai).pool
        let active = try #require(openai.activeAccount)
        let snapshot = OpenCodexHubUsageProjection.snapshot(for: active, provider: .openai, fallbackUpdatedAt: .now)
        #expect(snapshot.primary?.usedPercent == 51)
        #expect(snapshot.primary?.windowMinutes == 7 * 24 * 60)
        #expect(snapshot.secondary == nil)
        #expect(snapshot.identity?.providerID == UsageProvider.codex.instanceID)
        #expect(snapshot.identity?.accountEmail == "a***e@example.com")
        #expect(snapshot.identity?.accountOrganization == "pro")

        let monthly = OpenCodexHubUsageProjection.snapshot(
            for: openai.accounts[0], provider: .openai, fallbackUpdatedAt: .now)
        #expect(monthly.primary?.windowMinutes == 30 * 24 * 60)

        let anthropic = try OpenCodexHubPoolParser.parseSnapshot(data, provider: .anthropic).pool
        let claude = OpenCodexHubUsageProjection.snapshot(
            for: anthropic.accounts[0], provider: .anthropic, fallbackUpdatedAt: .now)
        #expect(claude.primary?.windowMinutes == 5 * 60)
        #expect(claude.secondary?.windowMinutes == 7 * 24 * 60)
        #expect(claude.extraRateWindows?.map(\.title) == ["Fable"])
    }
}

private func outcomeDate(_ outcome: OpenCodexHubSwitchOutcome) -> Date {
    if case let .requested(request) = outcome { return request.requestedAt }
    return .distantPast
}
