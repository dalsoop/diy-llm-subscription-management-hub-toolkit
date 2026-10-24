import AppKit
import CodexBarCore
import Foundation
import Observation
import XCTest
@testable import CodexBar

/// Codex and Grok cards that read an opencodex hub pool follow the multi-account menu layout: stacked shows
/// every hub account's card at once, segmented shows account tabs above the active account's card.
@MainActor
final class StatusMenuOpenCodexHubAccountsTests: XCTestCase {
    func test_pendingExpiryInvalidatesTheVisibleMenuWithoutAQuotaChange() throws {
        let (controller, store) = self.makeController(provider: .grok, pool: Self.pool(.xai), layout: .stacked)
        defer { controller.releaseStatusItemsForTesting() }
        var state = try XCTUnwrap(store.openCodexHubCardStates[.grok])
        state.switchStatus.begin(OpenCodexHubSwitchRequest(
            provider: .xai,
            targetIDSuffix: "in__",
            targetEmail: "m***n@example.com",
            requestedAt: Date().addingTimeInterval(-OpenCodexHubPendingSwitch.expiryInterval - 1)), label: "Account")
        store.openCodexHubCardStates[.grok] = state
        let before = controller.menuAdjunctReadinessSignature()
        let observed = LockIsolated(false)
        withObservationTracking {
            _ = store.menuObservationToken
        } onChange: {
            observed.setValue(true)
        }
        XCTAssertTrue(store.expireOpenCodexHubPendingSwitch(.grok))
        XCTAssertTrue(observed.value)
        XCTAssertNotEqual(controller.menuAdjunctReadinessSignature(), before)
    }

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

        let root = URL(fileURLWithPath: "/tmp/hub-menu-fixture-\(UUID().uuidString)")
        let environment = ["HOME": root.path]
        let fetcher = UsageFetcher(environment: environment)
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(homeDirectory: root.path, cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: environment)
        store.applyOpenCodexHubPool(pool, provider: provider)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
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

    func test_projectionCarriesAvailableAccountsQuotaAndGatesSwitching() {
        let pool = Self.pool(.openai)
        let accounts = OpenCodexHubAccountProjection.accounts(for: pool, allowsSwitching: true)
        XCTAssertEqual(accounts.map(\.id.opaqueID), ["1", "2"])
        XCTAssertEqual(accounts.map(\.provider), [.codex, .codex])
        XCTAssertEqual(accounts.map(\.displayLabel), [
            "m***n@example.com (go)", "a***e@example.com (pro)",
        ])
        XCTAssertEqual(accounts.map(\.isActive), [false, true])
        // Only an inactive, unpaused account of a switchable pool can be switched to.
        XCTAssertEqual(accounts.map(\.canActivate), [true, false])
        XCTAssertEqual(accounts[0].snapshot?.primary?.windowMinutes, 30 * 24 * 60)
        XCTAssertEqual(accounts[1].snapshot?.primary?.usedPercent, 53)
        XCTAssertTrue(accounts.allSatisfy { $0.error == nil })
        XCTAssertEqual(
            ClaudeSwapAccountMenuDisplay.label(for: accounts[0], hidePersonalInfo: true),
            L("Account %@", "1"))

        let pending = OpenCodexHubAccountProjection.accounts(for: pool, allowsSwitching: false)
        XCTAssertTrue(pending.allSatisfy { !$0.canActivate })
        let hubOnly = OpenCodexHubAccountProjection.accounts(
            for: Self.pool(.openai, switchable: false, origin: .snapshot(hubName: "hub-mac", updatedAt: Date())),
            allowsSwitching: true)
        XCTAssertTrue(hubOnly.allSatisfy { !$0.canActivate })
        XCTAssertEqual(hubOnly.count, 2)
    }

    func test_stackedLayoutShowsEveryHubAccountCardInsteadOfTheSubmenu() {
        for (provider, hubProvider) in [(UsageProvider.codex, OpenCodexHubProvider.openai), (.grok, .xai)] {
            let (controller, _) = self.makeController(
                provider: provider, pool: Self.pool(hubProvider), layout: .stacked)
            defer { controller.releaseStatusItemsForTesting() }
            let menu = controller.makeMenu(for: provider)
            controller.menuWillOpen(menu)
            let ids = self.representedIDs(in: menu)
            XCTAssertEqual(ids.filter { $0.hasPrefix("menuCard") }, ["menuCard-0", "menuCard-1"])
            XCTAssertFalse(menu.items.contains { $0.title == L("Switch opencodex hub account") })
            XCTAssertFalse(ids.contains("openCodexHubSwitcher"))
        }
    }

    func test_switcherQuotasKeepHubInventoryOrderAndUnknownAccounts() {
        var accounts = Self.pool(.openai).accounts
        accounts[0] = OpenCodexHubAccount(
            idSuffix: "0001", label: nil, email: "a***a@example.com", isActive: false)
        let pool = OpenCodexHubPool(provider: .openai, accounts: accounts, switchable: true, origin: .hubLocal)
        let (controller, _) = self.makeController(provider: .codex, pool: pool, layout: .stacked)
        defer { controller.releaseStatusItemsForTesting() }
        let quotas = controller.switcherAccountQuotas(for: .codex)
        XCTAssertEqual(quotas.map(\.id), ["opencodex-hub:1", "opencodex-hub:2"])
        XCTAssertEqual(quotas.map(\.isActive), [false, true])
        XCTAssertNil(quotas[0].percent)
        XCTAssertEqual(quotas[1].percent, 47)
        controller.settings.usageBarsShowUsed = true
        XCTAssertEqual(controller.switcherAccountQuotas(for: .codex)[1].percent, 53)
        XCTAssertTrue(controller.switcherAccountQuotas(for: .grok).isEmpty)
    }

