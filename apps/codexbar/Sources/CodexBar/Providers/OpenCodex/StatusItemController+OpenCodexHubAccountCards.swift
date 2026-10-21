import AppKit
import CodexBarCore

/// Projects an opencodex hub pool onto the provider-neutral account rows the multi-account menu layouts
/// draw. The rows hold only what the pool holds: masked emails, labels, state flags and quota windows.
enum OpenCodexHubAccountProjection {
    static let identitySource = "opencodex-hub"

    /// One row per hub account, in the hub's order; the 1-based position is the row's opaque id.
    /// `canActivate` is true only for accounts this Mac may switch the hub to right now.
    static func accounts(
        for pool: OpenCodexHubPool,
        allowsSwitching: Bool,
        now: Date = Date()) -> [ProviderAccountUsageSnapshot]
    {
        let provider = pool.provider.usageProvider
        return pool.accounts.enumerated().map { index, account in
            ProviderAccountUsageSnapshot(
                id: ProviderAccountIdentity(source: self.identitySource, opaqueID: String(index + 1)),
                provider: provider,
                displayLabel: account.displayAlias.map { "\(account.email) (\($0))" } ?? account.email,
                accountEmail: account.email.isEmpty ? nil : account.email,
                isActive: account.isActive,
                canActivate: allowsSwitching && pool.canSwitch(to: account),
                snapshot: OpenCodexHubUsageProjection.snapshot(
                    for: account,
                    provider: pool.provider,
                    fallbackUpdatedAt: pool.snapshotUpdatedAt ?? now),
                error: self.stateText(for: account),
                sourceLabel: OpenCodexHubUsageProjection.sourceLabel)
        }
    }

    /// The hub account behind a projected row.
    static func hubAccount(for row: ProviderAccountUsageSnapshot, in pool: OpenCodexHubPool) -> OpenCodexHubAccount? {
        guard row.id.source == self.identitySource, let ordinal = Int(row.id.opaqueID),
              pool.accounts.indices.contains(ordinal - 1)
        else { return nil }
        return pool.accounts[ordinal - 1]
    }

    static func privacyOrdinal(for row: ProviderAccountUsageSnapshot) -> PersonalInfoRedactor.AccountOrdinal? {
        guard row.id.source == self.identitySource, let ordinal = Int(row.id.opaqueID) else { return nil }
        return PersonalInfoRedactor.AccountOrdinal(ordinal)
    }

    private static func stateText(for account: OpenCodexHubAccount) -> String? {
        if account.isPaused { return L("Disabled") }
        if account.requiresReauthentication { return L("Re-authenticate") }
        if account.quotaUnavailable || account.quota.isEmpty { return L("Limits not available") }
        return nil
    }
}

extension StatusItemController {
    /// Draws a Codex or Grok card's hub accounts with the multi-account menu layout. Stacked shows every
    /// account's usage card at once (compact rows for long lists); segmented shows account tabs above the
    /// selected account's card. Returns true when the hub accounts replaced the provider's own card.
    func addOpenCodexHubAccountCards(
        provider: UsageProvider,
        to menu: NSMenu,
        captureMenu: NSMenu,
        context: MenuCardContext) -> Bool
    {
        guard self.store.usesOpenCodexHub(for: provider),
              let state = self.store.openCodexHubCardState(for: provider),
              let pool = state.pool,
              pool.accounts.count > 1
        else { return false }
        let allowsSwitching = !state.isSwitching && !state.switchStatus.isPending
        let accounts = OpenCodexHubAccountProjection.accounts(for: pool, allowsSwitching: allowsSwitching)
        switch self.settings.multiAccountMenuLayout {
        case .stacked:
            self.addStackedOpenCodexHubCards(accounts, pool: pool, to: menu, captureMenu: captureMenu, context: context)
            return true
        case .segmented:
            return self.addSegmentedOpenCodexHubCards(
                accounts,
                pool: pool,
                to: menu,
                captureMenu: captureMenu,
                context: context)
        }
    }

    /// Shows another hub account's card in the segmented layout; the active account clears the selection.
    func inspectOpenCodexHubAccount(_ id: ProviderAccountIdentity, provider: UsageProvider, menu: NSMenu?) {
        guard var state = self.store.openCodexHubCardStates[provider], let pool = state.pool else { return }
        self.advanceMenuInteraction(for: menu)
        let isActive = OpenCodexHubAccountProjection.accounts(for: pool, allowsSwitching: false)
            .first { $0.id == id }?.isActive == true
        state.inspectedAccountID = isActive ? nil : id
        self.store.openCodexHubCardStates[provider] = state
        self.invalidateMenus(refreshOpenMenus: true)
    }

    /// The inspected tab lasts one menu session, like the Claude account tabs.
    func resetOpenCodexHubAccountInspection() {
        for (provider, state) in self.store.openCodexHubCardStates where state.inspectedAccountID != nil {
            var cleared = state
            cleared.inspectedAccountID = nil
            self.store.openCodexHubCardStates[provider] = cleared
        }
    }

