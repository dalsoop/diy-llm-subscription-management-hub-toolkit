import CodexBarCore
import Foundation

/// Display-only quota identity. Inventory order matches the account cards; no credentials or labels are copied.
struct ProviderSwitcherAccountQuota: Equatable {
    let id: String
    let percent: Double?
    let isActive: Bool
}

extension StatusItemController {
    func switcherAccountQuotas(for instanceID: ProviderInstanceID) -> [ProviderSwitcherAccountQuota] {
        guard let provider = instanceID.firstPartyProvider else { return [] }
        if self.store.menuBarSnapshot(for: instanceID) == nil,
           self.fleetAccountProjection(for: provider).fallback != nil
        {
            return []
        }
        func quota(id: String, snapshot: UsageSnapshot?, active: Bool) -> ProviderSwitcherAccountQuota {
            let percent = Self.switcherWeeklyMetricPercent(
                for: provider,
                snapshot: snapshot,
                showUsed: self.settings.usageBarsShowUsed,
                preference: self.settings.menuBarMetricPreference(for: provider, snapshot: snapshot))
            return ProviderSwitcherAccountQuota(id: id, percent: percent, isActive: active)
        }
        if self.store.usesOpenCodexHub(for: provider) {
            guard let pool = self.store.openCodexHubCardState(for: provider)?.pool else { return [] }
            return OpenCodexHubAccountProjection.accounts(for: pool, allowsSwitching: false).map { account in
                quota(
                    id: account.id.source + ":" + account.id.opaqueID,
                    snapshot: pool.isStale() ? nil : account.snapshot,
                    active: account.isActive)
            }
        }
        if ClaudeSwapMenuPrecedence.prefersClaudeSwap(
            provider: provider,
            accountCount: self.store.claudeSwapAccountSnapshots.count,
            showSingleAccount: self.settings.claudeSwapShowSingleAccount)
        {
            return self.store.claudeSwapAccountSnapshots.map { account in
                quota(
                    id: account.id.source + ":" + account.id.opaqueID,
                    snapshot: account.usesLastKnownUsage ? nil : account.snapshot,
                    active: account.isActive)
            }
        }
        if provider == .codex,
           let projection = self.settings.codexVisibleAccountProjectionForMenuDisplay,
           projection.visibleAccounts.count > 1
        {
            return projection.visibleAccounts.map { account in
                let record = self.store.codexAccountSnapshots.first {
                    $0.id == account.id && UsageStore.codexPriorSnapshotAccountMatches($0.account, account: account)
                }
                return quota(
                    id: account.id,
                    snapshot: record?.snapshot,
                    active: account.id == projection.activeVisibleAccountID)
            }
        }
        let accounts = self.settings.tokenAccounts(for: provider)
        guard accounts.count > 1, let active = self.settings.effectiveSelectedTokenAccount(for: provider) else {
            return []
        }
        let snapshots = self.store.validTokenAccountSnapshots(provider: provider, accounts: accounts)
        return accounts.map { account in
            quota(
                id: account.id.uuidString,
                snapshot: snapshots.first { $0.id == account.id }?.snapshot,
                active: account.id == active.id)
        }
    }
}
