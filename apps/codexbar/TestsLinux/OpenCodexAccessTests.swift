import Foundation
import Testing
@testable import CodexBarCore

struct OpenCodexAccessTests {
    static let status = #"{"schemaVersion":1,"runtimeRole":"hub","proxy":{"running":true},"dashboard":{"url":"http://localhost:1234"},"token":"synthetic-secret"}"#
    static let row = #"{"id":"id-a","name":"same","prefix":"ocx_abc","createdAt":"2026-10-20T01:02:03.000Z"}"#

    @Test func `OpenCodexAccess projects status and refuses invalid fields`() throws {
        let status = try OpenCodexAccessParser.status(Data(Self.status.utf8))
        #expect(status.runtimeRole == .hub)
        #expect(status.proxyRunning)
        for raw in [
            "{}",
            Self.status.replacingOccurrences(of: "true", with: "1"),
            Self.status.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":true"),
        ] {
            #expect(throws: OpenCodexAccessError.invalidResponse) {
                try OpenCodexAccessParser.status(Data(raw.utf8))
            }
        }
    }

    @Test func `OpenCodexAccess distinguishes same names duplicate ids and usage absence`() throws {
        let rows = "[\(Self.row),\(Self.row.replacingOccurrences(of: "id-a", with: "id-b"))]"
        let list = try OpenCodexAccessParser.list(Data("{\"keys\":\(rows)}".utf8))
        #expect(list.keys.count == 2)
        #expect(list.keys[0].usage == .unavailable)
        #expect(throws: OpenCodexAccessError.invalidResponse) {
            try OpenCodexAccessParser.list(Data("{\"keys\":[\(Self.row),\(Self.row)]}".utf8))
        }
        #expect(throws: OpenCodexAccessError.outputTooLarge) {
            try OpenCodexAccessParser.list(Data(repeating: 32, count: 262_145))
        }
    }

    @Test func `OpenCodexAccess validates names before trimming controls and UTF16 length`() throws {
        #expect(try OpenCodexAccessName.validate("  hello  ") == "hello")
        for name in ["", " \nname", "--json", "—json", String(repeating: "😀", count: 33)] {
            #expect(throws: OpenCodexAccessError.invalidName) { try OpenCodexAccessName.validate(name) }
        }
    }

    @Test func `OpenCodexAccess secrets have redacted descriptions and exact create confirmation`() throws {
        let raw = #"{"id":"a","name":"new","key":"synthetic-secret","createdAt":"2026-10-20T01:02:03Z"}"#
        let result = try OpenCodexAccessParser.created(Data(raw.utf8), expectedName: "new")
        #expect(result.secret.reveal() == "synthetic-secret")
        #expect(!String(reflecting: result).contains("synthetic-secret"))
        #expect(throws: OpenCodexAccessError.invalidResponse) {
            try OpenCodexAccessParser.created(Data(raw.utf8), expectedName: "other")
        }
    }
}

private actor OpenCodexAccessScript: OpenCodexAccessTransport {
    var replies: [Result<Data, OpenCodexAccessError>]
    var calls: [[String]] = []
    init(_ replies: [Result<Data, OpenCodexAccessError>]) { self.replies = replies }
    func run(_ request: OpenCodexAccessRequest) async throws -> Data {
        self.calls.append(request.arguments)
        return try self.replies.removeFirst().get()
    }
}

extension OpenCodexAccessTests {
    @Test func `OpenCodexAccess blocks client stopped and unknown before management`() async throws {
        for (raw, error) in [
            (Self.status.replacingOccurrences(of: "hub", with: "client"), OpenCodexAccessError.unsupportedRole),
            (Self.status.replacingOccurrences(of: "hub", with: "unknown"), .unsupportedRole),
            (Self.status.replacingOccurrences(of: "true", with: "false"), .serverStopped),
        ] {
            let transport = OpenCodexAccessScript([.success(Data(raw.utf8))])
            let client = OpenCodexAccessClient(executablePath: "/fake/ocx", transport: transport, mutationGate: .init())
            await #expect(throws: error) { try await client.list() }
            #expect(await transport.calls == [["status", "--json"]])
        }
    }

