import CodexBarCore
import Foundation
import Observation
import SwiftUI

/// One app-run owner. Construction inspects installation metadata only and never sends a management request.
@MainActor
@Observable
final class OpenCodexAccessSettings {
    struct Connection {
        let source: any OpenCodexAccessSource
        let identity: String
        let renameCapability: OpenCodexAccessRenameCapability
    }

    typealias ConnectionFactory = @MainActor (String) -> Connection
    static let executablePathDefaultsKey = "opencodexAccessExecutablePath"

    let store: OpenCodexAccessStore
    let dashboard: OpenCodexDashboardWindowController
    let clipboard: OpenCodexAccessClipboard
    private(set) var executablePath: String
    private(set) var pathIsInvalid = false
    private(set) var isOpeningDashboard = false
    private(set) var openError: OpenCodexAccessError?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let makeConnection: ConnectionFactory
    @ObservationIgnored private var connection: Connection
    @ObservationIgnored private var revision: UInt64 = 0
    @ObservationIgnored private var openRequest: UInt64 = 0

    init(
        defaults: UserDefaults,
        clipboard: OpenCodexAccessClipboard,
        dashboard: OpenCodexDashboardWindowController,
        makeConnection: @escaping ConnectionFactory)
    {
        let path = defaults.string(forKey: Self.executablePathDefaultsKey) ?? ""
        let connection = makeConnection(path)
        self.defaults = defaults
        self.clipboard = clipboard
        self.dashboard = dashboard
        self.makeConnection = makeConnection
        self.executablePath = path
        self.connection = connection
        self.store = OpenCodexAccessStore(source: connection.source, renameCapability: connection.renameCapability)
    }

    static func production(defaults: UserDefaults) -> OpenCodexAccessSettings {
        OpenCodexAccessSettings(
            defaults: defaults,
            clipboard: OpenCodexAccessClipboard(pasteboard: OpenCodexAccessSystemPasteboard()),
            dashboard: OpenCodexDashboardWindowController(),
            makeConnection: self.localConnection)
    }

    private static func localConnection(_ configuredPath: String) -> Connection {
        guard let executable = OpenCodexHubReader.resolvedExecutablePath(configuredPath) else {
            return Connection(source: MissingExecutable(), identity: "unresolved", renameCapability: .unsupported)
        }
        // Pin capability inspection and all source operations to the very same resolved installation.
        let path = URL(fileURLWithPath: executable).resolvingSymlinksInPath().standardizedFileURL.path
        let capability: OpenCodexAccessRenameCapability =
            (try? OpenCodexAccessRenameInstallation.resolve(executable: path)) == nil ? .unsupported : .available
        return Connection(
            source: OpenCodexAccessClient(executablePath: path), identity: path, renameCapability: capability)
    }

    var canChangeConnection: Bool {
        !self.store.isMutating && self.store.disclosure == nil
    }

    var dashboardErrorKey: String? {
        self.openError?.accessLocalizationKey ?? self.dashboard.state.failure?.localizationKey
    }

    /// A rejected path edit does not replace the source, release results, close a window, or persist anything.
    @discardableResult
    func applyExecutablePath(_ value: String) -> Bool {
        guard self.canChangeConnection else { return false }
        let path = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.rangeOfCharacter(from: .controlCharacters) == nil,
              path.isEmpty || path.hasPrefix("/") || path.hasPrefix("~/")
        else {
            self.pathIsInvalid = true
            return false
        }
        let replacement = self.makeConnection(path)
        guard self.store.reconfigure(source: replacement.source, renameCapability: replacement.renameCapability)
        else { return false }
        self.revision &+= 1
        self.openRequest &+= 1
        self.isOpeningDashboard = false
        self.dashboard.close()
        self.openError = nil
        self.pathIsInvalid = false
        self.connection = replacement
        self.executablePath = path
        self.defaults.set(path, forKey: Self.executablePathDefaultsKey)
        return true
    }

    /// Used by settings-window key, app activation, and dashboard-return callbacks. Never polls hidden/off-pane UI.
    func activate(isSettingsVisible: Bool, selectedPane: SettingsPane) async {
        guard isSettingsVisible, selectedPane == .opencodex else { return }
        await self.store.activate()
    }

    func openDashboard() async {
        self.openRequest &+= 1
        let request = self.openRequest
        let revision = self.revision
        let connection = self.connection
        self.isOpeningDashboard = true
        self.openError = nil
        do {
            let status = try await connection.source.status()
            guard self.revision == revision, self.openRequest == request else { return }
            self.isOpeningDashboard = false
            self.dashboard.open(status: status, connectionID: connection.identity) {
                try await connection.source.status()
            }
        } catch {
            guard self.revision == revision, self.openRequest == request else { return }
            self.isOpeningDashboard = false
            self.dashboard.close()
            self.openError = (error as? OpenCodexAccessError) ?? .communicationFailed
        }
    }
}

private struct MissingExecutable: OpenCodexAccessSource {
    func status() async throws -> OpenCodexAccessStatus { throw OpenCodexAccessError.executableMissing }
    func list() async throws -> OpenCodexAccessKeyList { throw OpenCodexAccessError.executableMissing }
    func create(name: String) async throws -> OpenCodexAccessCreatedKey { throw OpenCodexAccessError.executableMissing }
    func rename(id: String, name: String) async throws -> OpenCodexAccessRenamedKey {
        throw OpenCodexAccessError.executableMissing
    }

    func revoke(id: String) async throws { throw OpenCodexAccessError.executableMissing }
}

/// Renderable with memory preferences, a fake source, clipboard, and dashboard session factory.
@MainActor
struct OpenCodexAccessSettingsPane: View {
    let feature: OpenCodexAccessSettings
    @State private var path: String

    init(feature: OpenCodexAccessSettings) {
        self.feature = feature
        self._path = State(initialValue: feature.executablePath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("opencodex_settings_executable")).font(.headline)
                HStack {
                    TextField(L("opencodex_settings_default_path"), text: self.$path)
                        .disabled(!self.feature.canChangeConnection)
                    Button(L("opencodex_settings_apply_path")) {
                        guard self.feature.applyExecutablePath(self.path) else { return }
                        Task { await self.feature.store.activate() }
                    }
                    .disabled(!self.feature.canChangeConnection)
                }
                Text(L("opencodex_settings_path_hint")).font(.caption).foregroundStyle(.secondary)
                if self.feature.pathIsInvalid {
                    Text(L("opencodex_settings_invalid_path")).foregroundStyle(.orange)
                }
                if let key = self.feature.dashboardErrorKey {
                    Text(L(key)).foregroundStyle(.orange)
                    Button(L("Retry dashboard")) { Task { await self.feature.openDashboard() } }
                        .disabled(self.feature.isOpeningDashboard)
                }
                if self.feature.isOpeningDashboard { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            OpenCodexAccessPane(store: self.feature.store) {
                Task { await self.feature.openDashboard() }
            }
        }
        .onChange(of: self.feature.executablePath) { _, value in self.path = value }
    }
}

/// Outside the replaceable detail and its language identity: exactly one result presenter per settings root.
@MainActor
struct OpenCodexAccessSettingsPresenter: ViewModifier {
    let feature: OpenCodexAccessSettings?

    func body(content: Content) -> some View {
        if let feature {
            content.modifier(OpenCodexAccessDisclosurePresenter(store: feature.store, clipboard: feature.clipboard))
        } else {
            content
        }
    }
}
