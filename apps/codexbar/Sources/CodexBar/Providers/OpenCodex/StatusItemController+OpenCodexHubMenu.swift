import AppKit
import CodexBarCore

/// Identifies one hub account a menu row switches to. Holds only the masked email and id suffix.
final class OpenCodexHubMenuSelection: NSObject {
    let provider: UsageProvider
    let account: OpenCodexHubAccount
    let label: String

    init(provider: UsageProvider, account: OpenCodexHubAccount, label: String) {
        self.provider = provider
        self.account = account
        self.label = label
    }
}

extension StatusItemController {
    /// Adds the hub rows when the card reads an opencodex hub pool.
    func addOpenCodexHubMenuItemsIfNeeded(provider: UsageProvider, to menu: NSMenu) {
        guard self.store.usesOpenCodexHub(for: provider) else { return }
        self.addOpenCodexHubMenuItems(provider: provider, to: menu)
    }

    /// Notices and the account switcher of a Codex or Grok card that reads an opencodex hub pool. The
    /// active account's quota renders as the provider card below these rows.
    func addOpenCodexHubMenuItems(provider: UsageProvider, to menu: NSMenu) {
        guard let state = self.store.openCodexHubCardState(for: provider) else {
            self.addOpenCodexHubNotice(L("Reading the opencodex hub…"), to: menu)
            return
        }
        guard let pool = state.pool else {
            if let error = state.lastError {
                self.addOpenCodexHubNotice(error, to: menu)
            }
            return
        }
        for line in OpenCodexHubPresentation.poolNotices(pool) {
            self.addOpenCodexHubNotice(line, to: menu)
        }
        if let error = state.lastError {
            self.addOpenCodexHubNotice(error, to: menu)
        }
        for line in state.switchStatus.menuLines(hidePersonalInfo: self.settings.hidePersonalInfo) {
            self.addOpenCodexHubNotice(line, to: menu)
        }
        // Several accounts render as account cards or tabs (`addOpenCodexHubAccountCards`), which carry the
        // switch action; the submenu remains for a single-account pool.
        guard pool.accounts.count == 1 else { return }

        let canSwitchNow = pool.switchable && !state.isSwitching && !state.switchStatus.isPending
        let switcher = NSMenuItem(
            title: pool.switchable ? L("Switch opencodex hub account") : L("opencodex hub accounts"),
            action: nil,
            keyEquivalent: "")
        let submenu = NSMenu()
        let hidePersonalInfo = self.settings.hidePersonalInfo
        for (index, account) in pool.accounts.enumerated() {
            let label = OpenCodexHubPresentation.label(
                for: account,
                hidePersonalInfo: hidePersonalInfo,
                ordinal: index + 1)
            let item = NSMenuItem(
                title: OpenCodexHubPresentation.menuTitle(for: account, label: label),
                action: #selector(self.selectOpenCodexHubAccount(_:)),
                keyEquivalent: "")
            item.target = self
            item.state = account.isActive ? .on : .off
            item.representedObject = OpenCodexHubMenuSelection(provider: provider, account: account, label: label)
            item.isEnabled = canSwitchNow && pool.canSwitch(to: account)
            submenu.addItem(item)
        }
        if !pool.switchable {
            submenu.addItem(.separator())
            self.addOpenCodexHubNotice(
                pool.switchReason ?? OpenCodexHubPresentation.defaultSwitchReason(hubName: pool.hubName),
                to: submenu)
        }
        submenu.autoenablesItems = false
        switcher.submenu = submenu
        menu.addItem(switcher)
        menu.addItem(.separator())
    }

    @objc func selectOpenCodexHubAccount(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? OpenCodexHubMenuSelection else { return }
        sender.menu?.supermenu?.cancelTracking()
        self.confirmOpenCodexHubSwitch(selection, menu: sender.menu)
    }

    /// Confirms and starts a hub switch picked from the account submenu or an account card.
    func confirmOpenCodexHubSwitch(_ selection: OpenCodexHubMenuSelection, menu: NSMenu?) {
        guard let state = self.store.openCodexHubCardState(for: selection.provider),
              let pool = state.pool,
              !state.isSwitching, !state.switchStatus.isPending,
              pool.canSwitch(to: selection.account)
        else { return }
        // A hub switch moves every Mac that uses the hub, so it is confirmed outside the open menu first.
        menu?.cancelTracking()
        let isHubLocal = pool.isHubLocal
        let details = OpenCodexHubPresentation.confirmationDetails(
            account: selection.account,
            isHubLocal: isHubLocal,
            everyMacMoves: L("Every Mac that uses this hub moves to this account on its next request."))
        Task { @MainActor [weak self] in
            guard let self, OpenCodexHubSwitchConfirmation.confirm(accountLabel: selection.label, details: details)
            else { return }
            self.store.switchOpenCodexHubAccount(
                selection.account,
                provider: selection.provider,
                label: selection.label,
                progressDidChange: { [weak self] in self?.invalidateMenus() })
        }
    }

    func addOpenCodexHubNotice(_ text: String, to menu: NSMenu) {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }
}

/// The confirmation every opencodex hub switch shows (Claude, Codex and Grok cards).
///
/// "Switch Account..." is the first, default button (Return) and "Cancel" the second (Escape), as in the
/// Claude account switch. NSAlert picks its compact or wide layout from the height of the text, so a long
/// near-limit warning arranged (and exposed to accessibility) the buttons differently from a short
/// confirmation. A fixed-width accessory keeps one layout for every target.
enum OpenCodexHubSwitchConfirmation {
    static let layoutWidth: CGFloat = 360

    static func makeAlert(accountLabel: String, details: String) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Switch the opencodex hub to %@?", accountLabel)
        alert.informativeText = details
        alert.accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: self.layoutWidth, height: 0))
        alert.addButton(withTitle: L("Switch Account..."))
        let cancel = alert.addButton(withTitle: L("Cancel"))
        cancel.keyEquivalent = "\u{1B}"
        return alert
    }

    @MainActor
    static func confirm(accountLabel: String, details: String) -> Bool {
        let alert = self.makeAlert(accountLabel: accountLabel, details: details)
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
