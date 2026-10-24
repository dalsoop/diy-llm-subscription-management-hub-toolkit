import CodexBarCore
import SwiftUI

@MainActor
public struct OpenCodexAccessPane: View {
    private let store: OpenCodexAccessStore
    private let openDashboard: @MainActor () -> Void
    @State private var newName = ""
    @State private var renameID: String?
    @State private var renameName = ""

    public init(store: OpenCodexAccessStore, openDashboard: @escaping @MainActor () -> Void) {
        self.store = store
        self.openDashboard = openDashboard
    }

    public var body: some View {
        Form {
            Section {
                HStack {
                    Button(L("opencodex_access_refresh")) { Task { await self.store.refresh() } }
                        .disabled(self.store.isMutating)
                    Button(L("opencodex_access_dashboard"), action: self.openDashboard)
                        .disabled(self.store.status?.runtimeRole.ownsAccounts != true)
                    if self.store.isRefreshing { ProgressView().controlSize(.small) }
                }
                if self.store.isMutating { Text(L("opencodex_access_mutating")) }
                if let error = self.store.refreshError {
                    Text(L("opencodex_access_refresh_failed")).foregroundStyle(.orange)
                    Text(L(error.accessLocalizationKey))
                } else if self.store.snapshot == nil {
                    Text(L("opencodex_access_loading"))
                }
                self.outcome
            } header: { Text(L("opencodex_access_title")) }

            Section {
                TextField(L("opencodex_access_name"), text: self.$newName)
                Button(L("opencodex_access_create")) {
                    if self.store.create(name: self.newName) { self.newName = "" }
                }
                .disabled(!self.store.canMutate)
                if let error = self.store.inputError { Text(L(error.accessLocalizationKey)).foregroundStyle(.orange) }
            }

            if let list = self.store.snapshot {
                Section {
                    if list.keys.isEmpty { Text(L("opencodex_access_empty")) }
                    if list.usageIncomplete { Text(L("opencodex_access_usage_incomplete")) }
                    if list.historyTruncated { Text(L("opencodex_access_history_truncated")) }
                    if let since = list.attributionSince {
                        LabeledContent(L("opencodex_access_attribution_since")) { Text(
                            since,
                            format: .dateTime.year().month().day().hour().minute().second()) }
                    }
                    if let key = self.store.renameCapability
                        .localizationKey { Text(L(key)).foregroundStyle(.secondary) }
                    ForEach(list.keys) { key in self.row(key, list: list) }
                } footer: { Text(L("opencodex_access_advanced_hint")) }
            }
        }
        .formStyle(.grouped)
        .task { await self.store.enter() }
        .onDisappear { self.store.leave() }
        .confirmationDialog(
            L("opencodex_access_revoke_title"),
            isPresented: Binding(
                get: { self.store.revokeConfirmation != nil },
                set: { if !$0 { self.store.cancelRevoke() } }),
            titleVisibility: .visible)
        {
            Button(L("opencodex_access_revoke"), role: .destructive) { self.store.confirmRevoke() }
            Button(L("opencodex_access_cancel"), role: .cancel) { self.store.cancelRevoke() }
        } message: {
            if let key = self.store.revokeConfirmation {
                Text(L("opencodex_access_revoke_warning", key.name, key.prefix))
            }
        }
    }

    @ViewBuilder
    private var outcome: some View {
        switch self.store.mutationOutcome {
        case .succeeded(.create): Text(L("opencodex_access_create_succeeded"))
        case .succeeded(.rename): Text(L("opencodex_access_rename_succeeded"))
        case .succeeded(.revoke): Text(L("opencodex_access_revoke_succeeded"))
        case let .failed(error):
            Text(L(error.accessLocalizationKey)).foregroundStyle(.orange)
            if error == .confirmationRequired { Text(L("opencodex_access_confirmation_hint")) }
        case nil: EmptyView()
        }
    }

    private func row(_ key: OpenCodexAccessKey, list: OpenCodexAccessKeyList) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(key.name).font(.headline)
            Text(verbatim: key.prefix + "…").font(.system(.body, design: .monospaced))
            if list.keys.filter({ $0.name == key.name }).count > 1 { Text(L("opencodex_access_duplicate_name")) }
            LabeledContent(L("opencodex_access_created_at")) { Text(
                key.createdAt,
                format: .dateTime.year().month().day().hour().minute().second()) }
            LabeledContent(L("opencodex_access_providers"), value: self.scopeText(key.allowedProviders))
            LabeledContent(L("opencodex_access_models"), value: self.scopeText(key.allowedModels))
            self.usage(key, list: list)
            HStack {
                Button(L("opencodex_access_rename")) { self.renameID = key.id; self.renameName = key.name }
                    .disabled(!self.store.canRename)
                Button(L("opencodex_access_revoke"), role: .destructive) { self.store.requestRevoke(id: key.id) }
                    .disabled(!self.store.canMutate)
            }
            if self.renameID == key.id {
                TextField(L("opencodex_access_name"), text: self.$renameName)
                HStack {
                    Button(L("opencodex_access_save_name")) {
                        if self.store.rename(id: key.id, name: self.renameName) { self.renameID = nil }
                    }
                    .disabled(!self.store.canRename)
                    Button(L("opencodex_access_cancel")) { self.renameID = nil }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func scopeText(_ values: [String]?) -> String {
        guard let values else { return L("opencodex_access_metadata_unavailable") }
        return values.isEmpty ? L("opencodex_access_scope_empty") : values.joined(separator: ", ")
    }

    @ViewBuilder
    private func usage(_ key: OpenCodexAccessKey, list: OpenCodexAccessKeyList) -> some View {
        switch OpenCodexAccessUsagePresentation(key: key, list: list) {
        case .unavailable: Text(L("opencodex_access_usage_unavailable"))
        case .noRecordedUsage: Text(L("opencodex_access_no_usage"))
        case let .recorded(week, total, last):
            LabeledContent(L("opencodex_access_requests_7d"), value: self.number(week))
            LabeledContent(L("opencodex_access_requests_total"), value: self.number(total))
            if let last {
                LabeledContent(L("opencodex_access_last_used")) { Text(
                    last,
                    format: .dateTime.year().month().day().hour().minute().second()) }
            }
        }
    }

    private func number(_ value: Double?) -> String {
        value?.formatted() ?? L("opencodex_access_usage_unavailable")
    }
}
