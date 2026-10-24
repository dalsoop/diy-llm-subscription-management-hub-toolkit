import AppKit
import CodexBarCore
import Testing
import WebKit
@testable import CodexBar

@MainActor
struct OpenCodexDashboardNavigationIntegrationTests {
    @Test(arguments: ["link", "blank"])
    func `DOM links traverse real WebKit native session and controller policy`(_ element: String) async throws {
        let fixture = OfflineDashboardNavigationFixture()
        defer { fixture.controller.close() }
        let session = try await fixture.start()
        // DOM click is not a physical user gesture. Assert WebKit's actual classification instead.
        let result = try await session.evaluate("document.getElementById('\(element)').click(); 'clicked-\(element)'")
        #expect(result as? String == "clicked-\(element)")
        let action = try await session.externalDecision()
        #expect(action.type == .linkActivated)
        #expect(action.newWindow == (element == "blank"))
        #expect(action.mainFrame == (element == "link"))
        #expect(action.policy == .cancel)
        #expect(fixture.browserURLs.isEmpty)
        #expect(fixture.controller.state.failure == .externalNavigation)
        #expect(fixture.controller.state.canOpenExternal)
        print("Offline DOM link \(element) browser recordings before confirmation: \(fixture.browserURLs.count)")
        session.confirmExternal()
        #expect(fixture.browserURLs == [OfflineDashboardNavigationFixture.externalURL])
        print("Offline DOM link \(element) browser recordings after confirmation: \(fixture.browserURLs.count)")
        #expect(session.newWindowCallbacks == 0)
    }

    @Test
    func `page timer DOM click requires native confirmation despite link activated navigation type`() async throws {
        let fixture = OfflineDashboardNavigationFixture(script: """
        window.fixtureResult = 'automatic-click';
        document.getElementById('link').click();
        """)
        defer { fixture.controller.close() }
        let session = try await fixture.start()
        #expect(try await session.scriptResult() == "automatic-click")
        let action = try await session.externalDecision()
        // A timer-generated link activation is not permission to launch an external application.
        #expect(action.type == .linkActivated)
        #expect(action.mainFrame)
        #expect(!action.newWindow)
        #expect(action.policy == .cancel)
        #expect(fixture.browserURLs.isEmpty)
        #expect(fixture.controller.state.failure == .externalNavigation)
        #expect(fixture.controller.state.canOpenExternal)
        print("Offline automatic DOM click browser recordings before confirmation: \(fixture.browserURLs.count)")
        session.confirmExternal()
        #expect(fixture.browserURLs == [OfflineDashboardNavigationFixture.externalURL])
        print("Offline automatic DOM click browser recordings after confirmation: \(fixture.browserURLs.count)")
        #expect(session.newWindowCallbacks == 0)
    }

    @Test
    func `script top level navigation is cancelled with native guidance instead of browser launch`() async throws {
        let fixture = OfflineDashboardNavigationFixture(script: """
        window.fixtureResult = 'assigned';
        location.href = document.getElementById('link').href;
        """)
        defer { fixture.controller.close() }
        let session = try await fixture.start()
        #expect(try await session.scriptResult() == "assigned")
        let action = try await session.externalDecision()
        #expect(action.type == .other)
        #expect(action.mainFrame)
        #expect(!action.newWindow)
        #expect(action.policy == .cancel)
        #expect(fixture.browserURLs.isEmpty)
        #expect(fixture.controller.state.failure == .externalNavigation)
        #expect(fixture.controller.state.canOpenExternal)
        session.confirmExternal()
        #expect(fixture.browserURLs == [OfflineDashboardNavigationFixture.externalURL])
        #expect(session.newWindowCallbacks == 0)
    }

    @Test
    func `default WebKit configuration blocks automatic popup before navigation policy`() async throws {
        let fixture = OfflineDashboardNavigationFixture(script: """
        const blocked = window.open(document.getElementById('link').href, '_blank') === null;
        window.fixtureResult = blocked ? 'popup-blocked' : 'popup-created';
        location.hash = 'popup-attempt-finished';
        """)
        defer { fixture.controller.close() }
        let session = try await fixture.start()
        // A positive runtime result and a subsequent real same-origin action prove the attempt executed.
        #expect(try await session.scriptResult() == "popup-blocked")
        try await session.wait { session.decisions.contains { $0.url.fragment == "popup-attempt-finished" } }
        let witness = try #require(session.decisions.last { $0.url.fragment == "popup-attempt-finished" })
        #expect(witness.policy == .allow)
        #expect(witness.mainFrame)
        #expect(session.decisions.allSatisfy { $0.url.host == OfflineDashboardNavigationFixture.origin.host })
        #expect(fixture.browserURLs.isEmpty)
        #expect(fixture.controller.state.failure == nil)
        #expect(session.newWindowCallbacks == 0)
    }
}

@MainActor
private final class OfflineDashboardNavigationFixture {
    static let origin = URL(string: "https://dashboard.invalid/offline")!
    static let externalURL = URL(string: "https://auth.invalid/sign-in")!
    var session: OfflineDashboardNavigationSession?
    var browserURLs: [URL] = []
    let script: String
    lazy var controller = OpenCodexDashboardWindowController(
        makeSession: { [unowned self] state, callbacks in
            let session = try OfflineDashboardNavigationSession(
                state: state,
                callbacks: callbacks,
                script: self.script)
            self.session = session
            return session
        },
        openBrowser: { [unowned self] url in
            self.browserURLs.append(url)
            return true
        })

