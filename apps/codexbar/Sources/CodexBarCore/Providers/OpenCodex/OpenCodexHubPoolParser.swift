import CoreFoundation
import Foundation

public enum OpenCodexHubPoolError: LocalizedError, Equatable, Sendable {
    case notJSONObject
    case malformedShape(String)
    /// The snapshot has no pool for this provider.
    case providerMissing(OpenCodexHubProvider)

    public var errorDescription: String? {
        switch self {
        case .notJSONObject:
            "opencodex returned output that is not a JSON object."
        case let .malformedShape(details):
            "opencodex account list is malformed: \(details)"
        case let .providerMissing(provider):
            "The opencodex hub snapshot has no \(provider.rawValue) accounts."
        }
    }
}

/// A live `ocx account list <provider> --quota --json` result. `accountIDs[i]` is the full opencodex id of
/// `pool.accounts[i]`; it is held in memory only to address `ocx account use` and never persisted or shown.
/// It is nil for a row whose id cannot be passed to `ocx account use` safely; that account is listed but
/// cannot be switched to.
public struct OpenCodexHubLivePool: Equatable, Sendable {
    public let pool: OpenCodexHubPool
    public let accountIDs: [String?]

    public init(pool: OpenCodexHubPool, accountIDs: [String?]) {
        self.pool = pool
        self.accountIDs = accountIDs
    }
}

/// A hub snapshot pool plus the time the hub read the accounts (`state.fetchedAt`).
public struct OpenCodexHubSnapshotPool: Equatable, Sendable {
    public let pool: OpenCodexHubPool
    public let fetchedAt: Date?

    public init(pool: OpenCodexHubPool, fetchedAt: Date?) {
        self.pool = pool
        self.fetchedAt = fetchedAt
    }
}

/// Strict, allow-listed reader of opencodex account lists and of the hub snapshot file.
///
/// Only `id` (live lists, to address a switch), `idSuffix`, `email`/`label` (already masked by opencodex),
/// the state flags and the quota windows are read. Tokens, keys and other fields are ignored.
///
/// Snapshot file (`~/.swift-app-state/opencodex-hub-accounts.json` on the default layout):
/// `{app, updatedAt, state}` where `state.schemaVersion` 2 carries `state.providers.<provider>
/// {switchable, switchReason, accounts}` and `state.lastRequests`; schema 1 carries only the Anthropic
/// `state.accounts`, which schema 2 keeps alongside for older readers.
public enum OpenCodexHubPoolParser {
    static let maxAccountIDLength = 128
    static let idSuffixLength = 4

    // MARK: Live list

    public static func parseLiveList(_ data: Data, provider: OpenCodexHubProvider) throws -> OpenCodexHubLivePool {
        let object = try self.jsonObject(data)
        guard let rawAccounts = object["accounts"] as? [Any] else {
            throw OpenCodexHubPoolError.malformedShape("missing accounts array")
        }
        var accounts: [OpenCodexHubAccount] = []
        var ids: [String?] = []
        var seen: Set<String> = []
        for rawRow in rawAccounts {
            guard let row = rawRow as? [String: Any] else {
                throw OpenCodexHubPoolError.malformedShape("account row is not an object")
            }
            // Only this provider's pool feeds its card; other providers never leak in.
            if let rowProvider = row["provider"] as? String, rowProvider != provider.rawValue { continue }
            // A row whose id is unusable (or repeats an earlier row's) stays visible without a switch target
            // instead of failing the whole pool.
            var id = row["id"] as? String
            if let candidate = id, !self.isValidAccountID(candidate) || !seen.insert(candidate).inserted {
                id = nil
            }
            ids.append(id)
            try accounts.append(self.parseAccount(
                row,
                index: accounts.count + 1,
                idSuffix: id.map { String($0.suffix(self.idSuffixLength)) }))
        }
        try self.requireSingleActive(accounts)
        let pool = OpenCodexHubPool(provider: provider, accounts: accounts, switchable: true, origin: .hubLocal)
        return OpenCodexHubLivePool(pool: pool, accountIDs: ids)
    }

    /// `true` when the data is a JSON object with an `accounts` member, i.e. opencodex
    /// answered with a list rather than an error on stderr.
    public static func looksLikeAccountList(_ data: Data) -> Bool {
        guard let object = try? self.jsonObject(data) else { return false }
        return object["accounts"] != nil
    }

