import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct OpenCodexAccessIntegrationTests {
    @Test
    func `all typed errors resolve to native English and Korean messages`() {
        let errors: [OpenCodexAccessError] = [
            .executableMissing, .unsupportedRole, .serverStopped, .invalidResponse, .outputTooLarge,
            .communicationFailed, .permissionDenied, .notFound, .invalidName, .invalidID,
            .renameUnsupported, .confirmationRequired, .mutationInProgress, .invalidDashboardURL,
        ]
        for error in errors {
            let key = error.accessLocalizationKey
            let english = CodexBarLocalizationOverride.$appLanguage.withValue("en") { L(key) }
            let korean = CodexBarLocalizationOverride.$appLanguage.withValue("ko") { L(key) }
            #expect(english != key)
            #expect(korean != key)
            #expect(korean != english)
        }
    }

    @Test
    func `root construction uses injected stores and never sends requests`() async {
        let harness = IntegrationHarness()
        #expect(await harness.first.calls.isEmpty)
        #expect(harness.windows.sessions.isEmpty)
        #expect(harness.pasteboard.events.isEmpty)
        #expect(harness.defaults.dictionaryRepresentation().isEmpty)
        #expect(harness.feature.store === harness.feature.store)
    }

    @Test
    func `activation refreshes only visible selected active key pane`() async {
        let harness = IntegrationHarness()
        let feature = harness.feature
        await feature.activate(isSettingsVisible: true, selectedPane: .opencodex)
        #expect(await harness.first.calls.isEmpty)
        await feature.store.enter()
        let baseline = await harness.first.calls
        await feature.activate(isSettingsVisible: false, selectedPane: .opencodex)
        await feature.activate(isSettingsVisible: true, selectedPane: .provider(.claude))
        #expect(await harness.first.calls == baseline)
        await feature.activate(isSettingsVisible: true, selectedPane: .opencodex)
        #expect(await harness.first.calls == baseline + ["status", "list"])
        feature.store.leave()
        let inactive = await harness.first.calls
        await feature.activate(isSettingsVisible: true, selectedPane: .opencodex)
        #expect(await harness.first.calls == inactive)
    }

    @Test
    func `dashboard reuses window and return refreshes current key list`() async throws {
        let harness = IntegrationHarness()
        let feature = harness.feature
        await feature.store.enter()
        feature.dashboard.didActivate = {
            Task { await feature.activate(isSettingsVisible: true, selectedPane: .opencodex) }
        }
        await feature.openDashboard()
        await feature.openDashboard()
        #expect(harness.windows.sessions.count == 1)
        let session = try #require(harness.windows.sessions.first)
        #expect(session.loads.count == 1)
        #expect(session.presentations == 2)
        let calls = await harness.first.calls.count
        session.callbacks.closed()
        for _ in 0..<1000 {
            if await harness.first.calls.count >= calls + 2 { break }
            await Task.yield()
        }
        #expect(await harness.first.calls.count == calls + 2)
        #expect(feature.dashboard.state.phase == .closed)
    }

    @Test
    func `client and unknown show guidance without key reads writes or windows`() async {
        for role in [OpenCodexRuntimeRole.client, .unknown] {
            let harness = IntegrationHarness()
            await harness.first.configure(role: role)
            await harness.feature.store.enter()
            await harness.feature.openDashboard()
            #expect(harness.feature.store.refreshError == .unsupportedRole)
            #expect(!harness.feature.store.canMutate)
            #expect(!harness.feature.store.create(name: "synthetic"))
            #expect(harness.feature.dashboard.state.failure == .unsupportedRole)
            #expect(await harness.first.calls == ["status", "status"])
            #expect(harness.windows.sessions.isEmpty)
        }
    }

    @Test
    func `unsupported rename preserves creation and independent path preference`() async {
        let harness = IntegrationHarness()
        harness.defaults.set("provider-preserved", forKey: "claudeCLIPath")
        await harness.feature.store.enter()
        #expect(harness.feature.store.canMutate)
        #expect(!harness.feature.store.canRename)
        #expect(harness.feature.applyExecutablePath("/synthetic/second"))
        #expect(harness.defaults.string(forKey: OpenCodexAccessSettings.executablePathDefaultsKey)
            == "/synthetic/second")
        #expect(harness.defaults.string(forKey: "claudeCLIPath") == "provider-preserved")
        #expect(await harness.second.calls.isEmpty)
        await harness.feature.store.activate()
        #expect(harness.feature.store.canRename)
        #expect(!harness.feature.applyExecutablePath("https://synthetic.invalid/path"))
        #expect(harness.feature.pathIsInvalid)
        #expect(harness.feature.executablePath == "/synthetic/second")
        #expect(harness.feature.applyExecutablePath(""))
        #expect(harness.defaults.string(forKey: OpenCodexAccessSettings.executablePathDefaultsKey)?.isEmpty == true)
    }

    @Test
    func `path changes preserve in flight creation and undisclosed result across navigation`() async throws {
        let harness = IntegrationHarness()
        let feature = harness.feature
        await harness.first.configure(delayCreate: true)
        await feature.store.enter()
        #expect(feature.store.create(name: "synthetic"))
        feature.store.leave()
        #expect(!feature.canChangeConnection)
        #expect(!feature.applyExecutablePath("/synthetic/second"))
        for _ in 0..<1000 {
            if await harness.first.hasPendingCreate { break }
            await Task.yield()
        }
        #expect(await harness.first.hasPendingCreate)
        await harness.first.finishCreate()
        await feature.store.waitForMutation()
        let disclosure = try #require(feature.store.disclosure)
        #expect(!feature.applyExecutablePath("/synthetic/second"))
        #expect(feature.store.disclosure === disclosure)
        #expect(harness.defaults.string(forKey: OpenCodexAccessSettings.executablePathDefaultsKey) == nil)
        #expect(harness.pasteboard.events.isEmpty)
        #expect(!String(reflecting: disclosure).contains("synthetic-secret"))
        feature.store.dismissDisclosure()
        #expect(feature.applyExecutablePath("/synthetic/second"))
        #expect(feature.store.disclosure == nil)
        #expect(await harness.first.calls.filter { $0 == "create" }.count == 1)
    }

    @Test(arguments: [false, true])
    func `obsolete open status success and error cannot replace new connection`(oldFails: Bool) async {
        let harness = IntegrationHarness()
        await harness.first.configure(delayStatus: true)
        let oldOpen = Task { await harness.feature.openDashboard() }
        for _ in 0..<1000 {
            if await harness.first.hasPendingStatus { break }
            await Task.yield()
        }
        #expect(await harness.first.hasPendingStatus)
        #expect(harness.feature.applyExecutablePath("/synthetic/second"))
        await harness.feature.openDashboard()
        #expect(harness.windows.sessions.count == 1)
        let currentURL = harness.feature.dashboard.state.currentURL
        await harness.first.finishStatus(fail: oldFails)
        await oldOpen.value
        #expect(harness.windows.sessions.count == 1)
        #expect(harness.feature.dashboard.state.currentURL == currentURL)
        #expect(harness.feature.dashboardErrorKey == nil)
        #expect(!harness.feature.isOpeningDashboard)
        #expect(harness.feature.applyExecutablePath(""))
        #expect(harness.windows.sessions.first?.closed == true)
        #expect(harness.feature.dashboard.state.phase == .closed)
    }

    @Test
    func `dashboard manifest resolves exactly in Korean and errors are safe`() async {
        for (key, korean) in OpenCodexDashboardLocalization.manifest {
            #expect(CodexBarLocalizationOverride.$appLanguage.withValue("ko") { L(key) } == korean)
            #expect(CodexBarLocalizationOverride.$appLanguage.withValue("en") { L(key) } == key)
        }
        let harness = IntegrationHarness()
        await harness.first.configure(statusError: .permissionDenied)
        await harness.feature.openDashboard()
        #expect(harness.feature.dashboardErrorKey == OpenCodexAccessError.permissionDenied.accessLocalizationKey)
        #expect(harness.windows.sessions.isEmpty)
    }
}

