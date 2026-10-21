import Foundation

/// The role opencodex reports for this Mac (`runtimeRole` in `ocx status --json`).
///
/// A hub or a standalone install owns its account pools: `ocx account list` reads them and
/// `ocx account use` switches them. A client (for example a Remote Link Child) also answers
/// `ocx account list`, from the hub's cache, but refuses `ocx account use`, so a client is never
/// treated as the hub just because a list came back.
public enum OpenCodexRuntimeRole: String, Equatable, Sendable {
    case hub
    case standalone
    case client
    /// `ocx` is missing, did not answer, or reported a role this build does not know.
    case unknown

    /// Whether this Mac's `ocx` owns the pools, so `ocx account use` may run here.
    public var ownsAccounts: Bool {
        self == .hub || self == .standalone
    }
}

/// Reads the runtime role from `ocx status --json` (a fixed argument array, never a shell).
///
/// opencodex documents the command as reading `/healthz` plus the local config without calling a management
/// route. Only `runtimeRole` is read; every other field (the hub block can carry token details) is dropped.
public enum OpenCodexRuntimeRoleProbe {
    public static let statusArguments = ["status", "--json"]
    public static let timeout: TimeInterval = 10

    public static func detect(binary: String) async -> OpenCodexRuntimeRole {
        guard let result = try? await SubprocessRunner.run(
            binary: binary,
            arguments: self.statusArguments,
            environment: OpenCodexHubReader.environment(for: binary),
            timeout: self.timeout,
            maxOutputBytes: OpenCodexHubReader.maxOutputBytes,
            acceptsNonZeroExit: true,
            label: "opencodex status")
        else {
            return .unknown
        }
        return self.parseRole(Data(result.stdout.utf8))
    }

    /// The role in a status document, or `.unknown` when the document has none this build knows.
    public static func parseRole(_ data: Data) -> OpenCodexRuntimeRole {
        guard data.count <= OpenCodexHubReader.maxOutputBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["runtimeRole"] as? String,
              let role = OpenCodexRuntimeRole(rawValue: raw),
              role != .unknown
        else {
            return .unknown
        }
        return role
    }
}

/// Remembers the runtime role per `ocx` executable so a refresh pass asks opencodex once, not once per pool.
///
/// A known role is kept for `knownRoleLifetime`; an unknown answer is retried sooner. Concurrent callers for
/// the same executable share one `ocx status` run.
public actor OpenCodexRuntimeRoleCache {
    public static let shared = OpenCodexRuntimeRoleCache()
    public static let knownRoleLifetime: TimeInterval = 5 * 60
    public static let unknownRoleLifetime: TimeInterval = 60

    public typealias Probe = @Sendable (String) async -> OpenCodexRuntimeRole

    private struct Entry {
        let role: OpenCodexRuntimeRole
        let checkedAt: Date
    }

    private let probe: Probe
    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<OpenCodexRuntimeRole, Never>] = [:]

    public init(probe: @escaping Probe = { await OpenCodexRuntimeRoleProbe.detect(binary: $0) }) {
        self.probe = probe
    }

    /// The role of the `ocx` at `binary`, or `.unknown` without an executable (no process is started then).
    public func role(forBinary binary: String?, now: Date = Date()) async -> OpenCodexRuntimeRole {
        guard let binary else { return .unknown }
        if let entry = self.entries[binary] {
            let lifetime = entry.role == .unknown ? Self.unknownRoleLifetime : Self.knownRoleLifetime
            let age = now.timeIntervalSince(entry.checkedAt)
            if age >= 0, age < lifetime { return entry.role }
        }
        if let running = self.inFlight[binary] {
            return await running.value
        }
        let probe = self.probe
        let task = Task { await probe(binary) }
        self.inFlight[binary] = task
        let role = await task.value
        self.inFlight[binary] = nil
        self.entries[binary] = Entry(role: role, checkedAt: now)
        return role
    }

    /// Forgets the cached roles (all of them, or one executable's) so the next read asks opencodex again.
    public func invalidate(binary: String? = nil) {
        if let binary {
            self.entries[binary] = nil
        } else {
            self.entries.removeAll()
        }
    }
}