    /// `ocx account use <provider> <id> --json` prints `{ok, provider, type, activeId}`.
    public static func parseSwitchReceipt(_ data: Data) throws -> String {
        let object = try self.jsonObject(data)
        guard object["ok"] as? Bool == true else {
            throw OpenCodexHubPoolError.malformedShape("switch receipt is not ok")
        }
        guard let activeID = object["activeId"] as? String, !activeID.isEmpty else {
            throw OpenCodexHubPoolError.malformedShape("switch receipt has no activeId")
        }
        return activeID
    }

    // MARK: Snapshot

    public static func parseSnapshot(_ data: Data, provider: OpenCodexHubProvider) throws -> OpenCodexHubSnapshotPool {
        let envelope = try self.jsonObject(data)
        let state = envelope["state"] as? [String: Any] ?? envelope
        let fetchedAt = self.date(state["fetchedAt"])
        let updatedAt = self.date(envelope["updatedAt"]) ?? self.date(state["updatedAt"]) ?? fetchedAt
        let hubName = self.trimmed(state["hub"]) ?? self.trimmed(envelope["hub"])
        let origin = OpenCodexHubPoolOrigin.snapshot(hubName: hubName, updatedAt: updatedAt)
        let lastRequests = self.lastRequests(state["lastRequests"])

        if let providers = state["providers"] as? [String: Any] {
            guard let rawPool = providers[provider.rawValue] as? [String: Any] else {
                throw OpenCodexHubPoolError.providerMissing(provider)
            }
            guard let rawAccounts = rawPool["accounts"] as? [Any] else {
                throw OpenCodexHubPoolError.malformedShape("\(provider.rawValue) pool has no accounts array")
            }
            let accounts = try self.parseSnapshotAccounts(rawAccounts, provider: provider)
            let pool = OpenCodexHubPool(
                provider: provider,
                accounts: accounts,
                switchable: rawPool["switchable"] as? Bool ?? false,
                switchReason: self.trimmed(rawPool["switchReason"]),
                origin: origin,
                lastRequests: lastRequests.filter { $0.provider == nil || $0.provider == provider })
            return OpenCodexHubSnapshotPool(pool: pool, fetchedAt: fetchedAt)
        }
        // Schema 1: only the Anthropic pool, read-only.
        guard provider == .anthropic else { throw OpenCodexHubPoolError.providerMissing(provider) }
        guard let rawAccounts = state["accounts"] as? [Any] else {
            throw OpenCodexHubPoolError.malformedShape("missing accounts array")
        }
        let accounts = try self.parseSnapshotAccounts(rawAccounts, provider: provider)
        let pool = OpenCodexHubPool(provider: provider, accounts: accounts, switchable: false, origin: origin)
        return OpenCodexHubSnapshotPool(pool: pool, fetchedAt: fetchedAt)
    }

    // MARK: - Private

    private static func parseSnapshotAccounts(
        _ rawAccounts: [Any],
        provider: OpenCodexHubProvider) throws -> [OpenCodexHubAccount]
    {
        var accounts: [OpenCodexHubAccount] = []
        for rawRow in rawAccounts {
            guard let row = rawRow as? [String: Any] else {
                throw OpenCodexHubPoolError.malformedShape("account row is not an object")
            }
            if let rowProvider = row["provider"] as? String, rowProvider != provider.rawValue { continue }
            let suffix = self.trimmed(row["idSuffix"]).flatMap { self.isValidIDSuffix($0) ? $0 : nil }
            try accounts.append(self.parseAccount(row, index: accounts.count + 1, idSuffix: suffix))
        }
        try self.requireSingleActive(accounts)
        return accounts
    }

    private static func requireSingleActive(_ accounts: [OpenCodexHubAccount]) throws {
        guard accounts.count(where: \.isActive) <= 1 else {
            throw OpenCodexHubPoolError.malformedShape("more than one active account")
        }
    }

    private static func parseAccount(
        _ row: [String: Any],
        index: Int,
        idSuffix: String?) throws -> OpenCodexHubAccount
    {
        guard let isActive = row["active"] as? Bool else {
            throw OpenCodexHubPoolError.malformedShape("account \(index) has no active flag")
        }
        let label = self.trimmed(row["label"])
        return OpenCodexHubAccount(
            idSuffix: idSuffix,
            label: label,
            email: self.trimmed(row["email"]) ?? label ?? "",
            isActive: isActive,
            isPaused: row["paused"] as? Bool ?? false,
            needsReauth: row["needsReauth"] as? Bool ?? false,
            health: self.trimmed(row["health"]),
            quotaUnavailable: row["quotaUnavailable"] as? Bool ?? false,
            quota: self.quota(row["quota"] as? [String: Any]))
    }

