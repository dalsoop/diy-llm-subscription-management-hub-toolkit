import AppKit
import CodexBarCore

extension StatusItemController {
    func addClaudeSwapMenuCards(
        to menu: NSMenu,
        captureMenu: NSMenu,
        context: MenuCardContext)
    {
        let accounts = self.store.claudeSwapAccountSnapshots
        let display = ClaudeSwapAccountMenuDisplay(
            accounts: accounts,
            layout: self.settings.multiAccountMenuLayout,
            switchingAccountID: self.store.claudeSwapTransientState.switchingAccountID,
            errorAccountID: self.store.claudeSwapTransientState.lastErrorAccountID,
            inspectedAccountID: self.claudeSwapInspectedAccountID)
        // tcr picks the account for each request, so it never switches and never reports an active account.
        // Keyed on the rows being drawn, not the setting, so a list read before a source change keeps its wording.
        let readsFromTcr = accounts.contains { ClaudeSwapAccountSource(identitySource: $0.id.source) == .tcr }
        // opencodex switches the hub's pool, so the wording names the hub; a read-only hub snapshot says
        // where the accounts are managed instead of offering a switch.
        let readsFromOpenCodex = accounts.contains {
            ClaudeSwapAccountSource(identitySource: $0.id.source) == .openCodex
        }
        let remoteCopy = readsFromOpenCodex ? self.store.claudeSwapRemoteCopy : nil
        if let remoteCopy {
            let lines = if let pool = remoteCopy.pool {
                OpenCodexHubPresentation.poolNotices(pool)
            } else {
                [remoteCopy.managerName.map { L("Accounts are managed on the hub %@.", $0) }
                    ?? L("Accounts are managed on the opencodex hub.")]
            }
            for line in lines {
                self.addOpenCodexHubNotice(line, to: menu, width: context.menuWidth)
            }
        }
        if readsFromOpenCodex {
            let hidePersonalInfo = self.settings.hidePersonalInfo
            for line in self.store.claudeSwapHubSwitchStatus.menuLines(hidePersonalInfo: hidePersonalInfo) {
                self.addOpenCodexHubNotice(line, to: menu, width: context.menuWidth)
            }
        }
        if display.showsSwitcher {
            let headingTitle = if readsFromTcr {
                L("Claude accounts in tcr")
            } else if readsFromOpenCodex, let remoteCopy, !remoteCopy.isSwitchable {
                L("Claude accounts on the opencodex hub")
            } else if readsFromOpenCodex {
                L("Switch opencodex hub account")
            } else {
                L("Switch Claude Code account")
            }
            let switcherHeading = NSMenuItem(title: headingTitle, action: nil, keyEquivalent: "")
            switcherHeading.isEnabled = false
            menu.addItem(switcherHeading)
            let item = NSMenuItem()
            item.view = ClaudeSwapAccountSwitcherView(
                display: display,
                hidePersonalInfo: self.settings.hidePersonalInfo,
                width: context.menuWidth,
                onSelect: { [weak self, weak captureMenu] id in
                    self?.handleClaudeSwapAccountSelection(id, menu: captureMenu)
                })
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
            if !readsFromTcr, !accounts.contains(where: \.isActive) {
                let notice = NSMenuItem(title: L("No active account"), action: nil, keyEquivalent: "")
                notice.isEnabled = false
                menu.addItem(notice)
            }
            if let account = display.displayedAccount, !account.isActive {
                let label = ClaudeSwapAccountMenuDisplay.label(
                    for: account, hidePersonalInfo: self.settings.hidePersonalInfo)
                let heading = NSMenuItem(
                    title: String(format: L("Details for %@"), label),
                    action: nil,
                    keyEquivalent: "")
                heading.isEnabled = false
                menu.addItem(heading)
            }
            if let account = display.displayedAccount {
                self.addStackedClaudeSwapMenuCards(
                    accounts: [account],
                    to: menu,
                    captureMenu: captureMenu,
                    context: context)
            } else if self.addStorageMenuCardSection(to: menu, provider: .claude, width: context.menuWidth) {
                menu.addItem(.separator())
            }
            return
        }
        let plan = self.compactAccountPlan(for: .claude, accounts: accounts)
        guard plan.usesCompactLayout else {
            self.addStackedClaudeSwapMenuCards(accounts: accounts, to: menu, captureMenu: captureMenu, context: context)
            return
        }
        self.addCompactAccountMenuRows(
            CompactAccountMenuRendering(
                plan: plan,
                accounts: accounts,
                idPrefix: "claudeSwap",
                cardModel: { [weak self] account in
                    self?.claudeSwapCardModel(for: account)
                },
                planAction: { [weak self] account in
                    self?.claudeSwapAccountSwitchAction(account, menu: captureMenu)
                },
                privacyOrdinal: ClaudeSwapAccountMenuDisplay.privacyOrdinal),
            to: menu,
            captureMenu: captureMenu,
            context: context)
    }

