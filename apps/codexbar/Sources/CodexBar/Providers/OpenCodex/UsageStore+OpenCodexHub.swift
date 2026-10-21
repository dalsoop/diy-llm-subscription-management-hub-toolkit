import CodexBarCore
import Foundation

/// What a Codex or Grok card shows while it reads an opencodex hub pool.
struct OpenCodexHubCardState: Equatable {
    var pool: OpenCodexHubPool?
    var lastError: String?
    var lastRefreshAt: Date?
    var switchStatus = OpenCodexHubSwitchStatus()
    var isSwitching = false
    /// Segmented menu layout: the hub account whose card the menu shows instead of the active one.
    var inspectedAccountID: ProviderAccountIdentity?
}

extension UsageStore {
    /// How often a card re-reads the hub while a switch request is pending (the hub writes every ~60s).
    static let openCodexHubPendingPollInterval: Duration = .seconds(20)

    /// True when the Codex or Grok card reads its accounts from the opencodex hub instead of the
    /// provider's own sources (which, behind an opencodex proxy, cannot report ChatGPT or Grok limits).
    func usesOpenCodexHub(for provider: UsageProvider) -> Bool {
        self.settings.openCodexHubEnabled(for: provider) && !self.openCodexHubNativeFallbacks.contains(provider)
    }

    /// Codex's own account bookkeeping (usage owner reconciliation, credits, the OpenAI web dashboard) only
    /// knows the native sources. While the Codex card reads the hub, that bookkeeping neither runs nor clears
    /// the hub card: the hub's snapshot has no local Codex owner, so the owner check would always discard it,
    /// and the native credits read behind an opencodex proxy only fails ("configured for a custom provider").
    var codexCardReadsOpenCodexHub: Bool {
        self.usesOpenCodexHub(for: .codex)
    }

    /// The Claude card reads the hub pool, so the opencodex account adapter (same pool) stays off. Other adapter
    /// sources (claude-swap, tcr) are separate account stores and keep running.
    var claudeCardReplacesOpenCodexAdapter: Bool {
        self.usesOpenCodexHub(for: .claude) && self.settings.claudeSwapSource == .openCodex
    }

    func dropCodexNativeCreditsForOpenCodexHub() {
        self.credits = nil
        self.lastCreditsError = nil
        self.lastCreditsSnapshot = nil
        self.lastCreditsSnapshotAccountKey = nil
        self.lastCreditsSnapshotOwnerGuard = nil
        self.lastCreditsSource = .none
        self.creditsFailureStreak = 0
    }

    func openCodexHubCardState(for provider: UsageProvider) -> OpenCodexHubCardState? {
        guard self.usesOpenCodexHub(for: provider) else { return nil }
        return self.openCodexHubCardStates[provider]
    }

    func clearOpenCodexHubCardState(_ provider: UsageProvider) {
        self.openCodexHubPollTasks[provider]?.cancel()
        self.openCodexHubPollTasks[provider] = nil
        self.openCodexHubCardStates[provider] = nil
    }

    /// One refresh pass for a hub-backed card: read the pool, resolve a pending switch and publish the
    /// active account's quota as the provider snapshot. Returns false when this Mac has no hub source (no
    /// opencodex role and no snapshot), so the caller reads the provider's own sources instead of an error.
    @discardableResult
    func refreshOpenCodexHubCard(_ provider: UsageProvider, generation: UInt64?) async -> Bool {
        guard let hubProvider = OpenCodexHubProvider(usageProvider: provider) else { return false }
        let executablePath = self.settings.openCodexHubExecutablePath(for: provider)
        let snapshotPath = self.settings.openCodexHubSnapshotPath(for: provider)
        let result: Result<OpenCodexHubPool, Error>
        do {
            result = try await .success(OpenCodexHubReader.readPool(
                provider: hubProvider,
                executablePath: executablePath,
                snapshotPath: snapshotPath))
        } catch is CancellationError {
            return true
        } catch {
            result = .failure(error)
        }
        guard self.isCurrentProviderRefreshGeneration(provider, generation: generation),
              self.settings.openCodexHubEnabled(for: provider),
              self.settings.openCodexHubExecutablePath(for: provider) == executablePath,
              self.settings.openCodexHubSnapshotPath(for: provider) == snapshotPath
        else { return true }
        if case let .failure(error) = result, case .noHubSource = error as? OpenCodexHubReaderError {
            if !self.openCodexHubNativeFallbacks.contains(provider) {
                self.openCodexHubNativeFallbacks.insert(provider)
                self.clearOpenCodexHubCardState(provider)
                self.snapshots.removeValue(forKey: provider.instanceID)
                self.errors[provider.instanceID] = nil
            }
            return false
        }
        self.openCodexHubNativeFallbacks.remove(provider)
        switch result {
        case let .success(pool):
            self.applyOpenCodexHubPool(pool, provider: provider)
        case let .failure(error):
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            var state = self.openCodexHubCardStates[provider] ?? OpenCodexHubCardState()
            state.lastError = message
            self.openCodexHubCardStates[provider] = state
            if state.pool == nil {
                self.snapshots.removeValue(forKey: provider.instanceID)
            }
            self.errors[provider.instanceID] = message
        }
        return true
    }

