import Foundation
import Testing
@testable import CodexBarCore

/// A Mac linked to an opencodex hub (opencodex 2.84+ "Remote Link Child") answers `ocx account list` from the
/// hub's cache but refuses `ocx account use`. CodexBar must take the role from `ocx status --json`, not from a
/// list coming back: the child reads the hub's snapshot and switches by request, never with `ocx account use`.
struct OpenCodexHubLinkChildTests {
    /// The hub's snapshot as a linked Mac receives it: OpenAI is switched only on the hub.
    static func snapshot(updatedAt: Date) -> String {
        let stamp = ISO8601DateFormatter().string(from: updatedAt)
        return #"""
        {"app": "opencodex-hub-accounts", "updatedAt": "\#(stamp)", "state": {
          "schemaVersion": 2, "hub": "hub-mac", "host": "child-mac", "fetchedAt": "\#(stamp)",
          "accounts": [],
          "providers": {
            "anthropic": {"switchable": true, "switchReason": null, "accounts": [
              {"idSuffix": "4d1e", "label": "a***e@example.com", "email": "a***e@example.com", "active": true},
              {"idSuffix": "5592", "label": "b***b@example.com", "email": "b***b@example.com", "active": false}
            ]},
            "openai": {"switchable": false, "switchReason": "Automation on hub-mac uses this pool.", "accounts": [
              {"idSuffix": "0f0f", "label": "go", "email": "b***b@example.com", "active": false},
              {"idSuffix": "1a2b", "label": "pro", "email": "a***e@example.com", "active": true}
            ]},
            "xai": {"switchable": true, "switchReason": null, "accounts": [
              {"idSuffix": "9999", "label": "b***b@example.com", "email": "b***b@example.com", "active": false},
              {"idSuffix": "7777", "label": "a***e@example.com", "email": "a***e@example.com", "active": true}
            ]}
          },
          "lastRequests": [
            {"requestId": "req-2", "from": "child-mac", "provider": "xai",
             "target": {"idSuffix": "9999", "email": "b***b@example.com"}, "result": "refused",
             "code": "superseded", "reason": "A newer request replaced this one.", "at": "\#(stamp)"}
          ]
        }}
        """#
    }

    /// What `ocx account list <provider> --json` prints on the child (the hub's cached pool).
    static let childList = #"""
    {"accounts": [
      {"provider": "%PROVIDER%", "id": "chatgpt-1791743620f0f", "email": "b***b@example.com", "active": false,
       "health": "Healthy", "quota": {"weeklyPercent": 3}},
      {"provider": "%PROVIDER%", "id": "978bdedac54d52d7c63cff74d09041a2b", "email": "a***e@example.com",
       "active": true, "health": "Healthy", "quota": {"weeklyPercent": 51}}
    ], "notes": []}
    """#

    /// opencodex's refusal, without the apostrophe of "Home's" so it fits the fake's single-quoted echo.
    static let useRefusal = "This machine is a Remote Link Child managed by Home hub-mac (link lnk_0123456789abcdef). "
        + "This management command runs on the Home, not on this Child. No request was sent."

    private struct Fixture {
        let directory: URL
        let ocx: String

        var snapshotPath: String {
            self.directory.appendingPathComponent("opencodex-hub-accounts.json").path
        }

        var requestFiles: [String] {
            let requests = self.directory.appendingPathComponent("opencodex-hub-requests")
            return (try? FileManager.default.contentsOfDirectory(atPath: requests.path)) ?? []
        }

        var calls: [String] {
            ((try? String(contentsOfFile: self.ocx + ".calls", encoding: .utf8)) ?? "")
                .split(separator: "\n").map(String.init)
        }

        func writeSnapshot(updatedAt: Date) throws {
            try OpenCodexHubLinkChildTests.snapshot(updatedAt: updatedAt)
                .write(toFile: self.snapshotPath, atomically: true, encoding: .utf8)
        }
    }

    /// A fake `ocx` reporting `role` (nil: no status document), listing every pool like a child does, and
    /// refusing `account use` the way opencodex refuses it on a link child.
    private func makeChild(
        role: String? = "client",
        listWorks: Bool = true,
        accountCount: Int = 2,
        includeQuota: Bool = true) throws -> Fixture
    {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencodex-link-child-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for provider in ["anthropic", "openai", "xai"] {
            var document = Self.childList.replacingOccurrences(of: "%PROVIDER%", with: provider)
            if accountCount > 2 || !includeQuota {
                var object = try #require(JSONSerialization.jsonObject(with: Data(document.utf8)) as? [String: Any])
                var accounts = try #require(object["accounts"] as? [[String: Any]])
                for index in 2..<accountCount {
                    accounts.append([
                        "provider": provider, "id": "synthetic-new-\(String(format: "%04x", index))",
                        "email": "n\(index)***w@example.com", "active": false,
                    ])
                }
                if !includeQuota {
                    accounts = accounts.map { row in
                        var copy = row
                        copy.removeValue(forKey: "quota")
                        return copy
                    }
                }
                object["accounts"] = accounts
                document = try #require(String(data: JSONSerialization.data(withJSONObject: object), encoding: .utf8))
            }
            try document
                .write(to: directory.appendingPathComponent("list-\(provider).json"), atomically: true, encoding: .utf8)
        }
        let status = role.map { #"printf '{"schemaVersion":1,"runtimeRole":"%s"}\n' '\#($0)'"# }
            ?? #"echo "Error: unknown command" >&2; exit 64"#
        let list = listWorks ? #"""
        if [ "$#" -ne 4 ] || [ "$4" != "--json" ]; then
          echo 'Remote Link Child: passive account list only; no request was sent' >&2
          exit 1
        fi
        cat "$DIR/list-$3.json"
        """# : #"echo "Error: not_found" >&2; exit 1"#
        let url = directory.appendingPathComponent("ocx")
        let script = """
        DIR='\(directory.path)'
        printf '%s\\n' "$*" >> "$DIR/ocx.calls"
        case "$1 $2" in
          "status --json") \(status) ;;
          "account list") \(list) ;;
          "account use") echo '\(Self.useRefusal)' >&2; exit 1 ;;
          *) exit 64 ;;
        esac
        """
        try FakeExecutable.install(script, at: url)
        return Fixture(directory: directory, ocx: url.path)
    }

    @Test
    func `a link child reads the current snapshot and keeps the hub's switch rules`() async throws {
        let child = try self.makeChild()
        try child.writeSnapshot(updatedAt: Date())

        let openai = try await OpenCodexHubReader.readPool(
            provider: .openai, executablePath: child.ocx, snapshotPath: child.snapshotPath)
        #expect(!openai.isHubLocal)
        #expect(!openai.switchable)
        #expect(openai.switchReason == "Automation on hub-mac uses this pool.")
        #expect(openai.hubName == "hub-mac")

        let xai = try await OpenCodexHubReader.readPool(
            provider: .xai, executablePath: child.ocx, snapshotPath: child.snapshotPath)
        #expect(xai.switchable)
        #expect(xai.lastRequests.map(\.requestID) == ["req-2"])

        let anthropic = try await ClaudeSwapAccountReader.readAccountList(
            executablePath: child.ocx, source: .openCodex, openCodexSnapshotPath: child.snapshotPath)
        #expect(anthropic.remoteCopy?.managerName == "hub-mac")
        #expect(anthropic.supportsAccountSwitching)

        // The role is asked once for the whole pass; the child's own list is not needed with a current snapshot.
        #expect(child.calls == ["status --json"])
    }

    @Test
    func `a link child switches by request and never runs account use`() async throws {
        let child = try self.makeChild()
        try child.writeSnapshot(updatedAt: Date())

        let outcome = try await OpenCodexHubReader.switchAccount(
            provider: .xai,
            idSuffix: "9999",
            email: "b***b@example.com",
            executablePath: child.ocx,
            snapshotPath: child.snapshotPath)
        guard case let .requested(request) = outcome else {
            Issue.record("expected a request, got \(outcome)")
            return
        }
        #expect(child.requestFiles == [request.fileName])

        let claude = try await ClaudeSwapAccountReader.switchAccount(
            executablePath: child.ocx,
            accountNumber: 2,
            source: .openCodex,
            expectedEmail: "b***b@example.com",
            openCodexSnapshotPath: child.snapshotPath)
        #expect(claude.reason == "requested")
        #expect(!claude.switched)
        #expect(child.requestFiles.count == 2)

        await #expect(throws: OpenCodexHubReaderError.switchNotAllowed("Automation on hub-mac uses this pool.")) {
            _ = try await OpenCodexHubReader.switchAccount(
                provider: .openai,
                idSuffix: "0f0f",
                email: "b***b@example.com",
                executablePath: child.ocx,
                snapshotPath: child.snapshotPath)
        }
        #expect(!child.calls.contains { $0.hasPrefix("account use") })
    }

    @Test
    func `without a current snapshot a link child shows its own list read only`() async throws {
        let child = try self.makeChild()
        try child.writeSnapshot(updatedAt: Date().addingTimeInterval(-OpenCodexHubPool.staleInterval - 60))

        let xai = try await OpenCodexHubReader.readPool(
            provider: .xai, executablePath: child.ocx, snapshotPath: child.snapshotPath)
        #expect(!xai.isHubLocal)
        #expect(!xai.switchable)
        #expect(xai.accounts.map(\.idSuffix) == ["0f0f", "1a2b"])
        #expect(xai.accounts.allSatisfy { !xai.canSwitch(to: $0) })

        let claude = try await ClaudeSwapAccountReader.readAccountList(
            executablePath: child.ocx, source: .openCodex, openCodexSnapshotPath: child.snapshotPath)
        #expect(!claude.supportsAccountSwitching)
        #expect(claude.remoteCopy != nil)
        #expect(claude.accounts.count == 2)

        // Switching from an out-of-date snapshot is refused locally instead of handing it to `ocx account use`.
        await #expect(throws: (any Error).self) {
            _ = try await OpenCodexHubReader.switchAccount(
                provider: .xai,
                idSuffix: "9999",
                email: "b***b@example.com",
                executablePath: child.ocx,
                snapshotPath: child.snapshotPath)
        }
        await #expect(throws: (any Error).self) {
            _ = try await ClaudeSwapAccountReader.switchAccount(
                executablePath: child.ocx,
                accountNumber: 2,
                source: .openCodex,
                expectedEmail: "b***b@example.com",
                openCodexSnapshotPath: child.snapshotPath)
        }
        #expect(child.requestFiles.isEmpty)
        #expect(!child.calls.contains { $0.hasPrefix("account use") })
    }

    @Test
    func `a link child without any snapshot lists read only and cannot switch`() async throws {
        let child = try self.makeChild()

        let openai = try await OpenCodexHubReader.readPool(
            provider: .openai, executablePath: child.ocx, snapshotPath: child.snapshotPath)
        #expect(!openai.isHubLocal)
        #expect(!openai.switchable)
        await #expect(throws: (any Error).self) {
            _ = try await OpenCodexHubReader.switchAccount(
                provider: .openai,
                idSuffix: "0f0f",
                email: "b***b@example.com",
                executablePath: child.ocx,
                snapshotPath: nil)
        }
        #expect(!child.calls.contains { $0.hasPrefix("account use") })
    }

    @Test(arguments: [3, 12, 20, 50], OpenCodexHubProvider.allCases)
    func `new hub accounts survive the client's quota refresh refusal at larger pool sizes`(
        count: Int, provider: OpenCodexHubProvider) async throws
    {
        let child = try self.makeChild(accountCount: count)
        try child.writeSnapshot(updatedAt: Date().addingTimeInterval(-OpenCodexHubPool.staleInterval - 60))
        let pool = try await OpenCodexHubReader.readPool(
            provider: provider, executablePath: child.ocx, snapshotPath: child.snapshotPath)
        #expect(pool.accounts.count == count)
        #expect(pool.accounts.last?.idSuffix == String(format: "%04x", count - 1))
        #expect(pool.accounts.last?.quota.isEmpty == true)
        #expect(pool.isLinkedCopy)
        #expect(!pool.switchable)
        #expect(pool.accounts.allSatisfy { !pool.canSwitch(to: $0) })
        #expect(child.calls == ["status --json", "account list \(provider.rawValue) --json"])
        #expect(child.requestFiles.isEmpty)
        let bytes = try Data(contentsOf: child.directory.appendingPathComponent("list-\(provider.rawValue).json"))
        #expect(bytes.count < OpenCodexHubReader.maxOutputBytes)
    }

    @Test
    func `a failed passive list preserves the stale snapshot timestamp`() async throws {
        let child = try self.makeChild(listWorks: false)
        let old = Date(timeIntervalSince1970: 1_800_000_000)
        try child.writeSnapshot(updatedAt: old)
        let pool = try await OpenCodexHubReader.readPool(
            provider: .anthropic,
            executablePath: child.ocx,
            snapshotPath: child.snapshotPath,
            now: old.addingTimeInterval(OpenCodexHubPool.staleInterval + 60))
        #expect(pool.accounts.count == 2)
        #expect(pool.snapshotUpdatedAt == old)
        #expect(pool.isStale(now: old.addingTimeInterval(OpenCodexHubPool.staleInterval + 60)))
        #expect(child.calls == ["status --json", "account list anthropic --json"])
    }

    @Test(arguments: ["matching", "changed-email", "ambiguous"])
    func `passive lists retain only uniquely matched dated quota without copying old account state`(
        scenario: String) async throws
    {
        let child = try self.makeChild(accountCount: 3, includeQuota: false)
        let old = Date(timeIntervalSince1970: 1_800_000_000)
        var document = try #require(JSONSerialization.jsonObject(
            with: Data(Self.snapshot(updatedAt: old).utf8)) as? [String: Any])
        var state = try #require(document["state"] as? [String: Any])
        var providers = try #require(state["providers"] as? [String: Any])
        let cached: [String: Any] = [
            "idSuffix": "0f0f", "email": scenario == "changed-email" ? "c***c@example.com" : "b***b@example.com",
            "active": false, "paused": true, "needsReauth": true,
            "quota": ["weeklyPercent": 0, "updatedAt": old.timeIntervalSince1970 * 1000],
        ]
        providers["anthropic"] = ["switchable": true, "accounts": scenario == "ambiguous" ? [cached, cached] : [cached]]
        state["providers"] = providers
        document["state"] = state
        try JSONSerialization.data(withJSONObject: document).write(to: URL(fileURLWithPath: child.snapshotPath))
        let pool = try await OpenCodexHubReader.readPool(
            provider: .anthropic,
            executablePath: child.ocx,
            snapshotPath: child.snapshotPath,
            now: old.addingTimeInterval(OpenCodexHubPool.staleInterval + 60))
        let first = try #require(pool.accounts.first)
        #expect(pool.accounts.count == 3)
        #expect(!first.isPaused)
        #expect(!first.needsReauth)
        #expect(!first.isActive)
        #expect(first.quota.isEmpty == (scenario != "matching"))
        if scenario == "matching" {
            #expect(first.quota.weekly?.usedPercent == 0)
            #expect(first.quota.updatedAt == old)
            #expect(first.quotaUnavailable)
        }
        #expect(pool.accounts.last?.quota.isEmpty == true)
        #expect(pool.isLinkedCopy)
    }

    @Test(arguments: [12, 20, 50])
    func `a large current snapshot can request its last Claude account without changing accounts locally`(
        count: Int) async throws
    {
        let child = try self.makeChild()
        let now = Date()
        let stamp = ISO8601DateFormatter().string(from: now)
        let accounts: [[String: Any]] = (0..<count).map { index in
            ["idSuffix": String(format: "%04x", index), "email": "a\(index)***e@example.com", "active": index == 0]
        }
        let document: [String: Any] = [
            "updatedAt": stamp,
            "state": [
                "schemaVersion": 2,
                "hub": "hub-mac",
                "fetchedAt": stamp,
                "providers": ["anthropic": ["switchable": true, "accounts": accounts]],
            ],
        ]
        try JSONSerialization.data(withJSONObject: document).write(to: URL(fileURLWithPath: child.snapshotPath))
        let outcome = try await OpenCodexHubReader.switchAccount(
            provider: .anthropic,
            idSuffix: String(format: "%04x", count - 1),
            email: "a\(count - 1)***e@example.com",
            executablePath: child.ocx,
            snapshotPath: child.snapshotPath)
        guard case let .requested(request) = outcome else {
            Issue.record("Expected a hub request for the last account")
            return
        }
        #expect(request.targetIDSuffix == String(format: "%04x", count - 1))
        #expect(child.requestFiles.count == 1)
        #expect(child.calls == ["status --json"])
    }
}
