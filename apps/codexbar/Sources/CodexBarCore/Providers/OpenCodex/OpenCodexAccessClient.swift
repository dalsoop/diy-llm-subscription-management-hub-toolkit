import Foundation

/// Inject this into app-owned state. Reads do not imply mutations; mutation success never implies refresh success.
public protocol OpenCodexAccessSource: Sendable {
    func status() async throws -> OpenCodexAccessStatus
    func list() async throws -> OpenCodexAccessKeyList
    func create(name: String) async throws -> OpenCodexAccessCreatedKey
    func rename(id: String, name: String) async throws -> OpenCodexAccessRenamedKey
    func revoke(id: String) async throws
}

/// One shared gate across all native clients; dashboard writes have their own lifecycle.
public actor OpenCodexAccessMutationGate {
    public static let shared = OpenCodexAccessMutationGate()
    private var busy = false
    public init() {}
    func acquire() throws {
        guard !self.busy else { throw OpenCodexAccessError.mutationInProgress }
        self.busy = true
    }

    func release() { self.busy = false }
}

public actor OpenCodexAccessClient: OpenCodexAccessSource {
    private let executablePath: String?
    private let transport: any OpenCodexAccessTransport
    private let timeout: TimeInterval
    private let maxOutputBytes: Int
    private let mutationGate: OpenCodexAccessMutationGate

    public init(
        executablePath: String? = nil,
        transport: any OpenCodexAccessTransport = OpenCodexAccessProcessTransport(),
        timeout: TimeInterval = 30,
        maxOutputBytes: Int = 262_144,
        mutationGate: OpenCodexAccessMutationGate = .shared)
    {
        self.executablePath = executablePath
        self.transport = transport
        self.timeout = timeout
        self.maxOutputBytes = maxOutputBytes
        self.mutationGate = mutationGate
    }

    private func binary() throws -> String {
        guard let binary = OpenCodexHubReader.resolvedExecutablePath(self.executablePath) else {
            throw OpenCodexAccessError.executableMissing
        }
        return binary
    }

    private func run(
        binary: String,
        arguments: [String],
        input: Data? = nil,
        mutation: Bool = false) async throws -> Data
    {
        do {
            let data = try await self.transport.run(.init(
                binary: binary,
                arguments: arguments,
                input: input,
                mutation: mutation,
                timeout: self.timeout,
                maxOutputBytes: self.maxOutputBytes))
            guard data.count <= self.maxOutputBytes else { throw OpenCodexAccessError.outputTooLarge }
            return data
        } catch let error as OpenCodexAccessError {
            throw error
        } catch {
            throw OpenCodexAccessError.communicationFailed
        }
    }

    private func status(binary: String) async throws -> OpenCodexAccessStatus {
        try await OpenCodexAccessParser.status(
            self.run(binary: binary, arguments: ["status", "--json"]),
            maxOutputBytes: self.maxOutputBytes)
    }

    public func status() async throws -> OpenCodexAccessStatus { try await self.status(binary: self.binary()) }

    public func list() async throws -> OpenCodexAccessKeyList {
        let binary = try self.binary()
        try await self.status(binary: binary).requireLocalManagement()
        return try await OpenCodexAccessParser.list(self.run(
            binary: binary, arguments: ["access", "key", "list", "--json"]), maxOutputBytes: self.maxOutputBytes)
    }

    private static func validateID(_ id: String) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, id.utf8.count <= 512,
              !id.replacingOccurrences(of: "[‐-―−]", with: "-", options: .regularExpression).hasPrefix("-"),
              id.rangeOfCharacter(from: .controlCharacters) == nil,
              id != "json", !id.hasPrefix("json=") else { throw OpenCodexAccessError.invalidID }
    }

    /// Once launched, a mutation waits for completion despite view/task cancellation. Never retries or auto-refreshes.
    private func mutate<T: Sendable>(
        _ action: @escaping @Sendable () async throws -> T) async throws -> T
    {
        try Task.checkCancellation()
        try await self.mutationGate.acquire()
        do {
            let task = Task.detached { try await action() }
            let value = try await task.value
            await self.mutationGate.release()
            return value
        } catch {
            await self.mutationGate.release()
            throw error
        }
    }

    private static func mutationError(_ error: any Error) -> OpenCodexAccessError {
        // Only explicit fixed helper refusals or known CLI not-found are definite failures after launch.
        if let error = error as? OpenCodexAccessError,
           [.permissionDenied, .notFound, .renameUnsupported].contains(error) { return error }
        return .confirmationRequired
    }

    public func create(name: String) async throws -> OpenCodexAccessCreatedKey {
        let name = try OpenCodexAccessName.validate(name)
        let binary = try self.binary()
        return try await self.mutate {
            try await self.status(binary: binary).requireLocalManagement()
            do {
                let data = try await self.run(
                    binary: binary,
                    arguments: ["access", "key", "create", name, "--json"],
                    mutation: true)
                return try OpenCodexAccessParser.created(data, expectedName: name)
            } catch { throw Self.mutationError(error) }
        }
    }

    public func rename(id: String, name: String) async throws -> OpenCodexAccessRenamedKey {
        try Self.validateID(id)
        let name = try OpenCodexAccessName.validate(name)
        let installation = try OpenCodexAccessRenameInstallation.resolve(executable: self.binary())
        let input = try JSONSerialization.data(withJSONObject: ["id": id, "name": name])
        return try await self.mutate {
            try await self.status(binary: installation.executable).requireLocalManagement()
            do {
                let data = try await self.run(
                    binary: installation.runtime,
                    arguments: [installation.helper, installation.executable],
                    input: input,
                    mutation: true)
                if let code = try OpenCodexAccessParser.object(data)["error"] as? String {
                    switch code {
                    case "unsupported_installation": throw OpenCodexAccessError.renameUnsupported
                    case "permission_denied": throw OpenCodexAccessError.permissionDenied
                    case "not_found": throw OpenCodexAccessError.notFound
                    default: throw OpenCodexAccessError.confirmationRequired
                    }
                }
                return try OpenCodexAccessParser.renamed(data, id: id, name: name)
            } catch { throw Self.mutationError(error) }
        }
    }

    public func revoke(id: String) async throws {
        try Self.validateID(id)
        let binary = try self.binary()
        try await self.mutate {
            try await self.status(binary: binary).requireLocalManagement()
            do {
                let data = try await self.run(
                    binary: binary,
                    arguments: ["access", "key", "remove", id, "--yes", "--json"],
                    mutation: true)
                try OpenCodexAccessParser.revoked(data)
            } catch { throw Self.mutationError(error) }
        }
    }
}
