import AppKit
import CodexBarCore
import Observation
import WebKit

@MainActor
@Observable
final class OpenCodexDashboardState {
    enum Phase: Equatable { case closed, loading, ready, failed }

    fileprivate(set) var phase: Phase = .closed
    fileprivate(set) var currentURL: URL?
    fileprivate(set) var failure: OpenCodexDashboardFailure?
    fileprivate(set) var canOpenExternal = false
    fileprivate(set) var isRefreshingStatus = false
}

enum OpenCodexDashboardFailure: Equatable {
    case unsupportedRole, serverStopped, invalidStatus, invalidAddress, statusUnavailable
    case loading, tls, externalNavigation, externalBrowser, windowUnavailable

    var localizationKey: String {
        switch self {
        case .unsupportedRole: "Manage Opencodex on the hub for this connection."
        case .serverStopped: "The Opencodex server is stopped. Start it and try again."
        case .invalidStatus: "The Opencodex status response is invalid."
        case .invalidAddress: "The dashboard address is missing or unsafe."
        case .statusUnavailable: "Could not read Opencodex status."
        case .loading: "Could not load the Opencodex dashboard."
        case .tls: "A secure connection to the dashboard could not be established."
        case .externalNavigation: "An external page was blocked. Open it in your browser to continue."
        case .externalBrowser: "Could not open the external browser."
        case .windowUnavailable: "Could not create the dashboard window."
        }
    }

    static func statusError(_ error: any Error) -> Self {
        switch error as? OpenCodexAccessError {
        case .unsupportedRole: .unsupportedRole
        case .serverStopped: .serverStopped
        case .invalidDashboardURL: .invalidAddress
        case .invalidResponse: .invalidStatus
        default: .statusUnavailable
        }
    }

    static func navigationError(_ error: any Error) -> Self? {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain else { return .loading }
        switch error.code {
        case NSURLErrorCancelled: return nil
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid, NSURLErrorClientCertificateRejected,
             NSURLErrorClientCertificateRequired:
            return .tls
        default: return .loading
        }
    }
}

enum OpenCodexDashboardLoadEvent {
    case started(URL?), finished(URL?), failed(OpenCodexDashboardFailure)
}

@MainActor
struct OpenCodexDashboardSessionCallbacks {
    let closed: @MainActor () -> Void
    let activated: @MainActor () -> Void
    /// Arguments: URL, public WebKit navigation type, main frame, new window.
    let navigation: @MainActor (URL?, WKNavigationType, Bool, Bool) -> Bool
    let event: @MainActor (OpenCodexDashboardLoadEvent) -> Void
    var retry: @MainActor () async -> Void = {}
    var openExternal: @MainActor () -> Void = {}
}

@MainActor
protocol OpenCodexDashboardSession: AnyObject {
    func load(_ url: URL)
    func present()
    func stop()
    func close()
}

/// The app root retains this owner. Settings view reconstruction must not recreate its WebKit session.
@MainActor
final class OpenCodexDashboardWindowController {
    enum Outcome: Equatable { case created, reused, rejected }
    typealias StatusProvider = @MainActor () async throws -> OpenCodexAccessStatus
    typealias SessionFactory = @MainActor (
        OpenCodexDashboardState, OpenCodexDashboardSessionCallbacks) throws -> any OpenCodexDashboardSession

    let state = OpenCodexDashboardState()
    /// Refresh hook for window/app activation and user close (return to native settings).
    var didActivate: @MainActor () -> Void

    private let makeSession: SessionFactory
    private let openBrowser: @MainActor (URL) -> Bool
    private var session: (any OpenCodexDashboardSession)?
    private var destination: OpenCodexDashboardDestination?
    private var connectionID: String?
    private var refreshStatus: StatusProvider?
    private var pendingExternalURL: URL?
    private var generation = UUID()
    private var hasValidStatus = false