    private func addStackedOpenCodexHubCards(
        _ accounts: [ProviderAccountUsageSnapshot],
        pool: OpenCodexHubPool,
        to menu: NSMenu,
        captureMenu: NSMenu,
        context: MenuCardContext)
    {
        let provider = context.currentProvider
        let plan = self.compactAccountPlan(for: provider, accounts: accounts)
        if plan.usesCompactLayout {
            self.addCompactAccountMenuRows(
                CompactAccountMenuRendering(
                    plan: plan,
                    accounts: accounts,
                    idPrefix: "openCodexHub",
                    cardModel: { [weak self] account in
                        self?.openCodexHubCardModel(for: account, provider: provider)
                    },
                    planAction: { [weak self] account in
                        self?.openCodexHubSwitchAction(account, pool: pool, provider: provider, menu: captureMenu)
                    },
                    privacyOrdinal: OpenCodexHubAccountProjection.privacyOrdinal),
                to: menu,
                captureMenu: captureMenu,
                context: context)
            return
        }
        let cardRows = accounts.compactMap { account ->
            (account: ProviderAccountUsageSnapshot, model: UsageMenuCardView.Model)? in
            guard let model = self.openCodexHubCardModel(for: account, provider: provider) else { return nil }
            return (account, model)
        }
        self.addStackedMenuCards(
            cardRows.map(\.model),
            to: menu,
            context: context,
            planAction: { [weak self] index in
                guard cardRows.indices.contains(index) else { return nil }
                return self?.openCodexHubSwitchAction(
                    cardRows[index].account,
                    pool: pool,
                    provider: provider,
                    menu: captureMenu)
            })
    }

    /// Tabs for every hub account; the active account keeps the provider's own card below, another tab
    /// shows that account's card with its switch action. Returns true when it drew that card.
    private func addSegmentedOpenCodexHubCards(
        _ accounts: [ProviderAccountUsageSnapshot],
        pool: OpenCodexHubPool,
        to menu: NSMenu,
        captureMenu: NSMenu,
        context: MenuCardContext) -> Bool
    {
        let provider = context.currentProvider
        // Tabs only select which card shows; switching stays on the card's action and its confirmation.
        let tabs = OpenCodexHubAccountProjection.accounts(for: pool, allowsSwitching: false)
        let inspectedID = self.store.openCodexHubCardState(for: provider)?.inspectedAccountID
        let display = ClaudeSwapAccountMenuDisplay(
            accounts: tabs,
            layout: .segmented,
            switchingAccountID: nil,
            errorAccountID: nil,
            inspectedAccountID: inspectedID)
        let item = NSMenuItem()
        item.view = ClaudeSwapAccountSwitcherView(
            display: display,
            hidePersonalInfo: self.settings.hidePersonalInfo,
            width: context.menuWidth,
            onSelect: { [weak self, weak captureMenu] id in
                self?.inspectOpenCodexHubAccount(id, provider: provider, menu: captureMenu)
            })
        item.isEnabled = false
        item.representedObject = "openCodexHubSwitcher"
        menu.addItem(item)
        menu.addItem(.separator())
        guard let inspectedID, let account = accounts.first(where: { $0.id == inspectedID }), !account.isActive
        else { return false }
        let label = ClaudeSwapAccountMenuDisplay.label(for: account, hidePersonalInfo: self.settings.hidePersonalInfo)
        let heading = NSMenuItem(title: String(format: L("Details for %@"), label), action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        self.addStackedOpenCodexHubCards([account], pool: pool, to: menu, captureMenu: captureMenu, context: context)
        return true
    }

    private func openCodexHubCardModel(
        for account: ProviderAccountUsageSnapshot,
        provider: UsageProvider) -> UsageMenuCardView.Model?
    {
        let actionLabel: String? = if account.isActive {
            L("Active")
        } else if account.canActivate {
            L("Switch Account...")
        } else {
            nil
        }
        return self.menuCardModel(
            for: provider,
            context: .account(.init(
                snapshot: account.snapshot,
                error: account.error,
                info: AccountInfo(email: account.displayLabel, plan: nil),
                privacyOrdinal: OpenCodexHubAccountProjection.privacyOrdinal(for: account),
                plan: .label(actionLabel),
                planEmphasis: account.isActive ? .active : .none,
                sourceLabel: account.sourceLabel)))
    }

    private func openCodexHubSwitchAction(
        _ account: ProviderAccountUsageSnapshot,
        pool: OpenCodexHubPool,
        provider: UsageProvider,
        menu: NSMenu) -> (() -> Void)?
    {
        guard account.canActivate, let hubAccount = OpenCodexHubAccountProjection.hubAccount(for: account, in: pool)
        else { return nil }
        let label = ClaudeSwapAccountMenuDisplay.label(for: account, hidePersonalInfo: self.settings.hidePersonalInfo)
        let selection = OpenCodexHubMenuSelection(provider: provider, account: hubAccount, label: label)
        return { [weak self, weak menu] in
            self?.confirmOpenCodexHubSwitch(selection, menu: menu)
        }
    }
}