    func resetClaudeSwapAccountInspection() {
        guard self.claudeSwapInspectedAccountID != nil else { return }
        self.claudeSwapInspectedAccountID = nil
        self.invalidateMenus()
    }

    func handleClaudeSwapAccountSelection(_ id: ProviderAccountIdentity, menu: NSMenu?) {
        guard self.store.claudeSwapTransientState.task == nil,
              let account = self.store.claudeSwapAccountSnapshots.first(where: { $0.id == id })
        else { return }
        if !ClaudeSwapAccountMenuDisplay.activatesAccount(account) {
            // Inspect sentinel diagnostics without asking the adapter to activate that slot.
            self.advanceMenuInteraction(for: menu)
            self.claudeSwapInspectedAccountID = id
            self.invalidateMenus()
        } else {
            self.startClaudeSwapAccountSwitch(id, menu: menu)
        }
        if let menu {
            self.deferSwitcherMenuRebuildIfStillVisible(menu, provider: .claude)
        }
    }

    private func startClaudeSwapAccountSwitch(_ accountID: ProviderAccountIdentity, menu: NSMenu?) {
        guard self.store.claudeSwapTransientState.task == nil,
              self.store.shouldFetchClaudeSwapAccounts(),
              let account = self.store.claudeSwapAccountSnapshots.first(where: { $0.id == accountID && $0.canActivate })
        else { return }
        guard self.settings.claudeSwapSource == .openCodex else {
            self.beginClaudeSwapAccountSwitch(accountID, menu: menu)
            return
        }
        guard !self.store.claudeSwapHubSwitchStatus.isPending else { return }
        // A hub switch moves every Mac that uses the hub, so it is confirmed outside the open menu first.
        let label = ClaudeSwapAccountMenuDisplay.label(for: account, hidePersonalInfo: self.settings.hidePersonalInfo)
        let details = Self.openCodexHubSwitchDetails(for: account, remoteCopy: self.store.claudeSwapRemoteCopy)
        menu?.cancelTracking()
        Task { @MainActor [weak self] in
            guard let self, OpenCodexHubSwitchConfirmation.confirm(accountLabel: label, details: details) else {
                return
            }
            self.beginClaudeSwapAccountSwitch(accountID, menu: nil)
        }
    }

    /// The target's quota and the near-limit warning, from the hub account behind the card.
    private static func openCodexHubSwitchDetails(
        for account: ProviderAccountUsageSnapshot,
        remoteCopy: ClaudeSwapRemoteCopy?) -> String
    {
        let everyMacMoves = L("Every Mac that uses this hub moves to this Claude account on its next request.")
        // On the hub the card's windows are the live list's: 5-hour, weekly and model-scoped.
        let snapshot = account.snapshot
        let window = { (rate: RateWindow?) in
            rate.map { OpenCodexHubQuotaWindow(usedPercent: $0.usedPercent, resetsAt: $0.resetsAt) }
        }
        let hubAccount = remoteCopy?.pool?.accounts.first { $0.email == account.accountEmail }
            ?? OpenCodexHubAccount(
                idSuffix: nil,
                label: nil,
                email: account.accountEmail ?? "",
                isActive: false,
                quota: OpenCodexHubQuota(
                    fiveHour: window(snapshot?.primary),
                    weekly: window(snapshot?.secondary),
                    custom: (snapshot?.extraRateWindows ?? []).map {
                        OpenCodexHubCustomWindow(
                            label: $0.title,
                            usedPercent: $0.window.usedPercent,
                            resetsAt: $0.window.resetsAt)
                    }))
        return OpenCodexHubPresentation.confirmationDetails(
            account: hubAccount,
            isHubLocal: remoteCopy == nil,
            everyMacMoves: everyMacMoves)
    }