    @Test func `OpenCodexAccess rechecks mutations and never retries uncertain results`() async throws {
        let transport = OpenCodexAccessScript([
            .success(Data(Self.status.utf8)), .success(Data("{\"success\":false,\"key\":\"synthetic-secret\"}".utf8)),
        ])
        let client = OpenCodexAccessClient(executablePath: "/fake/ocx", transport: transport, mutationGate: .init())
        await #expect(throws: OpenCodexAccessError.confirmationRequired) { try await client.revoke(id: "id-a") }
        #expect(await transport.calls == [["status", "--json"], ["access", "key", "remove", "id-a", "--yes", "--json"]])
    }

    @Test func `OpenCodexAccess fake subprocess bounds output and sanitizes errors`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let binary = directory.appendingPathComponent("ocx")
        try FakeExecutable.install("printf 'synthetic-secret'; printf 'synthetic-secret' >&2; exit 1", at: binary)
        let transport = OpenCodexAccessProcessTransport()
        let request = OpenCodexAccessRequest(binary: binary.path, arguments: [], mutation: false, maxOutputBytes: 4)
        await #expect(throws: OpenCodexAccessError.outputTooLarge) { try await transport.run(request) }
        let mutation = OpenCodexAccessRequest(binary: binary.path, arguments: [], mutation: true, maxOutputBytes: 4)
        await #expect(throws: OpenCodexAccessError.outputTooLarge) { try await transport.run(mutation) }
        do {
            _ = try await transport.run(.init(binary: binary.path, arguments: [], mutation: false))
            Issue.record("expected failure")
        } catch {
            #expect(!String(reflecting: error).contains("synthetic-secret"))
            #expect(!error.localizedDescription.contains("synthetic-secret"))
        }
    }
}

