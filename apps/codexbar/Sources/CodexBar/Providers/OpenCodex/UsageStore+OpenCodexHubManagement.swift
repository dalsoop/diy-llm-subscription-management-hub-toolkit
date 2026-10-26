import CodexBarCore
import Foundation

/// A browser handoff, never evidence that OAuth succeeded. Kept only for this app session.
struct OpenCodexHubManagementState: Equatable {
    enum Phase: Equatable {
        case opening
        case awaitingReturn
        case checking
        case checked
        case waitingForSync
        case failed(String)
    }

    let id = UUID()
    let executablePath: String
    let snapshotPath: String
    let configRevision: UInt64
    var phase: Phase

    var isBusy: Bool {
        self.phase == .opening || self.phase == .checking
    }

    var needsAttention: Bool {
        switch self.phase {
        case .waitingForSync, .failed: true
        default: false
        }
    }

    var message: String {
        switch self.phase {
        case .opening: L("Opening account sign-in in your browser…")
        case .awaitingReturn: L("Finish signing in in your browser. Return here to check the account list.")
        case .checking: L("Checking the account list…")
        case .checked:
            L("Account list checked. Confirm that your account appears; " +
                "opening the browser does not complete sign-in.")
        case .waitingForSync:
            L("This Mac still has a read-only or outdated account list. " +
                "A new sign-in may not appear until hub sync resumes.")
        case let .failed(message): message
        }
    }

    var menuMessage: String {
        switch self.phase {
        case .opening, .checking: self.message
        case .awaitingReturn: L("Finish sign-in in your browser, then refresh accounts.")
        case .checked: L("Account list checked. Verify your account is listed.")
        case .waitingForSync: L("Account list is not current. Check hub sync.")
        case .failed: L("Account management needs attention. Open Settings.")
        }
    }
}

extension UsageStore {
    func openCodexHubManagementState(for provider: UsageProvider) -> OpenCodexHubManagementState? {
        guard self.settings.openCodexHubEnabled(for: provider),
              let state = self.openCodexHubManagementStates[provider],
              state.configRevision == self.settings.providerConfigRevision(for: provider),
              state.executablePath == self.settings.openCodexHubExecutablePath(for: provider),
              state.snapshotPath == self.settings.openCodexHubSnapshotPath(for: provider)
        else { return nil }
        return state
    }

    @discardableResult
    func openHubAccountManagement(
        _ provider: UsageProvider,
        resolveURL: (@MainActor (String?, OpenCodexHubProvider) async throws -> URL)? = nil,
        openURL: @MainActor (URL) -> Bool) async -> String?
    {
        guard self.settings.openCodexHubEnabled(for: provider),
              let hubProvider = OpenCodexHubProvider(usageProvider: provider),
              self.openCodexHubManagementState(for: provider)?.isBusy != true
        else { return nil }
        var state = self.newHubManagementState(provider, phase: .opening)
        self.openCodexHubManagementStates[provider] = state
        do {
            let url: URL = if let resolveURL {
                try await resolveURL(state.executablePath, hubProvider)
            } else {
                try await OpenCodexHubManagement.accountsURL(
                    executablePath: state.executablePath,
                    provider: hubProvider,
                    managementOrigin: self.settings.openCodexHubManagementOrigin(for: provider))
            }
            guard self.openCodexHubManagementState(for: provider)?.id == state.id else { return nil }
            guard !Task.isCancelled else {
                self.openCodexHubManagementStates[provider] = nil
                return nil
            }
            guard openURL(url) else {
                throw OpenCodexHubBrowserError.openFailed
            }
            state.phase = .awaitingReturn
        } catch {
            guard self.openCodexHubManagementState(for: provider)?.id == state.id else { return nil }
            guard !Task.isCancelled, !(error is CancellationError) else {
                self.openCodexHubManagementStates[provider] = nil
                return nil
            }
            let message: String = if error is OpenCodexHubManagementError {
                L("Set the hub's HTTPS management address in Settings. " +
                    "The local data tunnel cannot open the account manager.")
            } else if error is OpenCodexHubBrowserError {
                L("Could not open your browser. Try opening the account manager again.")
            } else {
                L("Could not reach the account manager. Check the hub connection and try again.")
            }
            state.phase = .failed(message)
            self.openCodexHubManagementStates[provider] = state
            return message
        }
        self.openCodexHubManagementStates[provider] = state
        return nil
    }

    /// One read on a user's return, with no OAuth polling, automatic retry or guessed login success.
    func checkHubAccountsAfterBrowserReturn() {
        for provider in SettingsStore.openCodexHubCardProviders
            where self.openCodexHubManagementState(for: provider)?.phase == .awaitingReturn
        {
            let handoffID = self.openCodexHubManagementState(for: provider)?.id
            Task { @MainActor [weak self] in
                guard let self, self.openCodexHubManagementState(for: provider)?.id == handoffID,
                      self.openCodexHubManagementState(for: provider)?.phase == .awaitingReturn
                else { return }
                await self.refreshHubAccountList(provider)
            }
        }
    }

    func refreshHubAccountList(_ provider: UsageProvider) async {
        guard self.settings.openCodexHubEnabled(for: provider),
              self.openCodexHubManagementState(for: provider)?.isBusy != true
        else { return }
        var state = self.newHubManagementState(provider, phase: .checking)
        let previousReadAt = self.openCodexHubCardState(for: provider)?.lastRefreshAt
        self.openCodexHubManagementStates[provider] = state
        await self.refreshProvider(provider, allowDisabled: true, hubAccountsOnly: true)
        guard self.openCodexHubManagementState(for: provider)?.id == state.id else { return }
        if let card = self.openCodexHubCardState(for: provider), card.lastError == nil,
           card.lastRefreshAt != previousReadAt, let pool = card.pool
        {
            state.phase = pool.isStale() ? .waitingForSync : .checked
        } else {
            state.phase = .failed(L("Could not refresh the account list. " +
                    "Your browser sign-in may still have succeeded. Try refreshing again."))
        }
        self.openCodexHubManagementStates[provider] = state
    }

    private func newHubManagementState(
        _ provider: UsageProvider,
        phase: OpenCodexHubManagementState.Phase) -> OpenCodexHubManagementState
    {
        OpenCodexHubManagementState(
            executablePath: self.settings.openCodexHubExecutablePath(for: provider),
            snapshotPath: self.settings.openCodexHubSnapshotPath(for: provider),
            configRevision: self.settings.providerConfigRevision(for: provider),
            phase: phase)
    }
}

private enum OpenCodexHubBrowserError: Error {
    case openFailed
}
