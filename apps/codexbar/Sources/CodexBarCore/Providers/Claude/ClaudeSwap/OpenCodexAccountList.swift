import Foundation

/// The result of translating an opencodex Anthropic pool: the shared list model
/// plus, for live hub lists, the opencodex account id of each slot.
public struct OpenCodexAccountListResult: Equatable, Sendable {
    public let list: ClaudeSwapAccountList
    /// Slot number to opencodex account id. Held in memory only to address
    /// `ocx account use`; never persisted, logged or shown. Empty for snapshots; a slot whose id
    /// `ocx account use` cannot take has no entry.
    public let accountIDs: [Int: String]
    /// The provider-neutral pool the list was translated from.
    public let pool: OpenCodexHubPool

    public init(list: ClaudeSwapAccountList, accountIDs: [Int: String], pool: OpenCodexHubPool) {
        self.list = list
        self.accountIDs = accountIDs
        self.pool = pool
    }
}

public enum OpenCodexAccountListError: LocalizedError, Equatable, Sendable {
    case notJSONObject
    case malformedShape(String)
    /// The live list is not available on this Mac (for example a client linked to a hub).
    case hubAccountsUnavailable(String)
    case snapshotUnreadable(String)
    /// This Mac is not the hub and has no current hub snapshot to ask for a switch through.
    case snapshotNotCurrent
    case accountNotFound(slot: Int)
    case accountChanged(slot: Int)
    case switchNotAllowed(String?)
    case switchFailed(String)
    case mismatchedTarget

    public var errorDescription: String? {
        switch self {
        case .notJSONObject:
            "opencodex returned output that is not a JSON object."
        case let .malformedShape(details):
            "opencodex account list is malformed: \(details)"
        case let .hubAccountsUnavailable(details):
            "This Mac cannot list the opencodex hub's Claude accounts (\(details)). " +
                "Accounts are managed on the hub; set a hub snapshot file to view them here."
        case let .snapshotUnreadable(details):
            "The opencodex hub snapshot could not be read: \(details)"
        case .snapshotNotCurrent:
            OpenCodexHubReaderError.snapshotNotCurrent.errorDescription
        case let .accountNotFound(slot):
            "opencodex no longer lists Claude account \(slot); refresh and try again."
        case let .accountChanged(slot):
            "opencodex lists a different account in slot \(slot) now; refresh and try again."
        case let .switchNotAllowed(reason):
            reason ?? "This Claude pool cannot be switched from this Mac."
        case let .switchFailed(details):
            "opencodex could not switch the account: \(details)"
        case .mismatchedTarget:
            "opencodex reported a different active account than the one CodexBar requested."
        }
    }

    init(_ error: OpenCodexHubPoolError) {
        switch error {
        case .notJSONObject: self = .notJSONObject
        case let .malformedShape(details): self = .malformedShape(details)
        case let .providerMissing(provider):
            self = .snapshotUnreadable("the snapshot has no \(provider.rawValue) accounts")
        }
    }

    init(_ error: OpenCodexHubReaderError, slot: Int = 0) {
        switch error {
        case let .hubAccountsUnavailable(details): self = .hubAccountsUnavailable(details)
        case let .noHubSource(details): self = .hubAccountsUnavailable(details)
        case let .snapshotUnreadable(details): self = .snapshotUnreadable(details)
        case .snapshotNotCurrent: self = .snapshotNotCurrent
        case .accountNotFound: self = .accountNotFound(slot: slot)
        case let .switchNotAllowed(reason): self = .switchNotAllowed(reason)
        case let .switchFailed(details): self = .switchFailed(details)
        case .mismatchedTarget: self = .mismatchedTarget
        }
    }
}

/// Translates the opencodex hub's Anthropic pool (`ocx account list anthropic --quota --json`, or the
/// hub snapshot) into the shared claude-swap list model.
///
/// Slots are assigned 1, 2, … in the order opencodex lists the accounts; a switch re-reads the list
/// and checks the slot still holds the same (masked) account.
public enum OpenCodexAccountListParser {
    public static let provider = OpenCodexHubProvider.anthropic.rawValue
    public static let listArguments = OpenCodexHubProvider.anthropic.listArguments

    /// Parses a live hub list (`{accounts, notes}`).
    public static func parseLiveList(_ data: Data) throws -> OpenCodexAccountListResult {
        do {
            return try self.result(fromLive: OpenCodexHubPoolParser.parseLiveList(data, provider: .anthropic))
        } catch let error as OpenCodexHubPoolError {
            throw OpenCodexAccountListError(error)
        }
    }

    /// Parses the hub snapshot: schema 2 (`state.providers.anthropic`) or schema 1 (`state.accounts`),
    /// or the bare list shape with optional `fetchedAt` and `hub`. Snapshot lists switch by request
    /// when the hub marks the pool switchable for this Mac.
    public static func parseSnapshot(_ data: Data) throws -> OpenCodexAccountListResult {
        do {
            return try self.result(fromSnapshot: OpenCodexHubPoolParser.parseSnapshot(data, provider: .anthropic))
        } catch let error as OpenCodexHubPoolError {
            throw OpenCodexAccountListError(error)
        }
    }

