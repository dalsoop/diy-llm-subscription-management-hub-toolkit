import AppKit
import CodexBarCore
import Foundation
import XCTest
@testable import CodexBar

/// Codex and Grok cards that read an opencodex hub pool follow the multi-account menu layout: stacked shows
/// every hub account's card at once, segmented shows account tabs above the active account's card.
@MainActor
final class StatusMenuOpenCodexHubAccountsTests: XCTestCase {
    private func makeController(
        provider: UsageProvider,
        pool: OpenCodexHubPool,
        layout: MultiAccountMenuLayout) -> (controller: StatusItemController, store: UsageStore)
    {
        StatusItemController.menuCardRenderingEnabled = false
        StatusItemController.setMenuRefreshEnabledForTesting(false)
        let settings = testSettingsStore(
            suiteName: "StatusMenuOpenCodexHubAccountsTests",
            userDefaults: InMemoryUserDefaults(),
            tokenAccountStore: InMemoryTokenAccountStore())
        settings.providerDetectionCompleted = true
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        settings.multiAccountMenuLayout = layout
        let registry = ProviderRegistry.shared
        for candidate in UsageProvider.allCases {
            guard let metadata = registry.metadata[candidate] else { continue }
            settings.setProviderEnabled(provider: candidate, metadata: metadata, enabled: candidate == provider)
        }
        settings.setOpenCodexHubEnabled(true, for: provider)

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        store.applyOpenCodexHubPool(pool, provider: provider)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        return (controller, store)
    }

    private static func pool(
        _ provider: OpenCodexHubProvider,
        switchable: Bool = true,
        origin: OpenCodexHubPoolOrigin = .hubLocal) -> OpenCodexHubPool
    {
        let weekly = { (used: Double) in
            OpenCodexHubQuota(weekly: OpenCodexHubQuotaWindow(usedPercent: used, resetsAt: nil))
        }
        return OpenCodexHubPool(
            provider: provider,
            accounts: [
                OpenCodexHubAccount(
                    idSuffix: "in__",
                    label: "go",
                    email: "m***n@example.com",
                    isActive: false,
                    quota: OpenCodexHubQuota(monthly: OpenCodexHubQuotaWindow(usedPercent: 0, resetsAt: nil))),
                OpenCodexHubAccount(
                    idSuffix: "3093",
                    label: "pro",
                    email: "a***e@example.com",
                    isActive: true,
                    quota: weekly(53)),
                OpenCodexHubAccount(
                    idSuffix: "4d1e",
                    label: nil,
                    email: "c***c@example.com",
                    isActive: false,
                    isPaused: true,
                    quota: weekly(10)),
            ],
            switchable: switchable,
            switchReason: switchable ? nil : "Switched only on hub-mac.",
            origin: origin)
    }

    private func representedIDs(in menu: NSMenu) -> [String] {
        menu.items.compactMap { $0.representedObject as? String }
    }

    func test_projectionCarriesEveryAccountsQuotaAndGatesSwitching() {
        let pool = Self.pool(.openai)
        let accounts = OpenCodexHubAccountProjection.accounts(for: pool, allowsSwitching: true)
        XCTAssertEqual(accounts.map(\.id.opaqueID), ["1", "2", "3"])
        XCTAssertEqual(accounts.map(\.provider), [.codex, .codex, .codex])
        XCTAssertEqual(accounts.map(\.displayLabel), [
            "m***n@example.com (go)", "a***e@example.com (pro)", "c***c@example.com",
        ])
        XCTAssertEqual(accounts.map(\.isActive), [false, true, false])
        // Only an inactive, unpaused account of a switchable pool can be switched to.
        XCTAssertEqual(accounts.map(\.canActivate), [true, false, false])
        XCTAssertEqual(accounts[0].snapshot?.primary?.windowMinutes, 30 * 24 * 60)
        XCTAssertEqual(accounts[1].snapshot?.primary?.usedPercent, 53)
        XCTAssertEqual(accounts[2].error, L("Disabled"))
        XCTAssertEqual(
            ClaudeSwapAccountMenuDisplay.label(for: accounts[0], hidePersonalInfo: true),
            L("Account %@", "1"))

        let pending = OpenCodexHubAccountProjection.accounts(for: pool, allowsSwitching: false)
        XCTAssertTrue(pending.allSatisfy { !$0.canActivate })
        let hubOnly = OpenCodexHubAccountProjection.accounts(
            for: Self.pool(.openai, switchable: false, origin: .snapshot(hubName: "hub-mac", updatedAt: Date())),
            allowsSwitching: true)
        XCTAssertTrue(hubOnly.allSatisfy { !$0.canActivate })
        XCTAssertEqual(hubOnly.count, 3)
    }