    private func beginClaudeSwapAccountSwitch(_ accountID: ProviderAccountIdentity, menu: NSMenu?) {
        guard self.store.claudeSwapTransientState.task == nil,
              self.store.shouldFetchClaudeSwapAccounts(),
              self.store.claudeSwapAccountSnapshots.contains(where: { $0.id == accountID && $0.canActivate })
        else { return }
        self.advanceMenuInteraction(for: menu)
        self.claudeSwapInspectedAccountID = nil
        let executablePath = self.settings.claudeSwapExecutablePath
        let source = self.settings.claudeSwapSource
        let configurationGeneration = self.store.claudeSwapTransientState.configurationGeneration
        let interactionGeneration = menu.flatMap {
            self.menuSession.menuInteractionGeneration(for: ObjectIdentifier($0))
        }
        self.store.switchClaudeSwapAccount(accountID, progressDidChange: { [weak self, weak menu] in
            guard let self, let menu, let interactionGeneration else { return }
            self.scheduleOpenRootMenuDataRebuildIfStillVisible(menu, provider: .claude) { [weak self, weak menu] in
                guard let self, let menu else { return false }
                return self.store.isCurrentClaudeSwapConfiguration(
                    executablePath: executablePath,
                    source: source,
                    configurationGeneration: configurationGeneration) &&
                    self.menuSession.isCurrentMenuInteraction(interactionGeneration, for: ObjectIdentifier(menu)) &&
                    self.claudeSwapInspectedAccountID == nil &&
                    (self.store.claudeSwapTransientState.switchingAccountID == accountID ||
                        self.store.claudeSwapTransientState.task == nil)
            }
        })
    }

    private func addStackedClaudeSwapMenuCards(
        accounts: [ProviderAccountUsageSnapshot],
        to menu: NSMenu,
        captureMenu: NSMenu,
        context: MenuCardContext)
    {
        let cardRows = accounts.compactMap { account ->
            (account: ProviderAccountUsageSnapshot, model: UsageMenuCardView.Model)? in
            guard let model = self.claudeSwapCardModel(for: account) else { return nil }
            return (account, model)
        }
        self.addStackedMenuCards(
            cardRows.map(\.model),
            to: menu,
            context: context,
            planAction: { [weak self] index in
                guard cardRows.indices.contains(index) else { return nil }
                return self?.claudeSwapAccountSwitchAction(cardRows[index].account, menu: captureMenu)
            })
    }

    private func claudeSwapCardModel(for account: ProviderAccountUsageSnapshot) -> UsageMenuCardView.Model? {
        self.menuCardModel(
            for: .claude,
            context: ClaudeSwapAccountMenuDisplay.cardContext(
                for: account,
                planLabel: self.claudeSwapAccountActionLabel(account),
                adapterError: self.store.claudeSwapLastError,
                switchError: self.store.claudeSwapTransientState.lastErrorAccountID == account.id
                    ? self.store.claudeSwapTransientState.lastError
                    : nil,
                historySelection: self.store.claudeSwapPlanUtilizationHistorySelection(for: account)))
    }

    private func claudeSwapAccountActionLabel(_ account: ProviderAccountUsageSnapshot) -> String? {
        ClaudeSwapAccountMenuDisplay.actionLabel(
            for: account,
            switchingAccountID: self.store.claudeSwapTransientState.switchingAccountID,
            switchInFlight: self.store.claudeSwapTransientState.task != nil,
            switchPhase: self.store.claudeSwapTransientState.switchPhase)
    }

    func claudeSwapAccountSwitchAction(
        _ account: ProviderAccountUsageSnapshot,
        menu: NSMenu)
        -> (() -> Void)?
    {
        guard self.store.claudeSwapTransientState.task == nil, account.canActivate else { return nil }
        let accountID = account.id
        return { [weak self, weak menu] in
            guard let self else { return }
            self.startClaudeSwapAccountSwitch(accountID, menu: menu)
        }
    }
}
