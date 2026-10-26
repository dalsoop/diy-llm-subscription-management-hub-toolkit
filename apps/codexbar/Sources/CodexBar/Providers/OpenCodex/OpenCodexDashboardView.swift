import AppKit
import SwiftUI
import WebKit

/// Static English-key → Korean manifest for T4's existing locale catalogs. No catalog wiring lives here.
enum OpenCodexDashboardLocalization {
    static let manifest: [String: String] = [
        "Opencodex Dashboard": "Opencodex 대시보드",
        "Loading Opencodex dashboard…": "Opencodex 대시보드를 불러오는 중…",
        "Current dashboard address": "현재 대시보드 주소",
        "Retry dashboard": "대시보드 다시 시도",
        "Open in browser": "브라우저에서 열기",
        "Manage Opencodex on the hub for this connection.": "이 연결의 Opencodex는 허브에서 관리해 주세요.",
        "The Opencodex server is stopped. Start it and try again.": "Opencodex 서버가 중지되어 있습니다. 서버를 시작한 뒤 다시 시도해 주세요.",
        "The Opencodex status response is invalid.": "Opencodex 상태 응답 형식이 올바르지 않습니다.",
        "The dashboard address is missing or unsafe.": "대시보드 주소가 없거나 안전하지 않습니다.",
        "Could not read Opencodex status.": "Opencodex 상태를 읽지 못했습니다.",
        "Could not load the Opencodex dashboard.": "Opencodex 대시보드를 불러오지 못했습니다.",
        "A secure connection to the dashboard could not be established.": "대시보드에 안전하게 연결하지 못했습니다.",
        "An external page was blocked. Open it in your browser to continue.":
            "외부 페이지 이동이 차단되었습니다. 계속하려면 브라우저에서 열어 주세요.",
        "Could not open the external browser.": "외부 브라우저를 열지 못했습니다.",
        "Could not create the dashboard window.": "대시보드 창을 만들지 못했습니다.",
    ]
}

@MainActor
struct OpenCodexDashboardView: View {
    let state: OpenCodexDashboardState
    let webView: WKWebView
    let retry: @MainActor () async -> Void
    let openExternal: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if self.state.phase == .loading || self.state.isRefreshingStatus {
                    ProgressView().controlSize(.small)
                    Text(L("Loading Opencodex dashboard…"))
                }
                if let url = self.state.currentURL {
                    Text(verbatim: url.absoluteString)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .accessibilityLabel(L("Current dashboard address"))
                }
                Spacer(minLength: 8)
                Button(L("Retry dashboard")) { Task { await self.retry() } }
                    .disabled(self.state.isRefreshingStatus)
            }
            .padding(12)
            Divider()
            if let failure = self.state.failure {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text(L(failure.localizationKey)).multilineTextAlignment(.center)
                    if self.state.canOpenExternal {
                        Button(L("Open in browser"), action: self.openExternal)
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                OpenCodexDashboardWebView(webView: self.webView)
            }
        }
        .frame(minWidth: 640, minHeight: 440)
    }
}

