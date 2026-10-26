import Foundation

/// Closed error vocabulary: never carries process output, server bodies, paths, or credentials.
public enum OpenCodexAccessError: String, Error, LocalizedError, Sendable {
    case executableMissing, unsupportedRole, serverStopped, invalidResponse, outputTooLarge
    case communicationFailed, permissionDenied, notFound, invalidName, invalidID
    case renameUnsupported, confirmationRequired, mutationInProgress, invalidDashboardURL

    public var errorDescription: String? {
        switch self {
        case .executableMissing: "Opencodex 실행 파일을 찾을 수 없습니다."
        case .unsupportedRole: "이 기기에서는 관리할 수 없습니다. 허브에서 관리해 주세요."
        case .serverStopped: "Opencodex 서버가 중지되어 있습니다."
        case .invalidResponse: "Opencodex 응답 형식이 올바르지 않습니다."
        case .outputTooLarge: "Opencodex 응답 크기가 제한을 초과했습니다."
        case .communicationFailed: "Opencodex와 통신하지 못했습니다."
        case .permissionDenied: "관리 권한이 거부되었습니다."
        case .notFound: "키를 찾을 수 없습니다. 목록을 새로고침해 주세요."
        case .invalidName: "제어 문자나 옵션이 아닌 1~64자의 이름을 입력해 주세요."
        case .invalidID: "키 식별자가 올바르지 않습니다. 목록을 새로고침해 주세요."
        case .renameUnsupported: "이 Opencodex 설치에서는 안전한 이름 변경을 지원하지 않습니다."
        case .confirmationRequired: "변경 결과를 확인해야 합니다. 자동으로 다시 시도하지 않습니다."
        case .mutationInProgress: "다른 키 변경이 진행 중입니다."
        case .invalidDashboardURL: "대시보드 주소가 안전한 HTTP(S) 주소가 아닙니다."
        }
    }
}

public struct OpenCodexAccessStatus: Equatable, Sendable {
    public let schemaVersion: Int
    public let runtimeRole: OpenCodexRuntimeRole
    public let proxyRunning: Bool
    public let dashboardURL: URL?

    public init(schemaVersion: Int = 1, runtimeRole: OpenCodexRuntimeRole, proxyRunning: Bool, dashboardURL: URL?) {
        self.schemaVersion = schemaVersion
        self.runtimeRole = runtimeRole
        self.proxyRunning = proxyRunning
        self.dashboardURL = dashboardURL
    }

    public func requireLocalManagement() throws {
        guard self.schemaVersion == 1 else { throw OpenCodexAccessError.invalidResponse }
        guard self.runtimeRole.ownsAccounts else { throw OpenCodexAccessError.unsupportedRole }
        guard self.proxyRunning else { throw OpenCodexAccessError.serverStopped }
    }

    public func dashboardDestination() throws -> OpenCodexDashboardDestination {
        try self.requireLocalManagement()
        guard let dashboardURL else { throw OpenCodexAccessError.invalidDashboardURL }
        return try OpenCodexDashboardDestination(dashboardURL.absoluteString)
    }
}

public enum OpenCodexAccessUsage: Equatable, Sendable {
    case unavailable
    case ambiguous
    /// Zero is a server-reported value. A missing number remains nil, never fabricated as zero.
    case recorded(requests7d: Double?, totalRequests: Double?, lastUsedAt: Date?)

    public var hasNoRecordedUsage: Bool {
        if case let .recorded(_, total, lastUsed) = self { return total == 0 && lastUsed == nil }
        return false
    }
}

public struct OpenCodexAccessKey: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let prefix: String
    public let createdAt: Date
    public let allowedProviders: [String]?
    public let allowedModels: [String]?
    public let usage: OpenCodexAccessUsage

    public init(
        id: String,
        name: String,
        prefix: String,
        createdAt: Date,
        allowedProviders: [String]? = nil,
        allowedModels: [String]? = nil,
        usage: OpenCodexAccessUsage = .unavailable)
    {
        self.id = id
        self.name = name
        self.prefix = prefix
        self.createdAt = createdAt
        self.allowedProviders = allowedProviders
        self.allowedModels = allowedModels
        self.usage = usage
    }
}

public struct OpenCodexAccessKeyList: Equatable, Sendable {
    public let keys: [OpenCodexAccessKey]
    public let attributionSince: Date?
    public let historyTruncated: Bool
    public let usageIncomplete: Bool
    /// Server-provided metadata; UI must render as text, never as an error diagnostic.
    public let usageIncompleteReason: String?

    public init(
        keys: [OpenCodexAccessKey],
        attributionSince: Date? = nil,
        historyTruncated: Bool = false,
        usageIncomplete: Bool = false,
        usageIncompleteReason: String? = nil)
    {
        self.keys = keys
        self.attributionSince = attributionSince
        self.historyTruncated = historyTruncated
        self.usageIncomplete = usageIncomplete
        self.usageIncompleteReason = usageIncompleteReason
    }
}

/// Not Codable, Equatable, or reflected into general state. The result owner releases it on dismissal.
public final class OpenCodexAccessSecret: Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    private let value: String
    public init(_ value: String) { self.value = value }
    public func reveal() -> String { self.value }
    public var description: String {
        "<redacted>"
    }

    public var debugDescription: String {
        self.description
    }

    public var customMirror: Mirror {
        Mirror(self, children: [:])
    }
}

public struct OpenCodexAccessCreatedKey: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let id: String
    public let name: String
    public let createdAt: Date
    public let secret: OpenCodexAccessSecret

    public init(id: String, name: String, createdAt: Date, secret: OpenCodexAccessSecret) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.secret = secret
    }

    public var description: String {
        "OpenCodexAccessCreatedKey(<redacted>)"
    }

    public var debugDescription: String {
        self.description
    }
}

public struct OpenCodexAccessRenamedKey: Equatable, Sendable {
    public let id: String
    public let name: String
    public let createdAt: Date
    public let allowedProviders: [String]?
    public let allowedModels: [String]?

    public init(
        id: String,
        name: String,
        createdAt: Date,
        allowedProviders: [String]? = nil,
        allowedModels: [String]? = nil)
    {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.allowedProviders = allowedProviders
        self.allowedModels = allowedModels
    }
}

public enum OpenCodexAccessName {
    public static func validate(_ raw: String) throws -> String {
        guard raw.rangeOfCharacter(from: .controlCharacters) == nil else { throw OpenCodexAccessError.invalidName }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = name.replacingOccurrences(of: "[‐-―−]", with: "-", options: .regularExpression)
        // 2.88.0 consumes JSON options anywhere in argv, including the bare token "json".
        let optionBody = normalized.drop(while: { $0 == "-" })
        guard !name.isEmpty, name.utf16.count <= 64, !normalized.hasPrefix("-"),
              optionBody != "json", !optionBody.hasPrefix("json=")
        else { throw OpenCodexAccessError.invalidName }
        return name
    }
}
