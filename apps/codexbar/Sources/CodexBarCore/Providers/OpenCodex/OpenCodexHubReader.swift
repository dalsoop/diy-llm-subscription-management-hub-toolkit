import Foundation

public enum OpenCodexHubReaderError: LocalizedError, Equatable, Sendable {
    /// This Mac cannot list the hub's accounts (for example a client linked to a hub) and has no snapshot.
    case hubAccountsUnavailable(String)
    /// Neither an opencodex that reports its role nor a hub snapshot is available on this Mac.
    case noHubSource(String)
    case snapshotUnreadable(String)
    /// This Mac is not the hub and has no current hub snapshot to ask for a switch through.
    case snapshotNotCurrent
    case accountNotFound
    case switchNotAllowed(String?)
    case switchFailed(String)
    case mismatchedTarget

    public var errorDescription: String? {
        switch self {
        case let .hubAccountsUnavailable(details):
            "This Mac cannot list the opencodex hub's accounts (\(details)). " +
                "Accounts are managed on the hub; set a hub snapshot file to view them here."
        case let .noHubSource(details):
            "No opencodex hub source is available on this Mac (\(details)). " +
                "Install opencodex or set a hub snapshot file to read the hub's accounts."
        case let .snapshotUnreadable(details):
            "The opencodex hub snapshot could not be read: \(details)"
        case .snapshotNotCurrent:
            "This Mac asks the opencodex hub to switch through the hub's snapshot, " +
                "and the hub has not written a current one; try again after the hub's next update."
        case .accountNotFound:
            "The hub no longer lists this account; refresh and try again."
        case let .switchNotAllowed(reason):
            reason ?? "This pool cannot be switched from this Mac."
        case let .switchFailed(details):
            "opencodex could not switch the account: \(details)"
        case .mismatchedTarget:
            "opencodex reported a different active account than the one CodexBar requested."
        }
    }
}

/// What a switch did: switched on the hub itself, or left a request for the hub.
public enum OpenCodexHubSwitchOutcome: Equatable, Sendable {
    case alreadyActive
    case switched
    case requested(OpenCodexHubSwitchRequest)
}

/// A pool as read on this Mac, by where it came from.
public enum OpenCodexHubPoolRead: Equatable, Sendable {
    /// The hub's (or a standalone install's) own `ocx account list`; switched with `ocx account use`.
    case live(OpenCodexHubLivePool)
    /// The snapshot file the hub writes for the Macs linked to it; switched by a request file.
    case snapshot(OpenCodexHubSnapshotPool)
    /// A linked Mac's own read-only `ocx account list`, used while no current snapshot is available.
    case linkedCopy(OpenCodexHubPool)

    public var pool: OpenCodexHubPool {
        switch self {
        case let .live(live): live.pool
        case let .snapshot(snapshot): snapshot.pool
        case let .linkedCopy(pool): pool
        }
    }
}

/// How a switch reaches the hub from this Mac.
public enum OpenCodexHubSwitchRoute: Equatable, Sendable {
    /// This Mac is the hub: `ocx account use` with the id from this fresh live list.
    case hub(OpenCodexHubLivePool, binary: String)
    /// Any other Mac: a request file next to the snapshot, checked against this snapshot.
    case request(OpenCodexHubSnapshotPool, requestsDirectory: URL)
}

/// Bounded adapter over the opencodex hub's account pools.
///
/// The role opencodex reports (`ocx status --json`, cached per executable by `OpenCodexRuntimeRoleCache`)
/// decides the path; a list coming back is not proof of being the hub, because a Mac linked to a hub also
/// answers `ocx account list` from the hub's cache while it refuses `ocx account use`.
///
/// - Hub or standalone: `ocx account list <provider> --quota --json` lists a pool and
///   `ocx account use <provider> <id> --json` switches it.
/// - Client (linked to a hub): the snapshot file the hub writes is read, and a switch is asked for by writing a
///   request file next to it. Without a current snapshot the Mac's own list is shown read-only.
///   `ocx account use` never runs on a client.
/// - Unknown role (no `ocx`, or it did not say): the snapshot only.
///
/// Only those fixed argument arrays run, never a shell. opencodex keeps the credentials on the hub; CodexBar
/// never reads or stores them, and full account ids stay in memory.
public enum OpenCodexHubReader {
    public static let defaultTimeout: TimeInterval = 30
    public static let maxOutputBytes = 262_144
    static let diagnosticLimit = 200
    /// Where `ocx` is looked for when no executable path is configured.
    public static let executableSearchPaths = [
        "/opt/homebrew/bin/ocx",
        "/usr/local/bin/ocx",
        "~/.local/bin/ocx",
    ]

