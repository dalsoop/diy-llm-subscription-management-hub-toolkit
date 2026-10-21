import CodexBarCore
import Foundation

/// The switch a card asked the opencodex hub for, and what the hub answered.
///
/// A Mac that is not the hub writes a request file and shows "the hub is switching" until a newer hub
/// snapshot reports the request (`lastRequests`) or shows the target as active. The answer is shown only
/// while the hub's active account is still the one it was about; once the hub moves on by itself, the
/// menu says where the hub is now instead.
struct OpenCodexHubSwitchStatus: Equatable {
    enum Notice: Equatable {
        case switched(String)
        case refused(String)
        case failed(String)
        case expired
    }

    /// Names a hub account the way a switch request does: id suffix and masked email.
    struct AccountKey: Equatable {
        let idSuffix: String?
        let email: String

        init(idSuffix: String?, email: String) {
            self.idSuffix = idSuffix
            self.email = email
        }

        init(_ account: OpenCodexHubAccount) {
            self.init(idSuffix: account.idSuffix, email: account.email)
        }
    }

    /// The hub's active account when a later pool no longer matches the notice, with its 1-based position.
    struct MovedOn: Equatable {
        let account: OpenCodexHubAccount
        let ordinal: Int
    }

    private(set) var pending: OpenCodexHubPendingSwitch?
    private(set) var pendingLabel: String?
    private(set) var notice: Notice?
    /// The active account the notice describes: the target of a switch, otherwise the account that stayed.
    private(set) var noticeAccount: AccountKey?
    private(set) var movedOn: MovedOn?

    var isPending: Bool {
        self.pending != nil
    }

    mutating func begin(_ request: OpenCodexHubSwitchRequest, label: String) {
        self.pending = OpenCodexHubPendingSwitch(request: request)
        self.pendingLabel = label
        self.notice = nil
        self.noticeAccount = nil
        self.movedOn = nil
    }

    /// Ends the pending request with `notice`; `activeAccount` is the hub's active account it describes.
    mutating func finish(_ notice: Notice?, activeAccount: AccountKey? = nil) {
        self.pending = nil
        self.pendingLabel = nil
        self.notice = notice
        self.noticeAccount = notice == nil ? nil : activeAccount
        self.movedOn = nil
    }

    /// Resolves a pending request against a newly read pool, or checks the last answer still describes the
    /// hub's active account. Returns true when the status changed.
    @discardableResult
    mutating func reconcile(with pool: OpenCodexHubPool, now: Date = Date()) -> Bool {
        guard let pending = self.pending else {
            return self.recordMovedOn(in: pool)
        }
        guard pending.request.provider == pool.provider else { return false }
        let label = self.pendingLabel ?? pending.request.targetEmail
        let active = pool.activeAccount.map(AccountKey.init)
        switch pending.resolution(in: pool, now: now) {
        case .pending:
            return false
        case .done:
            let target = AccountKey(idSuffix: pending.request.targetIDSuffix, email: pending.request.targetEmail)
            self.finish(.switched(label), activeAccount: target)
            self.recordMovedOn(in: pool)
        case let .refused(code, reason):
            self.finish(.refused(Self.reasonText(code: code, reason: reason)), activeAccount: active)
        case let .failed(code, reason):
            self.finish(.failed(Self.reasonText(code: code, reason: reason)), activeAccount: active)
        case .expired:
            self.finish(.expired, activeAccount: active)
        }
        return true
    }

    /// Lines for the menu: the pending request, the last answer while it still holds, or where the hub
    /// moved since.
    func menuLines(hidePersonalInfo: Bool) -> [String] {
        if self.pending != nil {
            return [L("The hub is switching accounts…")]
        }
        if let movedOn {
            let label = OpenCodexHubPresentation.label(
                for: movedOn.account,
                hidePersonalInfo: hidePersonalInfo,
                ordinal: movedOn.ordinal)
            return [L("The hub has since switched to %@.", label)]
        }
        switch self.notice {
        case let .switched(label): return [L("The hub switched to %@.", label)]
        case let .refused(reason): return [L("The hub refused the switch: %@", reason)]
        case let .failed(reason): return [L("The hub could not switch: %@", reason)]
        case .expired: return [L("The hub did not pick up the switch request in time.")]
        case nil: return []
        }
    }