private struct OpenCodexDashboardWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { self.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// Owns exactly one window, WebView, and private nonpersistent store until close. No cookie imports,
/// script handlers, injected scripts, request/HTML logging, or custom authentication challenge handling.
@MainActor
final class OpenCodexDashboardWebSession: NSObject, OpenCodexDashboardSession,
    NSWindowDelegate, WKNavigationDelegate, WKUIDelegate
{
    private(set) var webView: WKWebView?
    private var window: NSWindow?
    private let callbacks: OpenCodexDashboardSessionCallbacks
    private let presentWindow: @MainActor (NSWindow) -> Void
    private var activeNavigation: WKNavigation?
    private var acceptsEvents = true
    private var isClosed = false
    private var activationObserver: NSObjectProtocol?

    init(
        state: OpenCodexDashboardState,
        callbacks: OpenCodexDashboardSessionCallbacks,
        presentWindow: @escaping @MainActor (NSWindow) -> Void = {
            $0.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        })
    {
        self.callbacks = callbacks
        self.presentWindow = presentWindow
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        self.window = window
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        window.delegate = self
        window.title = L("Opencodex Dashboard")
        window.identifier = NSUserInterfaceItemIdentifier("com.steipete.codexbar.opencodex-dashboard")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 440)
        window.center()
        // The session callbacks are weak-owner closures, so the view never retains the controller/session.
        window.contentViewController = NSHostingController(rootView: OpenCodexDashboardView(
            state: state,
            webView: webView,
            retry: { await callbacks.retry() },
            openExternal: { callbacks.openExternal() }))
        self.activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main)
        { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isClosed else { return }
                self.callbacks.activated()
            }
        }
    }

    isolated deinit {
        self.dispose(closeWindow: true)
    }

    func load(_ url: URL) {
        guard !self.isClosed, let webView = self.webView else { return }
        self.acceptsEvents = true
        self.activeNavigation = webView.load(URLRequest(url: url))
    }

    func present() {
        guard !self.isClosed, let window = self.window else { return }
        self.presentWindow(window)
    }

    func stop() {
        self.acceptsEvents = false
        self.activeNavigation = nil
        self.webView?.stopLoading()
    }

    func close() {
        self.dispose(closeWindow: true)
    }

    func windowWillClose(_ notification: Notification) {
        self.dispose(closeWindow: false)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard !self.isClosed else { return }
        self.callbacks.activated()
    }

    private func dispose(closeWindow: Bool) {
        guard !self.isClosed else { return }
        self.isClosed = true
        self.stop()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        self.activationObserver = nil
        self.webView?.navigationDelegate = nil
        self.webView?.uiDelegate = nil
        self.webView?.removeFromSuperview()
        self.window?.delegate = nil
        self.window?.contentViewController = nil
        self.window?.contentView = nil
        if closeWindow { self.window?.close() }
        self.window = nil
        self.webView = nil
        self.callbacks.closed()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void)
    {
        let newWindow = navigationAction.targetFrame == nil
        let allowed = self.callbacks.navigation(
            navigationAction.request.url,
            navigationAction.navigationType,
            navigationAction.targetFrame?.isMainFrame == true,
            newWindow)
        if allowed, newWindow, let url = navigationAction.request.url {
            self.load(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(allowed ? .allow : .cancel)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void)
    {
        let allowed = self.callbacks.navigation(
            navigationResponse.response.url, .other, navigationResponse.isForMainFrame, false)
        if allowed, navigationResponse.isForMainFrame,
           let response = navigationResponse.response as? HTTPURLResponse, response.statusCode >= 400
        {
            self.callbacks.event(.failed(.loading))
            decisionHandler(.cancel)
        } else {
            decisionHandler(allowed ? .allow : .cancel)
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures) -> WKWebView?
    {
        // Defensive public-API fallback. A nil target alone must never authorize a popup.
        if self.callbacks.navigation(navigationAction.request.url, navigationAction.navigationType, false, true),
           let url = navigationAction.request.url
        {
            self.load(url)
        }
        return nil
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard !self.isClosed, self.acceptsEvents else { return }
        self.activeNavigation = navigation
        self.callbacks.event(.started(webView.url))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard self.isCurrent(navigation) else { return }
        self.callbacks.event(.finished(webView.url))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        self.failed(navigation, error: error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error)
    {
        self.failed(navigation, error: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard !self.isClosed else { return }
        self.callbacks.event(.failed(.loading))
    }

    private func isCurrent(_ navigation: WKNavigation?) -> Bool {
        !self.isClosed && self.acceptsEvents && (self.activeNavigation == nil || self.activeNavigation === navigation)
    }

    private func failed(_ navigation: WKNavigation?, error: any Error) {
        guard self.isCurrent(navigation), let failure = OpenCodexDashboardFailure.navigationError(error) else { return }
        self.callbacks.event(.failed(failure))
    }
}
