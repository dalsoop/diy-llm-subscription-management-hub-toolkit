import AppKit
import Foundation
import Testing
import WebKit
@testable import CodexBar

@MainActor
struct OpenCodexDashboardWebSessionTests {
    @Test
    func `native session uses a dedicated ephemeral store and renders isolated HTML without scripts`() async throws {
        _ = NSApplication.shared
        var finished = 0
        var closed = 0
        var presented = 0
        let callbacks = OpenCodexDashboardSessionCallbacks(
            closed: { closed += 1 },
            activated: {},
            navigation: { _, _, _, _ in true },
            event: { if case .finished = $0 { finished += 1 } })
        let first = OpenCodexDashboardWebSession(
            state: OpenCodexDashboardState(),
            callbacks: callbacks,
            presentWindow: { _ in presented += 1 })
        let second = OpenCodexDashboardWebSession(
            state: OpenCodexDashboardState(), callbacks: callbacks, presentWindow: { _ in })
        weak var webView = first.webView
        let configuration = try #require(webView?.configuration)
        #expect(!configuration.websiteDataStore.isPersistent)
        #expect(configuration.websiteDataStore !== second.webView?.configuration.websiteDataStore)
        #expect(configuration.userContentController.userScripts.isEmpty)
        #expect(!configuration.preferences.javaScriptCanOpenWindowsAutomatically)
        first.present()
        first.present()
        #expect(presented == 2)
        webView?.loadHTMLString(
            "<!doctype html><title>Synthetic dashboard</title><h1>Offline fixture</h1>",
            baseURL: nil)
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while finished == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(finished == 1)
        #expect(webView?.title == "Synthetic dashboard")
        webView?.loadHTMLString("<!doctype html><title>Second fixture</title><h1>Same session</h1>", baseURL: nil)
        let secondDeadline = ContinuousClock.now.advanced(by: .seconds(15))
        while finished < 2, ContinuousClock.now < secondDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(finished == 2)
        #expect(webView?.title == "Second fixture")
        first.close()
        #expect(first.webView == nil)
        // AppKit/WebKit may drain view/hosting autoreleases on the next main-loop turn.
        let releaseDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while webView != nil, ContinuousClock.now < releaseDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(webView == nil)
        #expect(closed == 1)
        first.close()
        #expect(closed == 1)
        second.close()
    }

    @Test
    func `failure mapping never includes error diagnostics or relaxes TLS`() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorServerCertificateUntrusted,
            userInfo: [NSLocalizedDescriptionKey: "synthetic credential must not be shown"])
        #expect(OpenCodexDashboardFailure.navigationError(error) == .tls)
        #expect(OpenCodexDashboardFailure.navigationError(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)) == .loading)
        #expect(OpenCodexDashboardFailure.navigationError(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)) == nil)
    }
}