    func applyOpenCodexHubPool(_ pool: OpenCodexHubPool, provider: UsageProvider, now: Date = Date()) {
        var state = self.openCodexHubCardStates[provider] ?? OpenCodexHubCardState()
        state.pool = pool
        state.lastError = nil
        state.lastRefreshAt = now
        state.switchStatus.reconcile(with: pool, now: now)
        self.openCodexHubCardStates[provider] = state
        self.lastSourceLabels[provider.instanceID] = OpenCodexHubUsageProjection.sourceLabel
        if let active = pool.activeAccount {
            let snapshot = OpenCodexHubUsageProjection.snapshot(
                for: active,
                provider: pool.provider,
                fallbackUpdatedAt: pool.snapshotUpdatedAt ?? now)
            self.snapshots[provider.instanceID] = snapshot
            self.errors[provider.instanceID] = nil
            self.failureGates[provider.instanceID]?.recordSuccess()
        } else {
            self.snapshots.removeValue(forKey: provider.instanceID)
            self.errors[provider.instanceID] = L("No active account")
        }
        if !state.switchStatus.isPending {
            self.openCodexHubPollTasks[provider]?.cancel()
            self.openCodexHubPollTasks[provider] = nil
        }
    }

    /// Switches a hub-backed card to `account`: on the hub through `ocx`, elsewhere by a request file.
    func switchOpenCodexHubAccount(
        _ account: OpenCodexHubAccount,
        provider: UsageProvider,
        label: String,
        progressDidChange: (@MainActor () -> Void)? = nil)
    {
        guard let hubProvider = OpenCodexHubProvider(usageProvider: provider),
              var state = self.openCodexHubCardState(for: provider),
              !state.isSwitching, !state.switchStatus.isPending,
              let pool = state.pool, pool.canSwitch(to: account),
              let idSuffix = account.idSuffix
        else { return }
        let executablePath = self.settings.openCodexHubExecutablePath(for: provider)
        let snapshotPath = self.settings.openCodexHubSnapshotPath(for: provider)
        state.isSwitching = true
        self.openCodexHubCardStates[provider] = state
        progressDidChange?()
        Task { @MainActor [weak self] in
            let outcome: Result<OpenCodexHubSwitchOutcome, Error>
            do {
                outcome = try await .success(OpenCodexHubReader.switchAccount(
                    provider: hubProvider,
                    idSuffix: idSuffix,
                    email: account.email,
                    executablePath: executablePath,
                    snapshotPath: snapshotPath))
            } catch {
                outcome = .failure(error)
            }
            guard let self, var state = self.openCodexHubCardStates[provider] else { return }
            state.isSwitching = false
            switch outcome {
            case .success(.switched), .success(.alreadyActive):
                state.switchStatus.finish(.switched(label), activeAccount: .init(account))
            case let .success(.requested(request)):
                state.switchStatus.begin(request, label: label)
            case let .failure(error):
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                let active = state.pool?.activeAccount.map(OpenCodexHubSwitchStatus.AccountKey.init)
                state.switchStatus.finish(.failed(message), activeAccount: active)
            }
            self.openCodexHubCardStates[provider] = state
            progressDidChange?()
            if state.switchStatus.isPending {
                self.startOpenCodexHubPendingPoll(provider)
            } else {
                await self.refreshProvider(provider)
            }
        }
    }

    /// Re-reads the hub until the pending request resolves (the snapshot reports it or it expires).
    private func startOpenCodexHubPendingPoll(_ provider: UsageProvider) {
        self.openCodexHubPollTasks[provider]?.cancel()
        self.openCodexHubPollTasks[provider] = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.openCodexHubPendingPollInterval)
                guard !Task.isCancelled, let self,
                      self.openCodexHubCardState(for: provider)?.switchStatus.isPending == true
                else { return }
                await self.refreshProvider(provider)
            }
        }
    }
}
