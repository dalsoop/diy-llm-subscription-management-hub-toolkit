import AppKit
import CodexBarCore

extension StatusItemController {
    func providerSwitcherHasCurrentQuotaLayout(in menu: NSMenu) -> Bool {
        guard let view = menu.items.first?.view as? ProviderSwitcherView else { return false }
        return !view.requiresMenuRowReplacement
    }

    func makeProviderSwitcherItem(
        providers: [UsageProvider],
        includesOverview: Bool,
        selected: ProviderSwitcherSelection,
        menu: NSMenu,
        width: CGFloat) -> NSMenuItem
    {
        let view = ProviderSwitcherView(
            providers: providers,
            pluginProviders: self.topLevelUserProviderPlugins(),
            selected: selected,
            includesOverview: includesOverview,
            width: width,
            showsIcons: self.settings.switcherShowsIcons,
            iconProvider: { [weak self] provider in
                self?.switcherIcon(for: provider) ?? NSImage()
            },
            pluginIconProvider: { [weak self] plugin in
                self?.userPluginSwitcherIcon(for: plugin) ?? NSImage()
            },
            weeklyRemainingProvider: { [weak self] provider in
                self?.switcherWeeklyRemaining(for: provider)
            },
            accountQuotaProvider: { [weak self] provider in
                self?.switcherAccountQuotas(for: provider) ?? []
            },
            onSelect: { [weak self, weak menu] selection in
                guard let self, let menu else { return }
                MenuSwitchFlickerProbe.debugLog("onSelect \(selection)")
                var provider: UsageProvider?
                self.preservingMergedSwitcherContentCachesDuringInvalidation {
                    switch selection {
                    case .overview:
                        self.settings.mergedMenuLastSelectedWasOverview = true
                        provider = self.resolvedMenuProvider()
                    case let .provider(selectedProvider):
                        self.settings.mergedMenuLastSelectedWasOverview = false
                        self.selectedMenuProvider = selectedProvider
                        provider = selectedProvider.firstPartyProvider
                    }
                    switch selection {
                    case .overview:
                        // Provider-specific by design: Codex is the persisted fallback for an empty overview.
                        self.lastMenuProvider = (provider ?? .codex).instanceID
                    case let .provider(provider):
                        self.lastMenuProvider = provider
                    }
                    self.lastMergedSwitcherSelection = selection
                    self.refreshProviderSelectionDependentUI(deferRendering: true)
                }
                self.requestProviderSwitcherMenuRebuild(menu, provider: provider)
            })
        let item = NSMenuItem()
        item.title = ""
        item.view = view
        item.isEnabled = false
        return item
    }
}