    func test_stackedLayoutShowsEveryHubAccountCardInsteadOfTheSubmenu() {
        for (provider, hubProvider) in [(UsageProvider.codex, OpenCodexHubProvider.openai), (.grok, .xai)] {
            let (controller, _) = self.makeController(
                provider: provider, pool: Self.pool(hubProvider), layout: .stacked)
            defer { controller.releaseStatusItemsForTesting() }
            let menu = controller.makeMenu(for: provider)
            controller.menuWillOpen(menu)
            let ids = self.representedIDs(in: menu)
            XCTAssertEqual(ids.filter { $0.hasPrefix("menuCard") }, ["menuCard-0", "menuCard-1", "menuCard-2"])
            XCTAssertFalse(menu.items.contains { $0.title == L("Switch opencodex hub account") })
            XCTAssertFalse(ids.contains("openCodexHubSwitcher"))
        }
    }

    func test_segmentedLayoutShowsTabsAndInspectsAnotherAccountWithoutSwitching() {
        let (controller, store) = self.makeController(provider: .codex, pool: Self.pool(.openai), layout: .segmented)
        defer { controller.releaseStatusItemsForTesting() }
        let menu = controller.makeMenu(for: .codex)
        controller.menuWillOpen(menu)
        XCTAssertEqual(menu.items.count(where: { $0.view is ClaudeSwapAccountSwitcherView }), 1)
        XCTAssertFalse(menu.items.contains { $0.title.hasPrefix(L("Details for %@", "")) })
        XCTAssertFalse(self.representedIDs(in: menu).contains { $0.hasPrefix("menuCard-") })

        controller.inspectOpenCodexHubAccount(
            ProviderAccountIdentity(source: OpenCodexHubAccountProjection.identitySource, opaqueID: "1"),
            provider: .codex,
            menu: nil)
        controller.settings.hidePersonalInfo = true
        controller.populateMenu(menu, provider: .codex)
        XCTAssertTrue(menu.items.contains { $0.title == String(format: L("Details for %@"), L("Account %@", "1")) })
        XCTAssertEqual(self.representedIDs(in: menu).filter { $0.hasPrefix("menuCard-") }, ["menuCard-0"])
        XCTAssertEqual(store.openCodexHubCardState(for: .codex)?.isSwitching, false)
        XCTAssertFalse(store.openCodexHubCardState(for: .codex)?.switchStatus.isPending ?? true)

        controller.menuDidClose(menu)
        XCTAssertNil(store.openCodexHubCardState(for: .codex)?.inspectedAccountID)
    }

    func test_singleAccountPoolKeepsTheProviderCard() {
        let pool = OpenCodexHubPool(
            provider: .xai,
            accounts: [OpenCodexHubAccount(idSuffix: "9999", label: nil, email: "a***e@example.com", isActive: true)],
            switchable: true,
            origin: .hubLocal)
        let (controller, _) = self.makeController(provider: .grok, pool: pool, layout: .stacked)
        defer { controller.releaseStatusItemsForTesting() }
        let menu = controller.makeMenu(for: .grok)
        controller.menuWillOpen(menu)
        XCTAssertFalse(self.representedIDs(in: menu).contains { $0.hasPrefix("menuCard-") })
    }
}