    /// The shared list model for an Anthropic pool however it was read.
    public static func result(from read: OpenCodexHubPoolRead) -> OpenCodexAccountListResult {
        switch read {
        case let .live(live): self.result(fromLive: live)
        case let .snapshot(snapshot): self.result(fromSnapshot: snapshot)
        case let .linkedCopy(pool): self.result(fromLinkedCopy: pool)
        }
    }

    static func result(fromLive live: OpenCodexHubLivePool) -> OpenCodexAccountListResult {
        var accountIDs: [Int: String] = [:]
        for (index, id) in live.accountIDs.enumerated() {
            guard let id else { continue }
            accountIDs[index + 1] = id
        }
        return OpenCodexAccountListResult(
            list: self.list(from: live.pool, defaultFetchedAt: nil, remoteCopy: nil),
            accountIDs: accountIDs,
            pool: live.pool)
    }

    static func result(fromSnapshot snapshot: OpenCodexHubSnapshotPool) -> OpenCodexAccountListResult {
        let fetchedAt = snapshot.fetchedAt ?? snapshot.pool.snapshotUpdatedAt
        let remoteCopy = ClaudeSwapRemoteCopy(
            managerName: snapshot.pool.hubName ?? OpenCodexHubDefaults.hubName,
            fetchedAt: fetchedAt,
            pool: snapshot.pool)
        return OpenCodexAccountListResult(
            list: self.list(from: snapshot.pool, defaultFetchedAt: fetchedAt, remoteCopy: remoteCopy),
            accountIDs: [:],
            pool: snapshot.pool)
    }

    /// A linked Mac's own read-only list: shown like a hub copy, never switched from here.
    static func result(fromLinkedCopy pool: OpenCodexHubPool) -> OpenCodexAccountListResult {
        let remoteCopy = ClaudeSwapRemoteCopy(
            managerName: pool.hubName ?? OpenCodexHubDefaults.hubName,
            fetchedAt: nil,
            pool: pool)
        return OpenCodexAccountListResult(
            list: self.list(from: pool, defaultFetchedAt: nil, remoteCopy: remoteCopy),
            accountIDs: [:],
            pool: pool)
    }

    public static func parseSwitchReceipt(_ data: Data) throws -> String {
        do {
            return try OpenCodexHubPoolParser.parseSwitchReceipt(data)
        } catch let error as OpenCodexHubPoolError {
            throw OpenCodexAccountListError(error)
        }
    }

    static func isValidAccountID(_ id: String) -> Bool {
        OpenCodexHubPoolParser.isValidAccountID(id)
    }

    static func date(_ raw: Any?) -> Date? {
        OpenCodexHubPoolParser.date(raw)
    }

    // MARK: - Private

    private static func list(
        from pool: OpenCodexHubPool,
        defaultFetchedAt: Date?,
        remoteCopy: ClaudeSwapRemoteCopy?) -> ClaudeSwapAccountList
    {
        let rows = pool.accounts.enumerated().map { index, account in
            self.row(account, slot: index + 1, defaultFetchedAt: defaultFetchedAt)
        }
        return ClaudeSwapAccountList(
            activeAccountNumber: rows.first(where: \.isActive)?.number,
            accounts: rows,
            supportsAccountSwitching: pool.switchable,
            remoteCopy: remoteCopy)
    }

    private static func row(
        _ account: OpenCodexHubAccount,
        slot: Int,
        defaultFetchedAt: Date?) -> ClaudeSwapAccountRow
    {
        let quota = account.quota
        let fiveHour = quota.fiveHour.map { ClaudeSwapUsageWindow(usedPercent: $0.usedPercent, resetsAt: $0.resetsAt) }
        let weekly = quota.weekly.map { ClaudeSwapUsageWindow(usedPercent: $0.usedPercent, resetsAt: $0.resetsAt) }
        let scoped = quota.custom.map {
            ClaudeSwapScopedUsageWindow(name: $0.label, usedPercent: $0.usedPercent, resetsAt: $0.resetsAt)
        }
        return ClaudeSwapAccountRow(
            number: slot,
            email: account.email,
            alias: account.displayAlias,
            isActive: account.isActive,
            usageStatus: self.usageStatus(account, hasWindows: fiveHour != nil || weekly != nil || !scoped.isEmpty),
            fiveHour: fiveHour,
            sevenDay: weekly,
            scoped: scoped,
            usageFetchedAt: quota.updatedAt ?? defaultFetchedAt,
            isDisabled: account.isPaused)
    }

    private static func usageStatus(_ account: OpenCodexHubAccount, hasWindows: Bool) -> ClaudeSwapUsageStatus {
        if account.requiresReauthentication { return .reloginRequired }
        if account.health == "Refresh failed" { return .tokenExpired }
        if account.quotaUnavailable || !hasWindows { return .unavailable }
        return .ok
    }
}
