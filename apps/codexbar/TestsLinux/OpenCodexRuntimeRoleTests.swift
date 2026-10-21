import Foundation
import Testing
@testable import CodexBarCore

/// The opencodex runtime role (`ocx status --json`), its cache, and the sources each role reads.
struct OpenCodexRuntimeRoleTests {
    // MARK: Status document

    @Test(arguments: [
        (#"{"schemaVersion":1,"runtimeRole":"hub","hub":{"dataToken":"redacted"}}"#, OpenCodexRuntimeRole.hub),
        (#"{"schemaVersion":1,"runtimeRole":"standalone"}"#, .standalone),
        (#"{"schemaVersion":1,"runtimeRole":"client","remoteHub":{"connected":true}}"#, .client),
        (#"{"schemaVersion":1,"runtimeRole":"unknown"}"#, .unknown),
        (#"{"schemaVersion":1,"runtimeRole":"relay"}"#, .unknown),
        (#"{"schemaVersion":1}"#, .unknown),
        (#"{"runtimeRole":1}"#, .unknown),
        ("Error: not_found", .unknown),
        ("", .unknown),
    ])
    func `the role comes only from runtimeRole`(document: String, role: OpenCodexRuntimeRole) {
        #expect(OpenCodexRuntimeRoleProbe.parseRole(Data(document.utf8)) == role)
    }

    @Test
    func `only a hub or a standalone install owns its pools`() {
        #expect(OpenCodexRuntimeRole.hub.ownsAccounts)
        #expect(OpenCodexRuntimeRole.standalone.ownsAccounts)
        #expect(!OpenCodexRuntimeRole.client.ownsAccounts)
        #expect(!OpenCodexRuntimeRole.unknown.ownsAccounts)
    }

    // MARK: Cache

    private final class ProbeLog: @unchecked Sendable {
        private let lock = NSLock()
        private var binaries: [String] = []
        var roles: [String: OpenCodexRuntimeRole] = [:]
        var delay: Duration = .zero

        func record(_ binary: String) {
            self.lock.withLock { self.binaries.append(binary) }
        }

        var calls: [String] {
            self.lock.withLock { self.binaries }
        }
    }

    private func makeCache(_ log: ProbeLog) -> OpenCodexRuntimeRoleCache {
        OpenCodexRuntimeRoleCache { binary in
            log.record(binary)
            if log.delay > .zero { try? await Task.sleep(for: log.delay) }
            return log.roles[binary] ?? .unknown
        }
    }

    @Test
    func `the role is asked once per executable for the cache lifetime`() async {
        let log = ProbeLog()
        log.roles = ["/hub/ocx": .hub, "/child/ocx": .client]
        let cache = self.makeCache(log)
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(await cache.role(forBinary: "/hub/ocx", now: start) == .hub)
        #expect(await cache.role(forBinary: "/hub/ocx", now: start.addingTimeInterval(60)) == .hub)
        #expect(await cache.role(forBinary: "/child/ocx", now: start) == .client)
        #expect(log.calls == ["/hub/ocx", "/child/ocx"])

        let later = start.addingTimeInterval(OpenCodexRuntimeRoleCache.knownRoleLifetime)
        #expect(await cache.role(forBinary: "/hub/ocx", now: later) == .hub)
        #expect(log.calls == ["/hub/ocx", "/child/ocx", "/hub/ocx"])

        await cache.invalidate(binary: "/child/ocx")
        #expect(await cache.role(forBinary: "/child/ocx", now: later) == .client)
        #expect(log.calls.count == 4)
    }

    @Test
    func `an unknown role is retried sooner and no executable starts nothing`() async {
        let log = ProbeLog()
        let cache = self.makeCache(log)
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(await cache.role(forBinary: nil, now: start) == .unknown)
        #expect(log.calls.isEmpty)

        #expect(await cache.role(forBinary: "/missing/ocx", now: start) == .unknown)
        #expect(await cache.role(forBinary: "/missing/ocx", now: start.addingTimeInterval(30)) == .unknown)
        #expect(log.calls.count == 1)
        let retry = start.addingTimeInterval(OpenCodexRuntimeRoleCache.unknownRoleLifetime)
        log.roles["/missing/ocx"] = .standalone
        #expect(await cache.role(forBinary: "/missing/ocx", now: retry) == .standalone)
        #expect(log.calls.count == 2)
    }

    @Test
    func `concurrent pools share one status run`() async {
        let log = ProbeLog()
        log.roles = ["/hub/ocx": .hub]
        log.delay = .milliseconds(50)
        let cache = self.makeCache(log)
        let now = Date()
        let roles = await withTaskGroup(of: OpenCodexRuntimeRole.self) { group in
            for _ in 0..<3 {
                group.addTask { await cache.role(forBinary: "/hub/ocx", now: now) }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(roles == [.hub, .hub, .hub])
        #expect(log.calls == ["/hub/ocx"])
    }

    // MARK: Sources by role

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencodex-role-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// A fake `ocx` answering `status --json` with `role` and listing `list` for every pool.
    private func makeOCX(role: String, in directory: URL) throws -> String {
        let list = directory.appendingPathComponent("list.json")
        try OpenCodexHubLinkChildTests.childList.replacingOccurrences(of: "%PROVIDER%", with: "xai")
            .write(to: list, atomically: true, encoding: .utf8)
        let url = directory.appendingPathComponent("ocx")
        try FakeExecutable.install("""
        printf '%s\\n' "$*" >> '\(url.path).calls'
        case "$1 $2" in
          "status --json") printf '{"schemaVersion":1,"runtimeRole":"%s"}\\n' '\(role)' ;;
          "account list") cat '\(list.path)' ;;
          "account use") printf '{"ok":true,"provider":"%s","type":"oauth","activeId":"%s"}\\n' "$3" "$4" ;;
          *) exit 64 ;;
        esac
        """, at: url)
        return url.path
    }

    @Test
    func `a standalone install reads and switches its own pool like the hub`() async throws {
        let directory = try self.makeDirectory()
        let ocx = try self.makeOCX(role: "standalone", in: directory)
        let cache = OpenCodexRuntimeRoleCache()

        let read = try await OpenCodexHubReader.read(
            provider: .xai, executablePath: ocx, snapshotPath: nil, roleCache: cache)
        guard case let .live(live) = read else {
            Issue.record("expected the live list, got \(read)")
            return
        }
        #expect(live.pool.isHubLocal)
        let outcome = try await OpenCodexHubReader.switchAccount(
            provider: .xai,
            idSuffix: "0f0f",
            email: "b***b@example.com",
            executablePath: ocx,
            snapshotPath: nil,
            roleCache: cache)
        #expect(outcome == .switched)
        let calls = try String(contentsOfFile: ocx + ".calls", encoding: .utf8)
        #expect(calls.split(separator: "\n").filter { $0 == "status --json" }.count == 1)
    }

    @Test
    func `a child pool read says it is a read only linked copy`() async throws {
        let directory = try self.makeDirectory()
        let ocx = try self.makeOCX(role: "client", in: directory)
        let cache = OpenCodexRuntimeRoleCache()
        let read = try await OpenCodexHubReader.read(
            provider: .xai, executablePath: ocx, snapshotPath: nil, roleCache: cache)
        guard case let .linkedCopy(pool) = read else {
            Issue.record("expected a linked copy, got \(read)")
            return
        }
        #expect(pool.isLinkedCopy)
        #expect(!pool.isStale())
        #expect(!pool.switchable)
        await #expect(throws: OpenCodexHubReaderError.snapshotNotCurrent) {
            _ = try await OpenCodexHubReader.switchAccount(
                provider: .xai,
                idSuffix: "0f0f",
                email: "b***b@example.com",
                executablePath: ocx,
                snapshotPath: nil,
                roleCache: cache)
        }
        await #expect(throws: OpenCodexAccountListError.snapshotNotCurrent) {
            _ = try await OpenCodexAccountReader.switchAccount(
                executablePath: ocx,
                accountNumber: 1,
                expectedEmail: nil,
                roleCache: cache)
        }
    }

    @Test
    func `without a role or a snapshot there is no hub source`() async throws {
        let directory = try self.makeDirectory()
        let missing = directory.appendingPathComponent("no-ocx").path
        let absentSnapshot = directory.appendingPathComponent("absent.json").path
        let cache = OpenCodexRuntimeRoleCache()

        await #expect(throws: OpenCodexHubReaderError.noHubSource("opencodex did not report this Mac's role")) {
            _ = try await OpenCodexHubReader.readPool(
                provider: .openai, executablePath: missing, snapshotPath: absentSnapshot, roleCache: cache)
        }
        await #expect(throws: OpenCodexHubReaderError.noHubSource("opencodex did not report this Mac's role")) {
            _ = try await OpenCodexHubReader.switchAccount(
                provider: .openai,
                idSuffix: "0f0f",
                email: "b***b@example.com",
                executablePath: missing,
                snapshotPath: nil,
                roleCache: cache)
        }
        // The Claude adapter keeps its own wording for the same situation.
        let claudeError = OpenCodexAccountListError.hubAccountsUnavailable("opencodex did not report this Mac's role")
        await #expect(throws: claudeError) {
            _ = try await OpenCodexAccountReader.readAccountList(
                executablePath: missing, snapshotPath: nil, roleCache: cache)
        }

        // An unknown role still reads a snapshot that exists, even an old one (shown as stale).
        let snapshotPath = directory.appendingPathComponent("snapshot.json").path
        let old = Date().addingTimeInterval(-3600)
        try OpenCodexHubLinkChildTests.snapshot(updatedAt: old)
            .write(toFile: snapshotPath, atomically: true, encoding: .utf8)
        let pool = try await OpenCodexHubReader.readPool(
            provider: .openai, executablePath: missing, snapshotPath: snapshotPath, roleCache: cache)
        #expect(pool.isStale())
        #expect(pool.switchReason == "Automation on hub-mac uses this pool.")
        await #expect(throws: OpenCodexHubReaderError.snapshotNotCurrent) {
            _ = try await OpenCodexHubReader.switchAccount(
                provider: .xai,
                idSuffix: "9999",
                email: "b***b@example.com",
                executablePath: missing,
                snapshotPath: snapshotPath,
                roleCache: cache)
        }
    }
}