private actor IntegrationSource: OpenCodexAccessSource {
    private var role: OpenCodexRuntimeRole = .hub
    private var delayStatus = false
    private var delayCreate = false
    private var statusError: OpenCodexAccessError?
    private var pendingStatus: CheckedContinuation<OpenCodexAccessStatus, any Error>?
    private var pendingCreate: CheckedContinuation<OpenCodexAccessCreatedKey, any Error>?
    private(set) var calls: [String] = []
    let address: String

    init(address: String) { self.address = address }

    var hasPendingStatus: Bool {
        self.pendingStatus != nil
    }

    var hasPendingCreate: Bool {
        self.pendingCreate != nil
    }

    func configure(
        role: OpenCodexRuntimeRole = .hub,
        delayStatus: Bool = false,
        delayCreate: Bool = false,
        statusError: OpenCodexAccessError? = nil)
    {
        self.role = role
        self.delayStatus = delayStatus
        self.delayCreate = delayCreate
        self.statusError = statusError
    }

    func status() async throws -> OpenCodexAccessStatus {
        self.calls.append("status")
        if self.delayStatus {
            return try await withCheckedThrowingContinuation { self.pendingStatus = $0 }
        }
        if let statusError { throw statusError }
        return self.currentStatus()
    }

    private func currentStatus() -> OpenCodexAccessStatus {
        .init(runtimeRole: self.role, proxyRunning: true, dashboardURL: URL(string: self.address))
    }

    func finishStatus(fail: Bool) {
        if fail {
            self.pendingStatus?.resume(throwing: OpenCodexAccessError.communicationFailed)
        } else {
            self.pendingStatus?.resume(returning: self.currentStatus())
        }
        self.pendingStatus = nil
    }

    func list() async throws -> OpenCodexAccessKeyList {
        self.calls.append("list")
        return .init(keys: [])
    }

    func create(name: String) async throws -> OpenCodexAccessCreatedKey {
        self.calls.append("create")
        if self.delayCreate {
            return try await withCheckedThrowingContinuation { self.pendingCreate = $0 }
        }
        return Self.created()
    }

    private static func created() -> OpenCodexAccessCreatedKey {
        .init(id: "synthetic-id", name: "synthetic", createdAt: .distantPast, secret: .init("synthetic-secret"))
    }

    func finishCreate() {
        self.pendingCreate?.resume(returning: Self.created())
        self.pendingCreate = nil
    }

    func rename(id: String, name: String) async throws -> OpenCodexAccessRenamedKey {
        self.calls.append("rename")
        return .init(id: id, name: name, createdAt: .distantPast)
    }

    func revoke(id: String) async throws { self.calls.append("revoke") }
}

