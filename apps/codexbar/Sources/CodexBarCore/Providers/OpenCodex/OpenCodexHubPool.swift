import Foundation

/// The opencodex pools CodexBar reads: one per provider card.
public enum OpenCodexHubProvider: String, CaseIterable, Sendable, Codable {
    case anthropic
    case openai
    case xai

    /// The CodexBar provider whose card shows this pool.
    public var usageProvider: UsageProvider {
        switch self {
        case .anthropic: .claude
        case .openai: .codex
        case .xai: .grok
        }
    }

    public init?(usageProvider: UsageProvider) {
        switch usageProvider {
        case .claude: self = .anthropic
        case .codex: self = .openai
        case .grok: self = .xai
        default: return nil
        }
    }

    /// The fixed list argument array (`ocx account list <provider> --quota --json`).
    public var listArguments: [String] {
        ["account", "list", self.rawValue, "--quota", "--json"]
    }
}

public struct OpenCodexHubQuotaWindow: Equatable, Sendable {
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(usedPercent: Double, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

public struct OpenCodexHubCustomWindow: Equatable, Sendable {
    /// Display-only label (for example a model-scoped week); never identity.
    public let label: String
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(label: String, usedPercent: Double, resetsAt: Date?) {
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

/// The union of the quota windows opencodex reports; a provider omits the windows it does not have
/// (Anthropic: 5-hour, weekly and custom; OpenAI: weekly and monthly; xAI: weekly).
public struct OpenCodexHubQuota: Equatable, Sendable {
    public let fiveHour: OpenCodexHubQuotaWindow?
    public let weekly: OpenCodexHubQuotaWindow?
    public let monthly: OpenCodexHubQuotaWindow?
    public let custom: [OpenCodexHubCustomWindow]
    public let updatedAt: Date?

    public init(
        fiveHour: OpenCodexHubQuotaWindow? = nil,
        weekly: OpenCodexHubQuotaWindow? = nil,
        monthly: OpenCodexHubQuotaWindow? = nil,
        custom: [OpenCodexHubCustomWindow] = [],
        updatedAt: Date? = nil)
    {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.monthly = monthly
        self.custom = custom
        self.updatedAt = updatedAt
    }

    public var isEmpty: Bool {
        self.fiveHour == nil && self.weekly == nil && self.monthly == nil && self.custom.isEmpty
    }

    /// The highest used percentage across all windows, or nil without windows.
    public var highestUsedPercent: Double? {
        let values = [self.fiveHour, self.weekly, self.monthly].compactMap { $0?.usedPercent }
            + self.custom.map(\.usedPercent)
        return values.max()
    }
}

/// One account of an opencodex pool. Only display data: the masked email, the label,
/// the last four characters of the opencodex id and state flags. Tokens and full ids
/// never enter this model.
public struct OpenCodexHubAccount: Equatable, Sendable {
    /// The last characters of the opencodex account id; addresses a switch request together with `email`.
    public let idSuffix: String?
    public let label: String?
    /// Masked by opencodex (`t***m@example.com`).
    public let email: String
    public let isActive: Bool
    public let isPaused: Bool
    public let needsReauth: Bool
    public let health: String?
    public let quotaUnavailable: Bool
    public let quota: OpenCodexHubQuota

    public init(
        idSuffix: String?,
        label: String?,
        email: String,
        isActive: Bool,
        isPaused: Bool = false,
        needsReauth: Bool = false,
        health: String? = nil,
        quotaUnavailable: Bool = false,
        quota: OpenCodexHubQuota = OpenCodexHubQuota())
    {
        self.idSuffix = idSuffix
        self.label = label
        self.email = email
        self.isActive = isActive
        self.isPaused = isPaused
        self.needsReauth = needsReauth
        self.health = health
        self.quotaUnavailable = quotaUnavailable
        self.quota = quota
    }

    /// The label when it says more than the email (for example a plan or seat name).
    public var displayAlias: String? {
        guard let label, label != self.email else { return nil }
        return label
    }

    /// opencodex refuses explicit switches to accounts that need a new login.
    public var requiresReauthentication: Bool {
        self.needsReauth || self.health == "Reauthentication required" || self.health == "Verification required"
    }

    /// Whether a switch to this account can be requested at all (the hub decides the rest).
    public var isSwitchTarget: Bool {
        !self.isActive && !self.isPaused && !self.requiresReauthentication
    }

    /// Used at or above the hub's automatic switch threshold: the hub may move away again soon.
    public var isNearLimit: Bool {
        (self.quota.highestUsedPercent ?? 0) >= OpenCodexHubPool.nearLimitPercent
    }
}

/// The outcome of a switch request as the hub reports it in `state.lastRequests`.
public struct OpenCodexHubRequestResult: Equatable, Sendable {
    public enum Outcome: String, Sendable {
        case done
        case refused
        case failed
    }

    public let requestID: String
    public let provider: OpenCodexHubProvider?
    public let outcome: Outcome
    /// Machine code (`switched`, `superseded`, `openai_hub_only`, …).
    public let code: String?
    /// Human-readable reason written by the hub.
    public let reason: String?
    public let at: Date?

    public init(
        requestID: String,
        provider: OpenCodexHubProvider?,
        outcome: Outcome,
        code: String? = nil,
        reason: String? = nil,
        at: Date? = nil)
    {
        self.requestID = requestID
        self.provider = provider
        self.outcome = outcome
        self.code = code
        self.reason = reason
        self.at = at
    }
}

/// Where a pool was read: the live `ocx` list on the hub itself, the hub's snapshot file, or the read-only
/// list a Mac linked to the hub gets from its own `ocx` when no current snapshot is available.
public enum OpenCodexHubPoolOrigin: Equatable, Sendable {
    case hubLocal
    /// `hubName` is the managing machine when the snapshot names it; `updatedAt` is when the hub wrote it.
    case snapshot(hubName: String?, updatedAt: Date?)
    /// opencodex on a linked Mac answers `ocx account list` from the hub's cache but refuses
    /// `ocx account use`; the pool is shown for reading only. `hubName` comes from an older snapshot, if any.
    case linkedCopy(hubName: String?)
}

/// One provider pool of an opencodex hub.
public struct OpenCodexHubPool: Equatable, Sendable {
    /// A snapshot older than this is shown as stale.
    public static let staleInterval: TimeInterval = 5 * 60
    /// opencodex's automatic switch threshold; switching to an account at or above it is allowed but warned about.
    public static let nearLimitPercent: Double = 80

    public let provider: OpenCodexHubProvider
    public let accounts: [OpenCodexHubAccount]
    /// Whether this Mac may switch the pool (directly on the hub, or by request).
    public let switchable: Bool
    /// Why switching is not available here, when the hub says so.
    public let switchReason: String?
    public let origin: OpenCodexHubPoolOrigin
    public let lastRequests: [OpenCodexHubRequestResult]

    public init(
        provider: OpenCodexHubProvider,
        accounts: [OpenCodexHubAccount],
        switchable: Bool,
        switchReason: String? = nil,
        origin: OpenCodexHubPoolOrigin,
        lastRequests: [OpenCodexHubRequestResult] = [])
    {
        self.provider = provider
        self.accounts = accounts
        self.switchable = switchable
        self.switchReason = switchReason
        self.origin = origin
        self.lastRequests = lastRequests
    }

    public var activeAccount: OpenCodexHubAccount? {
        self.accounts.first(where: \.isActive)
    }

    public var isHubLocal: Bool {
        self.origin == .hubLocal
    }

    public var hubName: String? {
        switch self.origin {
        case .hubLocal: nil
        case let .snapshot(hubName, _): hubName
        case let .linkedCopy(hubName): hubName
        }
    }

    /// A read-only list from a linked Mac's own `ocx`: switching needs a current hub snapshot.
    public var isLinkedCopy: Bool {
        if case .linkedCopy = self.origin { return true }
        return false
    }

    public var snapshotUpdatedAt: Date? {
        if case let .snapshot(_, updatedAt) = self.origin { return updatedAt }
        return nil
    }

    /// A snapshot is stale when the hub has not rewritten it for `staleInterval` (or never said when it did).
    public func isStale(now: Date = Date()) -> Bool {
        guard case let .snapshot(_, updatedAt) = self.origin else { return false }
        guard let updatedAt else { return true }
        return now.timeIntervalSince(updatedAt) > Self.staleInterval
    }

    /// Whether `account` can be switched to from this Mac.
    public func canSwitch(to account: OpenCodexHubAccount) -> Bool {
        guard self.switchable, account.isSwitchTarget else { return false }
        // A switch names the target by id suffix and masked email. A live row without a suffix has an id
        // `ocx account use` cannot take; a snapshot row without one cannot be named in a request.
        return account.idSuffix != nil
    }
}

/// A switch this Mac asked the hub for and has not seen the result of yet.
public struct OpenCodexHubPendingSwitch: Equatable, Sendable {
    /// Requests older than this are past the hub's acceptance window and will never be processed.
    public static let expiryInterval: TimeInterval = 11 * 60

    public enum Resolution: Equatable, Sendable {
        case pending
        case done
        case refused(code: String?, reason: String?)
        case failed(code: String?, reason: String?)
        case expired
    }

    public let request: OpenCodexHubSwitchRequest

    public init(request: OpenCodexHubSwitchRequest) {
        self.request = request
    }

    /// Resolves the request against a newer pool: a `lastRequests` entry wins; otherwise the target becoming
    /// active means it was switched.
    public func resolution(in pool: OpenCodexHubPool, now: Date = Date()) -> Resolution {
        if let result = pool.lastRequests.first(where: { $0.requestID == self.request.requestID }) {
            switch result.outcome {
            case .done: return .done
            case .refused: return .refused(code: result.code, reason: result.reason)
            case .failed: return .failed(code: result.code, reason: result.reason)
            }
        }
        if let active = pool.activeAccount,
           active.idSuffix == self.request.targetIDSuffix,
           active.email == self.request.targetEmail
        {
            return .done
        }
        if now.timeIntervalSince(self.request.requestedAt) > Self.expiryInterval {
            return .expired
        }
        return .pending
    }
}