    init(
        makeSession: @escaping SessionFactory = { state, callbacks in
            OpenCodexDashboardWebSession(state: state, callbacks: callbacks)
        },
        openBrowser: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) },
        didActivate: @escaping @MainActor () -> Void = {})
    {
        self.makeSession = makeSession
        self.openBrowser = openBrowser
        self.didActivate = didActivate
    }

    /// `status` must be freshly read from the selected source; retry uses that same source closure.
    /// The connection ID should identify the selected executable connection, not just the dashboard URL.
    @discardableResult
    func open(
        status: OpenCodexAccessStatus,
        connectionID: String,
        refreshStatus: @escaping StatusProvider) -> Outcome
    {
        let destination: OpenCodexDashboardDestination
        do {
            destination = try status.dashboardDestination()
        } catch {
            self.close()
            self.connectionID = connectionID
            self.refreshStatus = refreshStatus
            self.fail(.statusError(error))
            return .rejected
        }
        if self.connectionID == connectionID, self.destination == destination, let session {
            self.refreshStatus = refreshStatus
            self.hasValidStatus = true
            session.present()
            return .reused
        }
        self.close()
        self.connectionID = connectionID
        self.refreshStatus = refreshStatus
        self.destination = destination
        self.hasValidStatus = true
        self.state.currentURL = Self.displayURL(destination.url)
        let generation = self.generation
        let callbacks = OpenCodexDashboardSessionCallbacks(
            closed: { [weak self] in
                guard let self, self.generation == generation else { return }
                self.close()
                self.didActivate()
            },
            activated: { [weak self] in
                guard let self, self.generation == generation else { return }
                self.didActivate()
            },
            navigation: { [weak self] url, type, mainFrame, newWindow in
                guard let self, self.generation == generation else { return false }
                return self.navigate(to: url, type: type, mainFrame: mainFrame, newWindow: newWindow)
            },
            event: { [weak self] event in
                guard let self, self.generation == generation else { return }
                self.receive(event)
            },
            retry: { [weak self] in
                guard let self, self.generation == generation else { return }
                await self.retry()
            },
            openExternal: { [weak self] in
                guard let self, self.generation == generation else { return }
                self.openPendingExternalInBrowser()
            })
        do {
            let session = try self.makeSession(self.state, callbacks)
            self.session = session
            self.beginLoad(destination.url)
            session.present()
            return .created
        } catch {
            self.fail(.windowUnavailable)
            return .rejected
        }
    }

    /// Explicit retry only. A stopped server or changed role never reuses a previously authorized URL.
    func retry() async {
        guard let refreshStatus, let connectionID, !self.state.isRefreshingStatus else { return }
        let generation = self.generation
        self.state.isRefreshingStatus = true
        self.hasValidStatus = false
        self.pendingExternalURL = nil
        self.state.canOpenExternal = false
        self.session?.stop()
        do {
            let status = try await refreshStatus()
            guard self.generation == generation else { return }
            self.state.isRefreshingStatus = false
            let destination = try status.dashboardDestination()
            self.hasValidStatus = true
            if self.destination == destination, let session = self.session {
                self.beginLoad(destination.url)
                session.present()
            } else {
                self.open(status: status, connectionID: connectionID, refreshStatus: refreshStatus)
            }
        } catch {
            guard self.generation == generation else { return }
            self.state.isRefreshingStatus = false
            self.fail(.statusError(error))
        }
    }

    /// Called only by the native guidance button; navigation callbacks never auto-open a redirect.
    func openPendingExternalInBrowser() {
        guard self.hasValidStatus, let pendingExternalURL, let destination,
              destination.navigation(to: pendingExternalURL, userInitiated: true) == .externalBrowser
        else { return }
        if !self.openBrowser(pendingExternalURL) { self.fail(.externalBrowser) }
    }

    func close() {
        let previous = self.session
        self.session = nil
        self.generation = UUID()
        self.destination = nil
        self.hasValidStatus = false
        self.connectionID = nil
        self.refreshStatus = nil
        self.pendingExternalURL = nil
        self.state.phase = .closed
        self.state.currentURL = nil
        self.state.failure = nil
        self.state.canOpenExternal = false
        self.state.isRefreshingStatus = false
        previous?.stop()
        previous?.close()
    }

    private func beginLoad(_ url: URL) {
        self.pendingExternalURL = nil
        self.state.canOpenExternal = false
        self.state.failure = nil
        self.state.phase = .loading
        self.state.currentURL = Self.displayURL(url)
        self.session?.load(url)
    }

    private func navigate(to url: URL?, type _: WKNavigationType, mainFrame: Bool, newWindow: Bool) -> Bool {
        guard self.hasValidStatus else { return false }
        guard let url, let destination else {
            if mainFrame || newWindow { self.fail(.invalidAddress) }
            return false
        }
        // Even a page timer's DOM click can be .linkActivated. Only the native guidance button
        // authorizes an external application launch; WebKit navigation types do not prove user input.
        let policy = destination.navigation(to: url, userInitiated: false)
        switch policy {
        case .embedded:
            return true
        case .externalBrowser, .requiresUserAction:
            guard mainFrame || newWindow else { return false }
            self.pendingExternalURL = url
            self.state.canOpenExternal = true
            self.fail(.externalNavigation)
        case .reject:
            if mainFrame || newWindow { self.fail(.invalidAddress) }
        }
        return false
    }

    private func receive(_ event: OpenCodexDashboardLoadEvent) {
        switch event {
        case let .started(url), let .finished(url):
            guard self.state.failure == nil, !self.state.isRefreshingStatus else { return }
            if let url, self.destination?.navigation(to: url, userInitiated: false) == .embedded {
                self.state.currentURL = Self.displayURL(url)
            }
            if case .finished = event { self.state.phase = .ready } else { self.state.phase = .loading }
        case let .failed(failure):
            // Cancellation/failure from the blocked load must not replace the external-navigation guidance.
            guard self.state.failure == nil, !self.state.isRefreshingStatus else { return }
            self.fail(failure)
        }
    }

    private func fail(_ failure: OpenCodexDashboardFailure) {
        self.session?.stop()
        self.state.phase = .failed
        self.state.failure = failure
    }

    private static func displayURL(_ url: URL) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return components?.url
    }
}