@MainActor
private final class IntegrationSession: OpenCodexDashboardSession {
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

@MainActor
private final class IntegrationWindows {
    var sessions: [IntegrationSession] = []
}

@MainActor
private struct IntegrationHarness {
    let first = IntegrationSource(address: "http://localhost:18432/dashboard")
    let second = IntegrationSource(address: "http://localhost:18433/dashboard")
    let defaults = InMemoryUserDefaults()
    let pasteboard = OpenCodexAccessFakePasteboard()
    let windows = IntegrationWindows()
    let feature: OpenCodexAccessSettings

    init() {
        let windows = self.windows
        let dashboard = OpenCodexDashboardWindowController(
            makeSession: { _, callbacks in
                let session = IntegrationSession(callbacks: callbacks)
                windows.sessions.append(session)
                return session
            },
            openBrowser: { _ in Issue.record("Unexpected browser open"); return false })
        let first = self.first
        let second = self.second
        self.feature = OpenCodexAccessSettings(
            defaults: self.defaults,
            clipboard: OpenCodexAccessClipboard(pasteboard: self.pasteboard, schedule: { _, _ in }),
            dashboard: dashboard,
            makeConnection: { path in
                let isSecond = path == "/synthetic/second"
                return .init(
                    source: isSecond ? second : first,
                    identity: isSecond ? "second" : "first",
                    renameCapability: isSecond ? .available : .unsupported)
            })
    }
}
