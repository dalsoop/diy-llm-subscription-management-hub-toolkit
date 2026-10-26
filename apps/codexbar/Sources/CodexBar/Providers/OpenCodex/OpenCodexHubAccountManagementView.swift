import CodexBarCore
import SwiftUI

struct OpenCodexHubAccountManagementView: View {
    let provider: UsageProvider
    let store: UsageStore
    let openAccounts: @MainActor () async -> Void
    @State private var managementOriginDraft = ""

    var body: some View {
        let state = self.store.openCodexHubManagementState(for: self.provider)
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Hub accounts")).font(.headline)
            Text(L("Open the account manager in your browser, then add an account or sign in again. " +
                    "Your sign-in stays on the hub."))
                .font(.callout)
            // Provider-specific by design: the hub offers device-code sign-in only for Codex accounts.
            if self.provider == .codex {
                Text(L("For sign-in from another Mac, the account manager also offers device-code sign-in."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text(L("Hub HTTPS management address")).font(.callout)
            HStack {
                TextField(L("https://your-hub.example"), text: self.$managementOriginDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { self.saveManagementOrigin() }
                Button(L("Save address")) { self.saveManagementOrigin() }
                    .disabled(!self.validManagementOriginDraft)
            }
            Text(L("Use the hub's management address, not 127.0.0.1 or its data API address. " +
                    "For a Tailscale address, this Mac must be connected to the same tailnet."))
                .font(.caption).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack { self.actionButtons }
                VStack(alignment: .leading) { self.actionButtons }
            }
            .disabled(state?.isBusy == true)
            if let state {
                Text(state.message).font(.callout)
                    .foregroundStyle(state.needsAttention ? Color.orange : Color.secondary)
                    .accessibilityIdentifier("hubAccountManagementStatus")
            }
            if let pool = self.store.openCodexHubCardState(for: self.provider)?.pool {
                Text(OpenCodexHubPresentation.listStatus(pool)).font(.callout).foregroundStyle(.secondary)
                if pool.accounts.isEmpty {
                    Text(L("No accounts found. Add an account in your browser, then refresh this list."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(pool.accounts.indices, id: \.self) { index in
                    let account = pool.accounts[index]
                    HStack(alignment: .top) {
                        Text(OpenCodexHubPresentation.menuTitle(
                            for: account,
                            label: OpenCodexHubPresentation.label(
                                for: account,
                                hidePersonalInfo: self.store.settings.hidePersonalInfo,
                                ordinal: index + 1)))
                        Spacer(minLength: 8)
                        if account.isActive { Text(L("Active")).foregroundStyle(.secondary) }
                    }
                    .font(.callout)
                }
            } else {
                Text(L("Account list not loaded. Choose Refresh accounts to check it."))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 8)
        .onAppear {
            self.managementOriginDraft = self.store.settings.openCodexHubManagementOrigin(for: self.provider)
        }
    }

    private var validManagementOriginDraft: Bool {
        let address = self.managementOriginDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return address.isEmpty || OpenCodexHubManagement.isRemoteManagementOrigin(address)
    }

    private func saveManagementOrigin() {
        if self.store.settings.setOpenCodexHubManagementOrigin(self.managementOriginDraft, for: self.provider) {
            self.managementOriginDraft = self.store.settings.openCodexHubManagementOrigin(for: self.provider)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button(L("Add account or sign in again...")) {
            Task { @MainActor in await self.openAccounts() }
        }
        .fixedSize()
        Button(L("Refresh accounts")) {
            Task { @MainActor in await self.store.refreshHubAccountList(self.provider) }
        }
        .fixedSize()
        if self.store.openCodexHubManagementState(for: self.provider)?.isBusy == true {
            ProgressView().controlSize(.small)
        }
    }
}
