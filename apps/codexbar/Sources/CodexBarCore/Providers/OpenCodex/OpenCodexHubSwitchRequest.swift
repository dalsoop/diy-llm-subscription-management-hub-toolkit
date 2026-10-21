#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import Foundation

/// A switch request a Mac that is not the hub leaves for the hub to pick up
/// (`<requests directory>/<requestId>.json`). It names the target by the id suffix and
/// the masked email the hub's snapshot listed; the hub resolves the full id itself.
public struct OpenCodexHubSwitchRequest: Equatable, Sendable {
    public static let schemaVersion = 1
    /// The hub skips request files above this size.
    public static let maximumFileBytes = 4096

    public let requestID: String
    public let provider: OpenCodexHubProvider
    public let targetIDSuffix: String
    public let targetEmail: String
    public let requestedAt: Date

    public init(
        requestID: String = UUID().uuidString,
        provider: OpenCodexHubProvider,
        targetIDSuffix: String,
        targetEmail: String,
        requestedAt: Date = Date())
    {
        self.requestID = requestID
        self.provider = provider
        self.targetIDSuffix = targetIDSuffix
        self.targetEmail = targetEmail
        self.requestedAt = requestedAt
    }

    /// `[A-Za-z0-9-]{1,64}`; the file stem must equal the id.
    public static func isValidRequestID(_ id: String) -> Bool {
        guard (1...64).contains(id.utf8.count) else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-")
        }
    }

    public var fileName: String {
        "\(self.requestID).json"
    }

    /// The request file body: `{schemaVersion, requestId, provider, targetIdSuffix, targetEmail, requestedAt}`.
    public func encoded() throws -> Data {
        let object: [String: Any] = [
            "schemaVersion": Self.schemaVersion,
            "requestId": self.requestID,
            "provider": self.provider.rawValue,
            "targetIdSuffix": self.targetIDSuffix,
            "targetEmail": self.targetEmail,
            "requestedAt": Self.timestamp(self.requestedAt),
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

public enum OpenCodexHubRequestError: LocalizedError, Equatable, Sendable {
    case invalidRequestID
    case invalidTarget
    case requestTooLarge
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRequestID:
            "The switch request id is not valid."
        case .invalidTarget:
            "The account cannot be addressed by a switch request."
        case .requestTooLarge:
            "The switch request is larger than the hub accepts."
        case let .writeFailed(details):
            "The switch request could not be written: \(details)"
        }
    }
}

/// Writes switch requests atomically: a dot-prefixed temporary file in the requests
/// directory (which the hub skips) renamed into place, so the hub never reads a partial file.
public enum OpenCodexHubSwitchRequestWriter {
    public static let requestsDirectoryName = "opencodex-hub-requests"

    /// The requests directory sits next to the snapshot file
    /// (`~/.swift-app-state/opencodex-hub-accounts.json` → `~/.swift-app-state/opencodex-hub-requests`).
    public static func requestsDirectory(forSnapshotPath snapshotPath: String) -> URL {
        URL(fileURLWithPath: (snapshotPath as NSString).expandingTildeInPath)
            .deletingLastPathComponent()
            .appendingPathComponent(self.requestsDirectoryName, isDirectory: true)
    }

    @discardableResult
    public static func write(
        _ request: OpenCodexHubSwitchRequest,
        to directory: URL,
        fileManager: FileManager = .default) throws -> URL
    {
        guard OpenCodexHubSwitchRequest.isValidRequestID(request.requestID) else {
            throw OpenCodexHubRequestError.invalidRequestID
        }
        guard !request.targetIDSuffix.isEmpty, !request.targetEmail.isEmpty else {
            throw OpenCodexHubRequestError.invalidTarget
        }
        let data = try request.encoded()
        guard data.count <= OpenCodexHubSwitchRequest.maximumFileBytes else {
            throw OpenCodexHubRequestError.requestTooLarge
        }
        let destination = directory.appendingPathComponent(request.fileName)
        let temporary = directory.appendingPathComponent(".\(request.fileName).tmp")
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            if fileManager.fileExists(atPath: temporary.path) {
                try fileManager.removeItem(at: temporary)
            }
            guard fileManager.createFile(
                atPath: temporary.path,
                contents: data,
                attributes: [.posixPermissions: 0o600])
            else {
                throw OpenCodexHubRequestError.writeFailed("cannot create \(temporary.lastPathComponent)")
            }
            // rename(2) replaces atomically within one directory.
            guard rename(temporary.path, destination.path) == 0 else {
                let code = errno
                try? fileManager.removeItem(at: temporary)
                throw OpenCodexHubRequestError.writeFailed(String(cString: strerror(code)))
            }
        } catch let error as OpenCodexHubRequestError {
            throw error
        } catch {
            throw OpenCodexHubRequestError.writeFailed(error.localizedDescription)
        }
        return destination
    }
}