    private static func quota(_ raw: [String: Any]?) -> OpenCodexHubQuota {
        guard let raw else { return OpenCodexHubQuota() }
        return OpenCodexHubQuota(
            fiveHour: self.window(percent: raw["fiveHourPercent"], resetsAt: raw["fiveHourResetAt"]),
            weekly: self.window(percent: raw["weeklyPercent"], resetsAt: raw["weeklyResetAt"]),
            monthly: self.window(percent: raw["monthlyPercent"], resetsAt: raw["monthlyResetAt"]),
            custom: self.customWindows(raw["customWindows"]),
            updatedAt: self.date(raw["updatedAt"]))
    }

    private static func window(percent rawPercent: Any?, resetsAt rawResetsAt: Any?) -> OpenCodexHubQuotaWindow? {
        guard let percent = self.finiteDouble(rawPercent) else { return nil }
        return OpenCodexHubQuotaWindow(usedPercent: min(max(percent, 0), 100), resetsAt: self.date(rawResetsAt))
    }

    /// `quota.customWindows` (for example a model-scoped week) are additive; malformed rows are skipped.
    private static func customWindows(_ raw: Any?) -> [OpenCodexHubCustomWindow] {
        guard let rows = raw as? [Any] else { return [] }
        return rows.compactMap { rawRow in
            guard let row = rawRow as? [String: Any],
                  let label = self.trimmed(row["label"]),
                  let percent = self.finiteDouble(row["percent"])
            else { return nil }
            return OpenCodexHubCustomWindow(
                label: label,
                usedPercent: min(max(percent, 0), 100),
                resetsAt: self.date(row["resetAt"]))
        }
    }

    private static func lastRequests(_ raw: Any?) -> [OpenCodexHubRequestResult] {
        guard let rows = raw as? [Any] else { return [] }
        return rows.compactMap { rawRow in
            guard let row = rawRow as? [String: Any],
                  let requestID = self.trimmed(row["requestId"]),
                  OpenCodexHubSwitchRequest.isValidRequestID(requestID),
                  let outcome = self.trimmed(row["result"]).flatMap(OpenCodexHubRequestResult.Outcome.init(rawValue:))
            else { return nil }
            return OpenCodexHubRequestResult(
                requestID: requestID,
                provider: self.trimmed(row["provider"]).flatMap(OpenCodexHubProvider.init(rawValue:)),
                outcome: outcome,
                code: self.trimmed(row["code"]),
                reason: self.trimmed(row["reason"]).map { String($0.prefix(300)) },
                at: self.date(row["at"]))
        }
    }

    /// Whether an opencodex account id may be passed to `ocx account use` as one argument.
    ///
    /// opencodex ids come in several forms: 32 hex digits, `chatgpt-<epoch ms>`, a caller-chosen id, and
    /// `__main__` for the Codex App's own login. Any printable ASCII id is accepted, bounded in length; an
    /// id that starts with `-` would read as an option.
    static func isValidAccountID(_ id: String) -> Bool {
        guard self.isPrintableToken(id, maxLength: self.maxAccountIDLength) else { return false }
        return !id.hasPrefix("-")
    }

    /// The hub names a target by the last characters of its id, which may start with any id character.
    static func isValidIDSuffix(_ suffix: String) -> Bool {
        self.isPrintableToken(suffix, maxLength: 16)
    }

    /// Non-empty, at most `maxLength` characters, printable ASCII only: no whitespace or control characters.
    private static func isPrintableToken(_ text: String, maxLength: Int) -> Bool {
        let scalars = text.unicodeScalars
        guard !scalars.isEmpty, scalars.count <= maxLength else { return false }
        return scalars.allSatisfy { (0x21...0x7E).contains($0.value) }
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let raw = try? JSONSerialization.jsonObject(with: data),
              let object = raw as? [String: Any]
        else {
            throw OpenCodexHubPoolError.notJSONObject
        }
        return object
    }

    /// opencodex reports epoch milliseconds (some OpenAI fields epoch seconds); snapshots also carry ISO 8601.
    static func date(_ raw: Any?) -> Date? {
        if let text = raw as? String {
            return ISO8601DateParser.parse(text)
        }
        guard let value = self.finiteDouble(raw), value > 0 else { return nil }
        // Values below 1e11 cannot be milliseconds after 1973; read them as seconds.
        return Date(timeIntervalSince1970: value >= 100_000_000_000 ? value / 1000 : value)
    }

    static func trimmed(_ raw: Any?) -> String? {
        guard let text = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }

    private static func finiteDouble(_ raw: Any?) -> Double? {
        guard let number = raw as? NSNumber else { return nil }
        // JSON booleans bridge to NSNumber too; only accept genuine numbers.
        guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        return value.isFinite ? value : nil
    }
}
