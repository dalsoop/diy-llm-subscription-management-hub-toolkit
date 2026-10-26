import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
struct AppDelegateTests {
    @Test
    func `refuses the untitled window macOS would fill with the empty Settings scene`() {
        _ = NSApplication.shared
        let appDelegate = AppDelegate()

        #expect(appDelegate.applicationShouldOpenUntitledFile(NSApplication.shared) == false)
    }

    @Test
    func `explicit reopens reveal and reuse Settings without changing the selected pane`() async {
        let application = NSApplication.shared
        let appDelegate = AppDelegate()
        let selection = PreferencesSelection(userDefaults: InMemoryUserDefaults())
        selection.pane = .opencodex
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        var created = 0
        var presented: [NSWindow] = []
        let controller = SettingsWindowController(
            selection: selection,
            makeWindow: {
                created += 1
                return window
            },
            prepareToPresent: {},
            registerWindow: { _ in },
            presentWindow: { presented.append($0) },
            didPresentWindow: { _ in },
            presentationFailed: {})
        appDelegate._test_configureSettingsWindowController(controller)
        await self.drainSettingsRequests()
        #expect(presented.isEmpty)

        #expect(appDelegate.applicationShouldHandleReopen(application, hasVisibleWindows: false) == false)
        await self.drainSettingsRequests()
        window.close()
        #expect(appDelegate.applicationShouldHandleReopen(application, hasVisibleWindows: true) == false)
        await self.drainSettingsRequests()

        #expect(created == 1)
        #expect(presented.count == 2)
        #expect(presented.allSatisfy { $0 === window })
        #expect(selection.pane == .opencodex)
    }

    @Test
    func `early reopens wait for configuration and coalesce into one Settings presentation`() async {
        let application = NSApplication.shared
        let appDelegate = AppDelegate()
        var attempts = 0
        let controller = SettingsWindowController(
            selection: PreferencesSelection(userDefaults: InMemoryUserDefaults()),
            makeWindow: {
                attempts += 1
                return nil
            },
            prepareToPresent: {},
            registerWindow: { _ in },
            presentWindow: { _ in },
            didPresentWindow: { _ in },
            presentationFailed: {})

        #expect(appDelegate.applicationShouldHandleReopen(application, hasVisibleWindows: false) == false)
        #expect(appDelegate.applicationShouldHandleReopen(application, hasVisibleWindows: false) == false)
        await self.drainSettingsRequests()
        #expect(attempts == 0)

        appDelegate._test_configureSettingsWindowController(controller)
        await self.drainSettingsRequests()
        #expect(attempts == 1)
        // A failed presentation must allow a later explicit reopen to retry.
        #expect(appDelegate.applicationShouldHandleReopen(application, hasVisibleWindows: false) == false)
        await self.drainSettingsRequests()
        #expect(attempts == 2)
    }

    private func drainSettingsRequests() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @Test
    func `builds status controller after launch`() {
        let appDelegate = AppDelegate()
        var factoryCalls = 0
        var ttyShutdowns = 0
        let dummyStatusController = DummyStatusController()
        let managedCodexAccountCoordinator = ManagedCodexAccountCoordinator()

        let settings = SettingsStore(
            configStore: testConfigStore(suiteName: "AppDelegateTests"),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let account = fetcher.loadAccountInfo()
        let promotionCoordinator = CodexAccountPromotionCoordinator(
            settingsStore: settings,
            usageStore: store,
            managedAccountCoordinator: managedCodexAccountCoordinator)
        appDelegate.terminateActiveProcessesForAppShutdown = {
            ttyShutdowns += 1
        }

        // Install a test factory that records invocations without touching NSStatusBar.
        StatusItemController.factory = { _, _, _, _, _, receivedManagedCoordinator, receivedPromotionCoordinator in
            factoryCalls += 1
            #expect(receivedManagedCoordinator === managedCodexAccountCoordinator)
            #expect(receivedPromotionCoordinator === promotionCoordinator)
            return dummyStatusController
        }
        defer { StatusItemController.factory = StatusItemController.defaultFactory }

        // configure should not eagerly construct the status controller
        appDelegate.configure(.init(
            store: store,
            settings: settings,
            account: account,
            selection: PreferencesSelection(),
            managedCodexAccountCoordinator: managedCodexAccountCoordinator,
            codexAccountPromotionCoordinator: promotionCoordinator))
        #expect(factoryCalls == 0)

        // construction happens once after launch
        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        #expect(factoryCalls == 1)
        #expect(dummyStatusController.didSetSettingsOpenHandler)

        // idempotent on subsequent calls
        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        #expect(factoryCalls == 1)

        // production termination should ask the status controller to detach AppKit status/menu state
        appDelegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        #expect(dummyStatusController.shutdowns == 1)
        #expect(ttyShutdowns == 1)
    }
}

@MainActor
private final class DummyStatusController: StatusItemControlling {
    private(set) var shutdowns = 0
    private(set) var didSetSettingsOpenHandler = false

    func setSettingsOpenHandler(_: @escaping @MainActor (SettingsPane?) -> Void) {
        self.didSetSettingsOpenHandler = true
    }

    func openMenuFromShortcut() {}
    func runLoginFlowFromSettings(provider _: UsageProvider) async {}
    func prepareForAppShutdown() {
        self.shutdowns += 1
    }
}
