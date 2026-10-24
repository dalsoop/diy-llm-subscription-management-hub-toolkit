import CodexBarCore
import Foundation
import Testing
import WebKit
@testable import CodexBar

@MainActor
struct OpenCodexDashboardWindowTests {
    @Test
    func `same connection reuses session without reloading and close releases it`() {
        let harness = DashboardHarness()
        let controller = harness.controller
        #expect(controller
            .open(status: Self.status(), connectionID: "first", refreshStatus: { Self.status() }) == .created)
        weak var first = harness.sessions.last
        #expect(controller
            .open(status: Self.status(), connectionID: "first", refreshStatus: { Self.status() }) == .reused)
        #expect(first?.loads.count == 1)
        #expect(first?.presentations == 2)
        first?.callbacks.activated()
        #expect(harness.activations == 1)
        first?.callbacks.closed()
        #expect(harness.activations == 2)
        harness.sessions.removeAll()
        #expect(first == nil)
        #expect(controller.state.phase == .closed)
        #expect(controller
            .open(status: Self.status(), connectionID: "first", refreshStatus: { Self.status() }) == .created)
        #expect(harness.created == 2)
    }

    @Test
    func `connection identity and destination changes discard prior sessions and stale events`() {
        let harness = DashboardHarness()
        let controller = harness.controller
        controller.open(status: Self.status(), connectionID: "one", refreshStatus: { Self.status() })
        let old = harness.sessions[0]
        controller.open(
            status: Self.status(),
            connectionID: "two",
            refreshStatus: { Self.status() })
        #expect(old.closed)
        #expect(harness.created == 2)
        old.callbacks.event(.failed(.tls))
        old.callbacks.closed()
        #expect(controller.state.phase == .loading)
        controller.open(
            status: Self.status("https://other.invalid/dashboard"),
            connectionID: "two",
            refreshStatus: { Self.status() })
        #expect(harness.created == 3)
    }

    @Test
    func `invalid status never constructs or loads a web session`() {
        let harness = DashboardHarness()
        let invalid: [OpenCodexAccessStatus] = [
            Self.status(role: .client), Self.status(role: .unknown), Self.status(running: false),
            Self.status("http://remote.invalid"), Self.status("https://user:password@example.invalid"),
            Self.status("file:///tmp/dashboard.html"),
            OpenCodexAccessStatus(schemaVersion: 2, runtimeRole: .hub, proxyRunning: true, dashboardURL: nil),
        ]
        for status in invalid {
            #expect(harness.controller
                .open(status: status, connectionID: "bad", refreshStatus: { Self.status() }) == .rejected)
            #expect(harness.controller.state.failure != nil)
            #expect(harness.controller.state.currentURL == nil)
        }
        #expect(harness.created == 0)
    }

    @Test
    func `all cross origin navigation types require native confirmation including new windows`() throws {
        let harness = DashboardHarness()
        let controller = harness.controller
        controller.open(status: Self.status(), connectionID: "local", refreshStatus: { Self.status() })
        let callbacks = try #require(harness.sessions.first?.callbacks)
        let external = try #require(URL(string: "https://auth.invalid/sign-in"))
        let types: [WKNavigationType] = [
            .linkActivated, .other, .formSubmitted, .backForward, .reload, .formResubmitted,
        ]
        for type in types {
            #expect(!callbacks.navigation(external, type, true, false))
            #expect(harness.browserURLs.isEmpty)
            #expect(controller.state.failure == .externalNavigation)
            #expect(controller.state.canOpenExternal)
            #expect(!callbacks.navigation(external, type, false, true))
            #expect(harness.browserURLs.isEmpty)
            #expect(controller.state.failure == .externalNavigation)
            #expect(controller.state.canOpenExternal)
        }
        controller.openPendingExternalInBrowser()
        #expect(harness.browserURLs == [external])
        #expect(!callbacks.navigation(URL(string: "https://user:secret@auth.invalid"), .linkActivated, true, false))
        #expect(!callbacks.navigation(URL(string: "javascript:alert(1)"), .linkActivated, false, true))
        #expect(harness.browserURLs == [external])
        #expect(callbacks.navigation(URL(string: "http://localhost:18432/keys"), .other, true, false))
    }

    @Test
    func `unsafe navigation cannot offer external confirmation even when classified as a link`() throws {
        for raw in ["https://user:secret@auth.invalid", "javascript:alert(1)", "http://remote.invalid"] {
            let harness = DashboardHarness()
            let controller = harness.controller
            controller.open(status: Self.status(), connectionID: "local", refreshStatus: { Self.status() })
            let callbacks = try #require(harness.sessions.first?.callbacks)
            #expect(!callbacks.navigation(URL(string: raw), .linkActivated, true, false))
            #expect(controller.state.failure == .invalidAddress)
            #expect(!controller.state.canOpenExternal)
            controller.openPendingExternalInBrowser()
            #expect(harness.browserURLs.isEmpty)
            controller.close()
        }
    }

    @Test
    func `external guidance opens only after explicit native action and subframes do not open browser`() throws {
        let harness = DashboardHarness()
        harness.controller.open(status: Self.status(), connectionID: "local", refreshStatus: { Self.status() })
        let callbacks = try #require(harness.sessions.first?.callbacks)
        let external = try #require(URL(string: "https://auth.invalid"))
        #expect(!callbacks.navigation(external, .linkActivated, false, false))
        #expect(harness.browserURLs.isEmpty)
        #expect(!harness.controller.state.canOpenExternal)
        #expect(!callbacks.navigation(external, .other, true, false))
        #expect(!callbacks.navigation(URL(string: "https://subframe.invalid"), .linkActivated, false, false))
        harness.controller.openPendingExternalInBrowser()
        #expect(harness.browserURLs == [external])
        harness.controller.close()
        harness.controller.openPendingExternalInBrowser()
        #expect(harness.browserURLs.count == 1)
    }

    @Test
    func `loading and TLS failures are fixed and retry rechecks status before loading`() async throws {
        let harness = DashboardHarness()
        var currentStatus = Self.status()
        harness.controller.open(status: currentStatus, connectionID: "local", refreshStatus: { currentStatus })
        let session = try #require(harness.sessions.first)
        session.callbacks.event(.finished(URL(string: "http://localhost:18432/keys?token=synthetic#secret")))
        #expect(harness.controller.state.phase == .ready)
        #expect(harness.controller.state.currentURL?.absoluteString == "http://localhost:18432/keys")
        session.callbacks.event(.failed(.tls))
        #expect(harness.controller.state.failure == .tls)
        currentStatus = Self.status(running: false)
        await harness.controller.retry()
        #expect(harness.controller.state.failure == .serverStopped)
        #expect(session.loads.count == 1)
        currentStatus = Self.status()
        await harness.controller.retry()
        #expect(harness.controller.state.phase == .loading)
        #expect(session.loads.count == 2)
        session.callbacks.event(.failed(.loading))
        #expect(harness.controller.state.failure == .loading)
        #expect(OpenCodexDashboardFailure.tls.localizationKey != OpenCodexDashboardFailure.loading.localizationKey)
    }

    @Test
    func `retry returning after close cannot recreate a session`() async {
        let harness = DashboardHarness()
        var continuation: CheckedContinuation<OpenCodexAccessStatus, Never>?
        harness.controller.open(status: Self.status(), connectionID: "local", refreshStatus: {
            await withCheckedContinuation { continuation = $0 }
        })
        let retry = Task { await harness.controller.retry() }
        while continuation == nil {
            await Task.yield()
        }
        harness.controller.close()
        continuation?.resume(returning: Self.status())
        await retry.value
        #expect(harness.created == 1)
        #expect(harness.controller.state.phase == .closed)
    }

    @Test
    func `window and browser failures are fixed and never expose injected diagnostics`() throws {
        struct SyntheticError: Error {}
        let unavailable = OpenCodexDashboardWindowController(
            makeSession: { _, _ in throw SyntheticError() }, openBrowser: { _ in
                Issue.record("A failed factory must never open a browser")
                return false
            })
        #expect(unavailable.open(
            status: Self.status(), connectionID: "fixture", refreshStatus: { Self.status() }) == .rejected)
        #expect(unavailable.state.failure == .windowUnavailable)
        var callbacks: OpenCodexDashboardSessionCallbacks?
        let blockedBrowser = OpenCodexDashboardWindowController(
            makeSession: { _, received in
                callbacks = received
                return FakeDashboardSession(callbacks: received)
            }, openBrowser: { _ in false })
        blockedBrowser.open(
            status: Self.status(role: .standalone),
            connectionID: "fixture",
            refreshStatus: { Self.status(role: .standalone) })
        let received = try #require(callbacks)
        #expect(!received.navigation(URL(string: "https://auth.invalid"), .linkActivated, true, false))
        #expect(blockedBrowser.state.failure == .externalNavigation)
        blockedBrowser.openPendingExternalInBrowser()
        #expect(blockedBrowser.state.failure == .externalBrowser)
        blockedBrowser.close()
    }

    @Test
    func `repeat retry is coalesced and old connection response cannot load into its replacement`() async {
        let harness = DashboardHarness()
        var reads = 0
        var continuation: CheckedContinuation<OpenCodexAccessStatus, Never>?
        harness.controller.open(status: Self.status(), connectionID: "first", refreshStatus: {
            reads += 1
            return await withCheckedContinuation { continuation = $0 }
        })
        let retry = Task { await harness.controller.retry() }
        while continuation == nil {
            await Task.yield()
        }
        await harness.controller.retry()
        #expect(reads == 1)
        harness.controller.open(status: Self.status(), connectionID: "second", refreshStatus: { Self.status() })
        continuation?.resume(returning: Self.status("https://stale.invalid"))
        await retry.value
        #expect(harness.created == 2)
        #expect(harness.sessions[1].loads.first == Self.status().dashboardURL)
        #expect(harness.sessions[1].loads.count == 1)
    }

    @Test
    func `invalid repeated status closes the old authorized session without loading another address`() {
        let harness = DashboardHarness()
        harness.controller.open(status: Self.status(), connectionID: "local", refreshStatus: { Self.status() })
        let session = harness.sessions[0]
        #expect(harness.controller.open(
            status: Self.status(role: .client),
            connectionID: "local",
            refreshStatus: { Self.status() }) == .rejected)
        #expect(session.closed)
        #expect(session.loads.count == 1)
        #expect(harness.created == 1)
        #expect(harness.controller.state.failure == .unsupportedRole)
    }

    @Test
    func `retry losing local management blocks retained navigation and external guidance`() async throws {
        let harness = DashboardHarness()
        var status = Self.status()
        harness.controller.open(status: status, connectionID: "local", refreshStatus: { status })
        let callbacks = try #require(harness.sessions.first?.callbacks)
        #expect(!callbacks.navigation(URL(string: "https://auth.invalid"), .other, true, false))
        #expect(harness.controller.state.canOpenExternal)
        status = Self.status(role: .client)
        await harness.controller.retry()
        #expect(harness.controller.state.failure == .unsupportedRole)
        #expect(!harness.controller.state.canOpenExternal)
        harness.controller.openPendingExternalInBrowser()
        #expect(harness.browserURLs.isEmpty)
        #expect(!callbacks.navigation(Self.status().dashboardURL, .other, true, false))
        #expect(!callbacks.navigation(URL(string: "https://auth.invalid"), .linkActivated, true, false))
        #expect(harness.browserURLs.isEmpty)
    }

    static func status(
        _ url: String = "http://localhost:18432/dashboard",
        role: OpenCodexRuntimeRole = .hub,
        running: Bool = true) -> OpenCodexAccessStatus
    {
        OpenCodexAccessStatus(runtimeRole: role, proxyRunning: running, dashboardURL: URL(string: url))
    }
}

@MainActor
private final class DashboardHarness {
    var sessions: [FakeDashboardSession] = []
    var browserURLs: [URL] = []
    var created = 0
    var activations = 0
    lazy var controller = OpenCodexDashboardWindowController(
        makeSession: { [unowned self] _, callbacks in
            let session = FakeDashboardSession(callbacks: callbacks)
            self.created += 1
            self.sessions.append(session)
            return session
        },
        openBrowser: { [unowned self] in self.browserURLs.append($0); return true },
        didActivate: { [unowned self] in self.activations += 1 })
}

@MainActor
private final class FakeDashboardSession: OpenCodexDashboardSession {
    let callbacks: OpenCodexDashboardSessionCallbacks
    var loads: [URL] = []
    var presentations = 0
    var closed = false
    init(callbacks: OpenCodexDashboardSessionCallbacks) { self.callbacks = callbacks }
    func load(_ url: URL) { self.loads.append(url) }
    func present() { self.presentations += 1 }
    func stop() {}
    func close() { self.closed = true }
}