    func test_pausedRegistrationDoesNotDuplicateUsageCardsOrMeters() {
        let pool = OpenCodexHubPool(
            provider: .openai,
            accounts: [
                .init(
                    idSuffix: "in__",
                    label: "Team",
                    email: "a***e@example.com",
                    isActive: false,
                    isPaused: true),
                .init(idSuffix: "1111", label: "Team", email: "a***e@example.com", isActive: true),
                .init(idSuffix: "2222", label: "Team", email: "a***e@example.com", isActive: false),
            ],
            switchable: true,
            origin: .hubLocal)
        let projected = OpenCodexHubAccountProjection.accounts(for: pool, allowsSwitching: true)
        // Equal masked identities are not proof of a duplicate: both unpaused registrations remain.
        XCTAssertEqual(projected.map(\.id.opaqueID), ["2", "3"])
        XCTAssertEqual(projected.map(\.canActivate), [false, true])
        XCTAssertEqual(projected.map {
            OpenCodexHubAccountProjection.hubAccount(for: $0, in: pool)?.idSuffix
        }, ["1111", "2222"])
        XCTAssertEqual(pool.accounts.count, 3)
        for layout in [MultiAccountMenuLayout.stacked, .segmented] {
            let (controller, _) = self.makeController(provider: .codex, pool: pool, layout: layout)
            defer { controller.releaseStatusItemsForTesting() }
            XCTAssertEqual(controller.switcherAccountQuotas(for: .codex).map(\.id), [
                "opencodex-hub:2", "opencodex-hub:3",
            ])
            let menu = controller.makeMenu(for: .codex)
            controller.menuWillOpen(menu)
            if layout == .stacked {
                XCTAssertEqual(self.representedIDs(in: menu).filter { $0.hasPrefix("menuCard-") }.count, 2)
            } else {
                XCTAssertEqual(menu.items.count(where: { $0.view is ClaudeSwapAccountSwitcherView }), 1)
            }
        }
    }

    func test_longHubNoticeWrapsInsideTheProviderMenuWidth() throws {
        let (controller, _) = self.makeController(provider: .codex, pool: Self.pool(.openai), layout: .stacked)
        defer { controller.releaseStatusItemsForTesting() }
        let text = String(repeating: "Account switches are managed on the hub. 계정 전환은 허브에서 관리합니다. ", count: 3)
        let native = NSMenu()
        native.addItem(NSMenuItem(title: text, action: nil, keyEquivalent: ""))
        for width: CGFloat in [310, 380] {
            let menu = NSMenu()
            controller.addOpenCodexHubNotice(text, to: menu, width: width)
            let item = try XCTUnwrap(menu.items.first)
            let view = try XCTUnwrap(item.view)
            XCTAssertEqual(view.frame.width, width, accuracy: 0.5)
            XCTAssertGreaterThan(view.frame.height, NSFont.smallSystemFontSize * 2)
            XCTAssertLessThanOrEqual(menu.size.width, width + 32)
            XCTAssertLessThan(menu.size.width, native.size.width)
            XCTAssertEqual(item.toolTip, text)
            XCTAssertTrue(item.title.isEmpty)
            XCTAssertFalse(item.isEnabled)
        }
    }

    func test_resetNewsAppearsOnceAcrossAccountLayoutsAndMenuRebuilds() {
        for layout in [MultiAccountMenuLayout.stacked, .segmented] {
            let (controller, store) = self.makeController(
                provider: .codex, pool: Self.pool(.openai), layout: layout)
            defer { controller.releaseStatusItemsForTesting() }
            let disabledSignature = controller.menuAdjunctReadinessSignature()
            store.codexResetAnnouncements.configure(
                enabled: true,
                address: CodexResetAnnouncements.defaultProviderURL,
                automaticallyPoll: false)
            XCTAssertNotEqual(controller.menuAdjunctReadinessSignature(), disabledSignature)
            let menu = controller.makeMenu(for: .codex)
            controller.menuWillOpen(menu)
            XCTAssertEqual(self.representedIDs(in: menu).filter { $0 == "codexResetAnnouncements" }.count, 1)
            controller.populateMenu(menu, provider: .codex)
            XCTAssertEqual(self.representedIDs(in: menu).filter { $0 == "codexResetAnnouncements" }.count, 1)
            if layout == .stacked {
                XCTAssertEqual(self.representedIDs(in: menu).filter { $0.hasPrefix("menuCard-") }.count, 2)
            }
            let enabledSignature = controller.menuAdjunctReadinessSignature()
            store.codexResetAnnouncements.configure(
                enabled: false,
                address: CodexResetAnnouncements.defaultProviderURL,
                automaticallyPoll: false)
            XCTAssertNotEqual(controller.menuAdjunctReadinessSignature(), enabledSignature)
            controller.populateMenu(menu, provider: .codex)
            XCTAssertFalse(self.representedIDs(in: menu).contains("codexResetAnnouncements"))
        }
    }

    func test_resetNewsDoesNotAppearInAnotherProviderMenu() {
        let (controller, store) = self.makeController(provider: .grok, pool: Self.pool(.xai), layout: .stacked)
        defer { controller.releaseStatusItemsForTesting() }
        store.codexResetAnnouncements.configure(
            enabled: true,
            address: CodexResetAnnouncements.defaultProviderURL,
            automaticallyPoll: false)
        let menu = controller.makeMenu(for: .grok)
        controller.menuWillOpen(menu)
        XCTAssertFalse(self.representedIDs(in: menu).contains("codexResetAnnouncements"))
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