    /// The configured executable, or the first `ocx` found in the usual install locations.
    public static func resolvedExecutablePath(
        _ configured: String?,
        fileManager: FileManager = .default) -> String?
    {
        if let configured = SettingsValue.cleaned(configured) {
            return (configured as NSString).expandingTildeInPath
        }
        return self.executableSearchPaths
            .map { ($0 as NSString).expandingTildeInPath }
            .first { fileManager.isExecutableFile(atPath: $0) }
    }

    /// Reads a pool from the source this Mac's opencodex role allows (see the type documentation).
    public static func readPool(
        provider: OpenCodexHubProvider,
        executablePath: String?,
        snapshotPath: String?,
        roleCache: OpenCodexRuntimeRoleCache = .shared,
        now: Date = Date(),
        timeout: TimeInterval = OpenCodexHubReader.defaultTimeout) async throws -> OpenCodexHubPool
    {
        try await self.read(
            provider: provider,
            executablePath: executablePath,
            snapshotPath: snapshotPath,
            roleCache: roleCache,
            now: now,
            timeout: timeout).pool
    }

    /// Reads a pool and says where it came from.
    public static func read(
        provider: OpenCodexHubProvider,
        executablePath: String?,
        snapshotPath: String?,
        roleCache: OpenCodexRuntimeRoleCache = .shared,
        now: Date = Date(),
        timeout: TimeInterval = OpenCodexHubReader.defaultTimeout) async throws -> OpenCodexHubPoolRead
    {
        let binary = self.resolvedExecutablePath(executablePath)
        let snapshotPath = SettingsValue.cleaned(snapshotPath)
        let role = await roleCache.role(forBinary: binary, now: now)
        try Task.checkCancellation()
        switch (role, binary) {
        case let (.hub, .some(binary)), let (.standalone, .some(binary)):
            return try await self.readOnHub(
                provider: provider, binary: binary, snapshotPath: snapshotPath, timeout: timeout)
        case let (.client, .some(binary)):
            return try await self.readOnClient(
                provider: provider, binary: binary, snapshotPath: snapshotPath, now: now, timeout: timeout)
        default:
            guard let snapshotPath,
                  let snapshot = try self.readSnapshotIfPresent(provider: provider, path: snapshotPath)
            else {
                throw OpenCodexHubReaderError.noHubSource(self.noSourceDetails(binary: binary))
            }
            return .snapshot(snapshot)
        }
    }

    /// Reads the live hub list. Throws `.hubAccountsUnavailable` when opencodex answers without a list.
    public static func readLivePool(
        provider: OpenCodexHubProvider,
        binary: String,
        timeout: TimeInterval = OpenCodexHubReader.defaultTimeout) async throws -> OpenCodexHubLivePool
    {
        try Task.checkCancellation()
        let result = try await SubprocessRunner.run(
            binary: binary,
            arguments: provider.listArguments,
            environment: self.environment(for: binary),
            timeout: timeout,
            acceptsNonZeroExit: true,
            label: "opencodex list")
        let data = try self.boundedOutput(result.stdout)
        guard OpenCodexHubPoolParser.looksLikeAccountList(data) else {
            throw OpenCodexHubReaderError.hubAccountsUnavailable(self.diagnostic(result))
        }
        return try OpenCodexHubPoolParser.parseLiveList(data, provider: provider)
    }

