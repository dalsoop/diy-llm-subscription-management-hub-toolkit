import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct MenuRowResponsiveWidthTests {
    @Test
    func `wrapped native notices remeasure height when the popup narrows`() throws {
        let controller = self.controller()
        defer { controller.releaseStatusItemsForTesting() }
        let text = String(repeating: "A long notice stays readable when the provider menu changes width. ", count: 6)
        let item = controller.makeWrappedSecondaryTextItem(text: text, width: 429)
        let view = try #require(item.view as? WrappedSecondaryMenuTextView)
        let wideHeight = view.measuredHeight(width: 429)
        let narrowHeight = view.measuredHeight(width: 310)
        #expect(narrowHeight > wideHeight)
        view.setFrameSize(NSSize(width: 310, height: wideHeight))
        #expect(view.needsWidthRemeasurement)
        let menu = NSMenu()
        menu.addItem(item)
        controller.refreshMenuCardHeights(in: menu)
        #expect(abs(view.frame.height - narrowHeight) <= 1)
        #expect(!view.needsWidthRemeasurement)
    }

    @Test
    func `native menu resize reflows hosted content and cached payloads at the actual width`() throws {
        let previous = StatusItemController.menuCardRenderingEnabled
        StatusItemController.menuCardRenderingEnabled = true
        defer { StatusItemController.menuCardRenderingEnabled = previous }
        let controller = self.controller()
        defer { controller.releaseStatusItemsForTesting() }
        var firstWidths: [CGFloat] = []
        let item = controller.makeMenuCardItem(
            { width in
                firstWidths.append(width)
                return Text("First").frame(width: width)
            },
            id: "reflow",
            width: 310)
        let hosting = try #require(item.view as? MenuRowContainerView)
        for width: CGFloat in [429, 351, 310] {
            hosting.applyMeasuredSize(width: width, height: 80)
            #expect(firstWidths.last == width)
            #expect(hosting.frame.width == width)
        }
        let menu = NSMenu()
        menu.addItem(item)
        menu.addItem(NSMenuItem(title: String(repeating: "W", count: 45), action: nil, keyEquivalent: ""))
        let nativeWidth = controller.renderedMenuWidth(for: menu)
        for _ in 0..<5 {
            controller.refreshMenuCardHeights(in: menu)
            #expect(firstWidths.last == nativeWidth)
            #expect(abs(menu.size.width - nativeWidth) <= 0.5)
        }
        var cachedWidths: [CGFloat] = []
        let cached = controller.makeMenuCardItem(
            { width in
                cachedWidths.append(width)
                return Text("Cached").frame(width: width)
            },
            id: "cached",
            width: 310)
        let cachedHosting = try #require(cached.view as? MenuRowContainerView)
        hosting.applyMeasuredSize(width: 429, height: 80)
        hosting.replant(cachedHosting.rowPayload, refreshMonitor: nil)
        hosting.applyMeasuredSize(width: 429, height: 80)
        #expect(cachedWidths.last == 429)
    }

    @Test
    func `provider grid and subsequent rebuilds use the native popup width`() {
        let controller = self.controller()
        defer { controller.releaseStatusItemsForTesting() }
        let switcher = ProviderSwitcherView(
            providers: [.codex, .claude, .cursor, .antigravity, .grok],
            selected: .provider(.claude),
            includesOverview: true,
            width: 310,
            showsIcons: true,
            iconProvider: { _ in NSImage() },
            weeklyRemainingProvider: { _ in 50 },
            onSelect: { _ in })
        let menu = NSMenu()
        let item = NSMenuItem()
        item.view = switcher
        menu.addItem(item)
        menu.addItem(NSMenuItem(title: String(repeating: "W", count: 45), action: nil, keyEquivalent: ""))
        let nativeWidth = controller.renderedMenuWidth(for: menu)
        controller.refreshMenuCardHeights(in: menu)
        switcher.layoutSubtreeIfNeeded()
        #expect(switcher.frame.width == nativeWidth)
        #expect(abs(switcher._test_buttonFrames()[2].maxX - nativeWidth + 16) <= 1)
        controller.openMenus[ObjectIdentifier(menu)] = menu
        let descriptor = controller.makeMenuDescriptor(provider: .codex, includeContextualActions: false)
        let width = controller.menuCardWidth(
            for: [.codex], selectedProvider: .codex, descriptor: descriptor, renderedMenu: menu)
        #expect(width >= nativeWidth)
    }

    private func controller() -> StatusItemController {
        let settings = testSettingsStore(
            suiteName: "MenuRowResponsiveWidthTests",
            userDefaults: InMemoryUserDefaults(),
            tokenAccountStore: InMemoryTokenAccountStore())
        settings.providerDetectionCompleted = true
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        let root = URL(fileURLWithPath: "/tmp/menu-width-fixture-\(UUID().uuidString)")
        let store = UsageStore(
            fetcher: UsageFetcher(environment: ["HOME": root.path]),
            browserDetection: BrowserDetection(homeDirectory: root.path, cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: ["HOME": root.path])
        return StatusItemController(
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
    }
}