    init(script: String = "") {
        self.script = script
    }

    func start() async throws -> OfflineDashboardNavigationSession {
        _ = NSApplication.shared
        let status = OpenCodexAccessStatus(runtimeRole: .hub, proxyRunning: true, dashboardURL: Self.origin)
        #expect(self.controller.open(status: status, connectionID: "offline", refreshStatus: { status }) == .created)
        let session = try #require(self.session)
        try await session.wait { session.finished > 0 }
        if self.script.isEmpty { #expect(self.controller.state.phase == .ready) }
        #expect(session.decisions.contains { $0.url == Self.origin && $0.policy == .allow })
        // Cancelling automatic navigation can transiently reset WKWebView.title; the document remains loaded.
        #expect(try await session.evaluate("document.title") as? String == "Offline navigation fixture")
        return session
    }
}

/// Replaces only transport/presentation. Every real WKNavigationAction and all controller callbacks
/// pass through the production native session; no synthesized action or direct fake callback is used.
@MainActor
private final class OfflineDashboardNavigationSession: NSObject, OpenCodexDashboardSession,
    WKNavigationDelegate, WKUIDelegate
{
    struct Decision {
        let url: URL
        let type: WKNavigationType
        let mainFrame: Bool
        let newWindow: Bool
        let policy: WKNavigationActionPolicy
    }

    let native: OpenCodexDashboardWebSession
    let webView: WKWebView
    let script: String
    let confirmExternal: @MainActor () -> Void
    var decisions: [Decision] = []
    var finished = 0
    var newWindowCallbacks = 0

    init(
        state: OpenCodexDashboardState,
        callbacks: OpenCodexDashboardSessionCallbacks,
        script: String) throws
    {
        self.script = script
        self.confirmExternal = callbacks.openExternal
        self.native = OpenCodexDashboardWebSession(state: state, callbacks: callbacks, presentWindow: { _ in })
        self.webView = try #require(self.native.webView)
        #expect(!self.webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically)
        super.init()
        self.webView.navigationDelegate = self
        self.webView.uiDelegate = self
    }

    func load(_ url: URL) {
        #expect(url == OfflineDashboardNavigationFixture.origin)
        self.webView.loadHTMLString("""
        <!doctype html>
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'">
        <title>Offline navigation fixture</title>
        <a id="link" href="https://auth.invalid/sign-in">Ordinary link</a>
        <a id="blank" href="https://auth.invalid/sign-in" target="_blank">New window link</a>
        <script>
        // Run from the page load timer, independent of evaluateJavaScript's gesture semantics.
        window.addEventListener('load', () => setTimeout(() => {
            window.fixtureHadActivation = navigator.userActivation.isActive;
            \(self.script)
        }, 100));
        </script>
        """, baseURL: OfflineDashboardNavigationFixture.origin)
    }

    func present() { self.native.present() }
    func stop() {
        self.native.stop()
        self.webView.stopLoading()
    }

    func close() {
        self.stop()
        self.webView.navigationDelegate = nil
        self.webView.uiDelegate = nil
        self.native.close()
        self.webView.removeFromSuperview()
    }

    func evaluate(_ script: String) async throws -> Any? {
        try await self.webView.evaluateJavaScript(script)
    }

    func scriptResult() async throws -> String {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while ContinuousClock.now < deadline {
            if let result = try await self.evaluate("window.fixtureResult") as? String {
                let hadActivation = try await self.evaluate("window.fixtureHadActivation") as? Bool
                #expect(hadActivation == false)
                print("Offline page script result: \(result), userActivation=\(String(describing: hadActivation))")
                return result
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("The offline page's automatic script did not execute")
        return "missing-runtime-result"
    }

    func wait(until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(condition(), "Required real WebKit observation did not arrive")
    }

    func externalDecision() async throws -> Decision {
        try await self.wait { self.decisions.contains { $0.url == OfflineDashboardNavigationFixture.externalURL } }
        return try #require(self.decisions.last { $0.url == OfflineDashboardNavigationFixture.externalURL })
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void)
    {
        self.native.webView(webView, decidePolicyFor: navigationAction) { policy in
            if let url = navigationAction.request.url {
                print("Offline WebKit action: \(url.absoluteString), type=\(navigationAction.navigationType.rawValue), "
                    + "main=\(navigationAction.targetFrame?.isMainFrame == true), "
                    + "new=\(navigationAction.targetFrame == nil), policy=\(policy.rawValue)")
                self.decisions.append(Decision(
                    url: url,
                    type: navigationAction.navigationType,
                    mainFrame: navigationAction.targetFrame?.isMainFrame == true,
                    newWindow: navigationAction.targetFrame == nil,
                    policy: policy))
            }
            // Fail closed even if a future production regression allows an external request.
            let isOffline = navigationAction.request.url?.host == OfflineDashboardNavigationFixture.origin.host
            #expect(isOffline || policy == .cancel, "Production policy must cancel every external request")
            decisionHandler(isOffline ? policy : .cancel)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void)
    {
        self.native.webView(webView, decidePolicyFor: navigationResponse) { decisionHandler($0) }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        self.native.webView(webView, didStartProvisionalNavigation: navigation)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.native.webView(webView, didFinish: navigation)
        self.finished += 1
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures) -> WKWebView?
    {
        self.newWindowCallbacks += 1
        return self.native.webView(
            webView, createWebViewWith: configuration, for: navigationAction, windowFeatures: windowFeatures)
    }
}