extension OpenCodexAccessTests {
    @Test func `OpenCodexAccess rejects malformed required fields and optional scopes`() throws {
        for row in [
            Self.row.replacingOccurrences(of: "\"id-a\"", with: "null"),
            Self.row.replacingOccurrences(of: "\"same\"", with: "123"),
            Self.row.replacingOccurrences(of: "ocx_abc", with: ""),
            Self.row.replacingOccurrences(of: "2026-10-20", with: "2026-02-30"),
            Self.row.replacingOccurrences(of: "}", with: ",\"allowedModels\":[1]}"),
        ] {
            #expect(throws: OpenCodexAccessError.invalidResponse) {
                try OpenCodexAccessParser.list(Data("{\"keys\":[\(row)]}".utf8))
            }
        }
        #expect(try OpenCodexAccessParser.list(Data(#"{"keys":[]}"#.utf8)).keys.isEmpty)
        for raw in [#"{}"#, #"{"success":1}"#, #"{"success":false}"#] {
            #expect(throws: OpenCodexAccessError.invalidResponse) {
                try OpenCodexAccessParser.revoked(Data(raw.utf8))
            }
        }
    }

    @Test func `OpenCodexAccess usage preserves missing zero ambiguous and incomplete semantics`() throws {
        func list(since: String = "2026-10-20T01:02:03Z", usage: String) throws -> OpenCodexAccessKeyList {
            let row = Self.row.dropLast() + ",\"usage\":\(usage),\"allowedProviders\":[\"claude\"],\"allowedModels\":[]}"
            return try OpenCodexAccessParser.list(Data("""
            {"keys":[\(row)],"attributionSince":"\(since)","historyTruncated":true,
            "usageIncomplete":true,"usageIncompleteReason":"synthetic gap"}
            """.utf8))
        }
        let zero = try list(usage: #"{"requests7d":0,"totalRequests":0}"#)
        #expect(zero.keys[0].usage.hasNoRecordedUsage)
        #expect(zero.historyTruncated && zero.usageIncomplete)
        #expect(zero.usageIncompleteReason == "synthetic gap")
        #expect(zero.keys[0].allowedProviders == ["claude"])
        #expect(zero.keys[0].allowedModels == [])
        #expect(try list(usage: #"{"totalRequests":3}"#).keys[0].usage ==
            .recorded(requests7d: nil, totalRequests: 3, lastUsedAt: nil))
        #expect(try list(usage: #"{"ambiguous":true,"totalRequests":9}"#).keys[0].usage == .ambiguous)
        for usage in [
            #"{}"#,
            #"{"totalRequests":-1}"#,
            #"{"totalRequests":true}"#,
            #"{"requests7d":"1"}"#,
            #"{"totalRequests":1,"lastUsedAt":"yesterday"}"#,
        ] {
            #expect(try list(usage: usage).keys[0].usage == .unavailable)
        }
        #expect(try list(since: "invalid", usage: #"{"totalRequests":9}"#).keys[0].usage == .unavailable)
    }

    @Test func `OpenCodexAccess successful create revoke and subsequent role change use fixed argv`() async throws {
        let created = #"{"id":"new-id","name":"new name","key":"synthetic-secret","createdAt":"2026-10-20T01:02:03Z"}"#
        let transport = OpenCodexAccessScript([
            .success(Data(Self.status.utf8)), .success(Data(#"{"keys":[]}"#.utf8)),
            .success(Data(Self.status.utf8)), .success(Data(created.utf8)),
            .success(Data(Self.status.utf8)), .success(Data(#"{"success":true}"#.utf8)),
            .success(Data(Self.status.replacingOccurrences(of: "hub", with: "client").utf8)),
        ])
        let client = OpenCodexAccessClient(executablePath: "/fake/ocx", transport: transport, mutationGate: .init())
        #expect(try await client.list().keys.isEmpty)
        #expect(try await client.create(name: "  new name ").id == "new-id")
        try await client.revoke(id: "new-id")
        await #expect(throws: OpenCodexAccessError.unsupportedRole) { try await client.create(name: "new") }
        #expect(await transport.calls == [
            ["status", "--json"], ["access", "key", "list", "--json"],
            ["status", "--json"], ["access", "key", "create", "new name", "--json"],
            ["status", "--json"], ["access", "key", "remove", "new-id", "--yes", "--json"], ["status", "--json"],
        ])
    }
}

private actor OpenCodexAccessBlockingTransport: OpenCodexAccessTransport {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var mutationStarted = false
    func run(_ request: OpenCodexAccessRequest) async throws -> Data {
        if !request.mutation { return Data(OpenCodexAccessTests.status.utf8) }
        self.mutationStarted = true
        await withCheckedContinuation { self.continuation = $0 }
        return Data(#"{"success":true}"#.utf8)
    }

    func finish() { self.continuation?.resume(); self.continuation = nil }
}

extension OpenCodexAccessTests {
    @Test func `OpenCodexAccess shared gate prevents duplicate mutation and cancellation does not restart`() async throws {
        let transport = OpenCodexAccessBlockingTransport()
        let gate = OpenCodexAccessMutationGate()
        let first = OpenCodexAccessClient(executablePath: "/fake/ocx", transport: transport, mutationGate: gate)
        let second = OpenCodexAccessClient(executablePath: "/fake/ocx", transport: transport, mutationGate: gate)
        let task = Task { try await first.revoke(id: "a") }
        while await !(transport.mutationStarted) {
            await Task.yield()
        }
        task.cancel()
        await #expect(throws: OpenCodexAccessError.mutationInProgress) { try await second.revoke(id: "b") }
        await transport.finish()
        try await task.value
    }

    @Test func `OpenCodexAccess real fake mutation runs to completion after cancellation`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let binary = directory.appendingPathComponent("ocx")
        let marker = directory.appendingPathComponent("started")
        try FakeExecutable.install("touch '\(marker.path)'\nsleep 0.2\nprintf '{\"success\":true}'", at: binary)
        let task = Task {
            try await OpenCodexAccessProcessTransport().run(.init(binary: binary.path, arguments: [], mutation: true))
        }
        while !FileManager.default.fileExists(atPath: marker.path) {
            try await Task.sleep(for: .milliseconds(5))
        }
        task.cancel()
        #expect(try await String(decoding: task.value, as: UTF8.self) == #"{"success":true}"#)
    }
}

extension OpenCodexAccessTests {
    @Test func `OpenCodexAccess fake CLI lists creates and confirms no output secret leakage`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let binary = directory.appendingPathComponent("ocx")
        try FakeExecutable.install("""
        case "$1 $2" in
          'status --json') printf '%s' '\(Self.status)' ;;
          'access key')
            case "$3" in
              list) printf '%s' '{"keys":[\(Self.row)]}' ;;
              create) printf '%s' '{"id":"new","name":"new","key":"synthetic-secret","createdAt":"2026-10-20T01:02:03Z"}' ;;
              remove) printf '%s' '{"success":true}' ;;
              *) exit 64 ;;
            esac ;;
          *) exit 64 ;;
        esac
        """, at: binary)
        let client = OpenCodexAccessClient(executablePath: binary.path, mutationGate: .init())
        #expect(try await client.list().keys.map(\.id) == ["id-a"])
        let created = try await client.create(name: "new")
        #expect(created.secret.reveal() == "synthetic-secret")
        #expect(!String(reflecting: created).contains("synthetic-secret"))
        try await client.revoke(id: "new")
    }

    @Test func `OpenCodexAccess native rename validates synthetic installation and fixed stdin contract`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fm = FileManager.default
        for path in ["bin", "src/cli", "node_modules/bun/bin"] {
            try fm.createDirectory(at: directory.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        defer { try? fm.removeItem(at: directory) }
        try #"{"name":"@bitkyc08/opencodex","version":"2.88.0","bin":{"ocx":"./bin/ocx.mjs"},"dependencies":{"bun":"1.4.2"}}"#
            .write(to: directory.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try #"{"name":"bun","version":"1.4.2"}"#.write(
            to: directory.appendingPathComponent("node_modules/bun/package.json"), atomically: true, encoding: .utf8)
        try "// fake module, never imported by native validation".write(
            to: directory.appendingPathComponent("src/cli/runtime-api.ts"), atomically: true, encoding: .utf8)
        /// This fixture must be physically inside the package: the shared symlink trampoline is intentionally refused.
        func installContained(_ body: String, at url: URL) throws {
            try Data(("#!/bin/sh\n" + body).utf8).write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        let cli = directory.appendingPathComponent("bin/ocx.mjs")
        try installContained("printf '%s' '\(Self.status)'", at: cli)
        let runtime = directory.appendingPathComponent("node_modules/bun/bin/bun.exe")
        let input = directory.appendingPathComponent("input.json")
        let args = directory.appendingPathComponent("args")
        try installContained("""
        printf '%s\\n' "$@" > '\(args.path)'
        cat > '\(input.path)'
        printf '%s' '{"id":"exact-id","name":"new","createdAt":"2026-10-20T01:02:03Z","allowedModels":["kept"]}'
        """, at: runtime)
        let installation = try OpenCodexAccessRenameInstallation.resolve(executable: cli.path)
        let client = OpenCodexAccessClient(executablePath: cli.path, mutationGate: .init())
        let renamed = try await client.rename(id: "exact-id", name: "new")
        #expect(renamed.allowedModels == ["kept"])
        let payload = try JSONSerialization.jsonObject(with: Data(contentsOf: input)) as? [String: String]
        #expect(payload == ["id": "exact-id", "name": "new"])
        let arguments = try String(contentsOf: args, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(arguments == [installation.helper, installation.executable])
        try fm.removeItem(at: runtime)
        #expect(throws: OpenCodexAccessError.renameUnsupported) {
            try OpenCodexAccessRenameInstallation.resolve(executable: cli.path)
        }
    }

    @Test func `OpenCodexAccess client honors adjustable read limit and fixed errors`() async throws {
        let data = Data(("{\"keys\":[],\"discard\":\"" + String(repeating: "x", count: 262_144) + "\"}").utf8)
        let transport = OpenCodexAccessScript([.success(Data(Self.status.utf8)), .success(data)])
        let client = OpenCodexAccessClient(executablePath: "/fake/ocx", transport: transport, maxOutputBytes: 300_000)
        #expect(try await client.list().keys.isEmpty)
        let failed = OpenCodexAccessScript([.success(Data(Self.status.utf8)), .failure(.communicationFailed)])
        let uncertain = OpenCodexAccessClient(executablePath: "/fake/ocx", transport: failed, mutationGate: .init())
        await #expect(throws: OpenCodexAccessError.confirmationRequired) { try await uncertain.create(name: "new") }
    }
}