    @discardableResult
    private mutating func recordMovedOn(in pool: OpenCodexHubPool) -> Bool {
        guard self.notice != nil, let noticeAccount else { return false }
        var movedOn: MovedOn?
        if let index = pool.accounts.firstIndex(where: \.isActive),
           AccountKey(pool.accounts[index]) != noticeAccount
        {
            movedOn = MovedOn(account: pool.accounts[index], ordinal: index + 1)
        }
        guard movedOn != self.movedOn else { return false }
        self.movedOn = movedOn
        return true
    }

    private static func reasonText(code: String?, reason: String?) -> String {
        reason ?? code ?? L("No reason given")
    }
}

/// Menu-facing presentation shared by the hub cards.
enum OpenCodexHubPresentation {
    static func label(for account: OpenCodexHubAccount, hidePersonalInfo: Bool, ordinal: Int) -> String {
        if hidePersonalInfo { return L("Account %@", String(ordinal)) }
        if let alias = account.displayAlias { return "\(account.email) (\(alias))" }
        return account.email.isEmpty ? L("Account %@", String(ordinal)) : account.email
    }

    /// "Weekly 51% · Monthly 0%"; nil without windows.
    static func quotaSummary(_ quota: OpenCodexHubQuota) -> String? {
        let parts = OpenCodexHubUsageProjection.summary(quota).map { part in
            let name = switch part.label {
            case "5h": L("5h")
            case "Weekly": L("Weekly")
            case "Monthly": L("Monthly")
            default: part.label
            }
            return "\(name) \(Int(part.percent.rounded()))%"
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func menuTitle(for account: OpenCodexHubAccount, label: String) -> String {
        var title = label
        if account.isPaused {
            title = L("%@ (paused)", title)
        } else if account.requiresReauthentication {
            title = L("%@ (sign-in needed)", title)
        }
        if let summary = self.quotaSummary(account.quota) {
            title += " — \(summary)"
        }
        return title
    }

    /// Where the accounts live, staleness and why switching is off. Empty for a live list on the hub.
    static func poolNotices(_ pool: OpenCodexHubPool, now: Date = Date()) -> [String] {
        var lines: [String] = []
        if !pool.isHubLocal {
            let hubName = pool.hubName ?? OpenCodexHubDefaults.hubName
            lines.append(hubName.map { L("Accounts are managed on the hub %@.", $0) }
                ?? L("Accounts are managed on the opencodex hub."))
            if pool.isStale(now: now) {
                if let updatedAt = pool.snapshotUpdatedAt {
                    lines.append(L("The hub list is out of date (last updated %@).", updatedAt.relativeDescription()))
                } else {
                    lines.append(L("The hub list is out of date."))
                }
            }
        }
        if pool.isLinkedCopy {
            // This Mac's own read-only copy: switching goes through the hub's snapshot, which is not current.
            lines.append(L("Switching is off until the hub writes a current snapshot to this Mac."))
        } else if !pool.switchable {
            lines.append(pool.switchReason ?? self.defaultSwitchReason(hubName: pool.hubName))
        }
        return lines
    }

    static func defaultSwitchReason(hubName: String?) -> String {
        if let hubName = hubName ?? OpenCodexHubDefaults.hubName {
            return L("Accounts in this pool are switched only on %@.", hubName)
        }
        return L("Accounts in this pool are switched only on the hub.")
    }

    /// The confirmation text: who moves, the target's quota and, near a limit, what can happen next.
    static func confirmationDetails(
        account: OpenCodexHubAccount,
        isHubLocal: Bool,
        everyMacMoves: String) -> String
    {
        var paragraphs = [everyMacMoves]
        if let summary = self.quotaSummary(account.quota) {
            paragraphs.append(L("Quota: %@", summary))
        }
        if account.isNearLimit {
            paragraphs.append(L(
                "This account has used %@ or more of a limit. The hub may switch away again soon, " +
                    "or requests may stop until the limit resets.",
                "\(Int(OpenCodexHubPool.nearLimitPercent))%"))
        }
        if !isHubLocal {
            paragraphs.append(L("This Mac asks the hub to switch; the result shows after the hub's next update."))
        }
        return paragraphs.joined(separator: "\n\n")
    }
}