    public static func readSnapshot(provider: OpenCodexHubProvider, path: String) throws -> OpenCodexHubSnapshotPool {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let data: Data
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? NSNumber, size.intValue > self.maxOutputBytes {
                throw OpenCodexHubReaderError.snapshotUnreadable("file is larger than the list limit")
            }
            data = try Data(contentsOf: url)
        } catch let error as OpenCodexHubReaderError {
            throw error
        } catch {
            throw OpenCodexHubReaderError.snapshotUnreadable("no readable file at \(url.lastPathComponent)")
        }
        return try OpenCodexHubPoolParser.parseSnapshot(data, provider: provider)
    }

    /// The snapshot, or nil when no file exists at `path` (a configured but absent snapshot is no source).
    static func readSnapshotIfPresent(
        provider: OpenCodexHubProvider,
        path: String) throws -> OpenCodexHubSnapshotPool?
    {
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return nil }
        return try self.readSnapshot(provider: provider, path: path)
    }

    /// Switches `provider`'s pool to the account with this id suffix and masked email.
    ///
    /// On the hub the live list is read again so the account is resolved against what the hub lists now,
    /// then `ocx account use` runs to its natural exit. On another Mac the snapshot is read again, the
    /// target is checked against it and a request file is written for the hub's next pass.
    public static func switchAccount(
        provider: OpenCodexHubProvider,
        idSuffix: String,
        email: String,
        executablePath: String?,
        snapshotPath: String?,
        roleCache: OpenCodexRuntimeRoleCache = .shared,
        now: Date = Date(),
        timeout: TimeInterval = OpenCodexHubReader.defaultTimeout) async throws -> OpenCodexHubSwitchOutcome
    {
        let route = try await self.switchRoute(
            provider: provider,
            executablePath: executablePath,
            snapshotPath: snapshotPath,
            roleCache: roleCache,
            now: now,
            timeout: timeout)
        switch route {
        case let .hub(live, binary):
            return try await self.switchOnHub(live, idSuffix: idSuffix, email: email, binary: binary)
        case let .request(snapshot, requestsDirectory):
            return try self.requestSwitch(
                pool: snapshot.pool,
                idSuffix: idSuffix,
                email: email,
                requestsDirectory: requestsDirectory,
                now: now)
        }
    }

    /// Decides how a switch reaches the hub. Only a Mac whose opencodex owns the pools (hub or standalone) runs
    /// `ocx account use`; every other Mac asks through a current snapshot.
    public static func switchRoute(
        provider: OpenCodexHubProvider,
        executablePath: String?,
        snapshotPath: String?,
        roleCache: OpenCodexRuntimeRoleCache = .shared,
        now: Date = Date(),
        timeout: TimeInterval = OpenCodexHubReader.defaultTimeout) async throws -> OpenCodexHubSwitchRoute
    {
        let binary = self.resolvedExecutablePath(executablePath)
        let snapshotPath = SettingsValue.cleaned(snapshotPath)
        let role = await roleCache.role(forBinary: binary, now: now)
        try Task.checkCancellation()
        if role.ownsAccounts, let binary {
            do {
                let live = try await self.readLivePool(provider: provider, binary: binary, timeout: timeout)
                return .hub(live, binary: binary)
            } catch let error as OpenCodexHubPoolError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // The hub's own list failed: a request through its snapshot still reaches it.
                guard let snapshotPath else { throw error }
                let snapshot = try self.readSnapshot(provider: provider, path: snapshotPath)
                let directory = OpenCodexHubSwitchRequestWriter.requestsDirectory(forSnapshotPath: snapshotPath)
                return .request(snapshot, requestsDirectory: directory)
            }
        }
        guard let snapshotPath,
              let snapshot = try self.readSnapshotIfPresent(provider: provider, path: snapshotPath)
        else {
            if role == .client { throw OpenCodexHubReaderError.snapshotNotCurrent }
            throw OpenCodexHubReaderError.noHubSource(self.noSourceDetails(binary: binary))
        }
        guard !snapshot.pool.isStale(now: now) else { throw OpenCodexHubReaderError.snapshotNotCurrent }
        return .request(
            snapshot,
            requestsDirectory: OpenCodexHubSwitchRequestWriter.requestsDirectory(forSnapshotPath: snapshotPath))
    }

    /// Writes a switch request for the hub after checking the target against `pool`.
    public static func requestSwitch(
        pool: OpenCodexHubPool,
        idSuffix: String,
        email: String,
        requestsDirectory: URL,
        requestID: String = UUID().uuidString,
        now: Date = Date()) throws -> OpenCodexHubSwitchOutcome
    {
        let matches = pool.accounts.filter { $0.idSuffix == idSuffix && $0.email == email }
        guard matches.count == 1, let account = matches.first else {
            throw OpenCodexHubReaderError.accountNotFound
        }
        if account.isActive { return .alreadyActive }
        guard pool.switchable else { throw OpenCodexHubReaderError.switchNotAllowed(pool.switchReason) }
        guard pool.canSwitch(to: account) else { throw OpenCodexHubReaderError.switchNotAllowed(nil) }
        let request = OpenCodexHubSwitchRequest(
            requestID: requestID,
            provider: pool.provider,
            targetIDSuffix: idSuffix,
            targetEmail: email,
            requestedAt: now)
        try OpenCodexHubSwitchRequestWriter.write(request, to: requestsDirectory)
        return .requested(request)
    }

    static func switchOnHub(
        _ live: OpenCodexHubLivePool,
        idSuffix: String,
        email: String,
        binary: String) async throws -> OpenCodexHubSwitchOutcome
    {
        let matches = live.pool.accounts.indices.filter {
            live.pool.accounts[$0].idSuffix == idSuffix && live.pool.accounts[$0].email == email
        }
        guard matches.count == 1, let index = matches.first else {
            throw OpenCodexHubReaderError.accountNotFound
        }
        if live.pool.accounts[index].isActive { return .alreadyActive }
        guard let accountID = live.accountIDs[index] else { throw OpenCodexHubReaderError.switchNotAllowed(nil) }
        let result = try await SubprocessRunner.runToCompletion(
            binary: binary,
            arguments: ["account", "use", live.pool.provider.rawValue, accountID, "--json"],
            environment: self.environment(for: binary),
            acceptsNonZeroExit: true,
            label: "opencodex switch")
        let activeID: String
        do {
            activeID = try OpenCodexHubPoolParser.parseSwitchReceipt(self.boundedOutput(result.stdout))
        } catch {
            throw OpenCodexHubReaderError.switchFailed(self.diagnostic(result))
        }
        guard activeID == accountID else { throw OpenCodexHubReaderError.mismatchedTarget }
        return .switched
    }

    private static func readOnHub(
        provider: OpenCodexHubProvider,
        binary: String,
        snapshotPath: String?,
        timeout: TimeInterval) async throws -> OpenCodexHubPoolRead
    {
        let liveFailure: String
        do {
            return try await .live(self.readLivePool(provider: provider, binary: binary, timeout: timeout))
        } catch let error as OpenCodexHubReaderError {
            guard case let .hubAccountsUnavailable(details) = error else { throw error }
            liveFailure = details
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as OpenCodexHubPoolError {
            // A hub that answers with a malformed list is a real error.
            throw error
        } catch {
            liveFailure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        guard let snapshotPath else {
            throw OpenCodexHubReaderError.hubAccountsUnavailable(liveFailure)
        }
        return try .snapshot(self.readSnapshot(provider: provider, path: snapshotPath))
    }

    /// A linked Mac: the hub's current snapshot first (it carries switchability and the hub's request results);
    /// otherwise this Mac's own list, read-only; otherwise an out-of-date snapshot, shown as such.
    private static func readOnClient(
        provider: OpenCodexHubProvider,
        binary: String,
        snapshotPath: String?,
        now: Date,
        timeout: TimeInterval) async throws -> OpenCodexHubPoolRead
    {
        // An absent, unreadable or out-of-date snapshot falls back to the linked list below.
        let snapshot = snapshotPath.flatMap { try? self.readSnapshotIfPresent(provider: provider, path: $0) }
        if let snapshot, !snapshot.pool.isStale(now: now) {
            return .snapshot(snapshot)
        }
        do {
            let live = try await self.readLivePool(provider: provider, binary: binary, timeout: timeout)
            return .linkedCopy(OpenCodexHubPool(
                provider: provider,
                accounts: live.pool.accounts,
                switchable: false,
                origin: .linkedCopy(hubName: snapshot?.pool.hubName),
                lastRequests: snapshot?.pool.lastRequests ?? []))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let snapshot { return .snapshot(snapshot) }
            throw error
        }
    }

    private static func noSourceDetails(binary: String?) -> String {
        binary == nil ? "no ocx executable" : "opencodex did not report this Mac's role"
    }

    /// `ocx` is a Node launcher (`#!/usr/bin/env node`). A menu bar app inherits launchd's short PATH, so
    /// the directory the executable was configured in (for example `/opt/homebrew/bin`, where Homebrew
    /// also links `node`) goes first.
    static func environment(
        for binary: String,
        base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String]
    {
        var environment = base
        let directory = (binary as NSString).deletingLastPathComponent
        guard !directory.isEmpty else { return environment }
        let existing = environment["PATH"].map { ":" + $0 } ?? ""
        environment["PATH"] = directory + existing
        return environment
    }

    static func boundedOutput(_ stdout: String) throws -> Data {
        guard stdout.utf8.count <= self.maxOutputBytes else {
            throw ClaudeSwapAccountReaderError.outputTooLarge(byteCount: stdout.utf8.count)
        }
        return Data(stdout.utf8)
    }

    /// The first non-empty stderr line (opencodex prints `Error: <code>` there), bounded.
    static func diagnostic(_ result: SubprocessResult) -> String {
        let line = result.stderr
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let line else { return "no account list" }
        return String(line.prefix(self.diagnosticLimit))
    }
}
