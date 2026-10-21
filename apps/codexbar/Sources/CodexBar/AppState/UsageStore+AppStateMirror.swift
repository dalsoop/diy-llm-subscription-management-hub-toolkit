import CodexBarCore
import Foundation

/// Bookkeeping for the agent-readable state mirror (`CodexBarAppStateMirror`).
struct AppStateMirrorRecorder {
    /// When each provider's last refresh pass finished, successful or not.
    var refreshFinishedAt: [ProviderInstanceID: Date] = [:]
    var lastWrittenState: CodexBarAppStateMirror.State?
    var lastWrittenAt: Date?
    /// Tests point the mirror here; the app writes `CodexBarAppStateMirror.fileURLs()`.
    var fileURLOverride: URL?

    /// An unchanged state is rewritten at most once a minute so `updatedAt` still shows the app is alive.
    static let unchangedRewriteInterval: TimeInterval = 60
}

extension UsageStore {
    /// Records the end of a provider refresh pass and republishes the mirror.
    func noteAppStateRefreshFinished(_ provider: UsageProvider, now: Date = Date()) {
        self.appStateMirrorRecorder.refreshFinishedAt[provider.instanceID] = now
        self.publishAppStateMirror(now: now)
    }

    /// Writes `.swift-app-state/codexbar.json` under the fleet state root (and the home copy when that root is a
    /// tenant root) when the state changed or a minute passed. Test processes write only to an injected URL.
    func publishAppStateMirror(now: Date = Date()) {
        let urls: [URL]
        if let override = self.appStateMirrorRecorder.fileURLOverride {
            urls = [override]
        } else {
            guard !SettingsStore.isRunningTests else { return }
            urls = CodexBarAppStateMirror.fileURLs()
        }
        let state = self.appStateMirrorState(now: now)
        if state == self.appStateMirrorRecorder.lastWrittenState,
           let writtenAt = self.appStateMirrorRecorder.lastWrittenAt,
           now.timeIntervalSince(writtenAt) < AppStateMirrorRecorder.unchangedRewriteInterval
        {
            return
        }
        // The mirror is observability only; a failed write must not disturb the menu.
        let written = urls.filter { (try? CodexBarAppStateMirror.write(state, to: $0, now: now)) != nil }
        if !written.isEmpty {
            self.appStateMirrorRecorder.lastWrittenState = state
            self.appStateMirrorRecorder.lastWrittenAt = now
        }
    }

    func appStateMirrorState(now: Date = Date(), bundle: Bundle = .main) -> CodexBarAppStateMirror.State {
        let info = bundle.infoDictionary ?? [:]
        let enabled = Set(self.enabledProviders())
        var providers: [CodexBarAppStateMirror.Provider] = []
        var hubRoles: [String] = []
        for instanceID in self.enabledProvidersForDisplay() {
            guard let provider = UsageProvider(rawValue: instanceID.rawValue) else { continue }
            let entry = self.appStateMirrorProvider(
                provider,
                instanceID: instanceID,
                enabled: enabled.contains(instanceID),
                now: now)
            providers.append(entry.provider)
            if let role = entry.hubRole { hubRoles.append(role) }
        }
        return CodexBarAppStateMirror.State(
            appVersion: info["CFBundleShortVersionString"] as? String,
            appBuild: info["CFBundleVersion"] as? String,
            bundleID: bundle.bundleIdentifier,
            gitCommit: info["CodexGitCommit"] as? String,
            multiAccountMenuLayout: self.settings.multiAccountMenuLayout.rawValue,
            hubRole: Self.appStateHubRole(hubRoles),
            providers: providers)
    }

    private func appStateMirrorProvider(
        _ provider: UsageProvider,
        instanceID: ProviderInstanceID,
        enabled: Bool,
        now: Date) -> (provider: CodexBarAppStateMirror.Provider, hubRole: String?)
    {
        let snapshot = self.snapshots[instanceID]
        var source = self.lastSourceLabels[instanceID]
        var error = self.errors[instanceID]
        var lastRefreshAt = self.appStateMirrorRecorder.refreshFinishedAt[instanceID]
        var accountSource: String?
        var accountError: String?
        var stale = false
        var accounts: [CodexBarAppStateMirror.Account] = []
        var hubRole: String?

        if self.usesOpenCodexHub(for: provider) {
            source = "opencodex-hub"
            accountSource = "opencodex-hub"
            let card = self.openCodexHubCardStates[provider]
            if let pool = card?.pool {
                accounts = pool.accounts.map(Self.appStateAccount)
                stale = pool.isStale(now: now)
                hubRole = Self.appStateHubRole(pool)
            }
            if error == nil { error = card?.lastError }
            lastRefreshAt = Self.latest(lastRefreshAt, card?.lastRefreshAt)
        } else if provider == .claude, self.settings.claudeSwapEnabled {
            accountSource = self.settings.claudeSwapSource.rawValue
            accountError = self.claudeSwapLastError
            accounts = self.claudeSwapAccountSnapshots.map { account in
                CodexBarAppStateMirror.Account(
                    label: account.accountEmail ?? account.displayLabel,
                    active: account.isActive,
                    windows: Self.appStateWindows(account.snapshot),
                    error: account.error)
            }
            if let pool = self.claudeSwapRemoteCopy?.pool {
                stale = pool.isStale(now: now)
                hubRole = Self.appStateHubRole(pool)
            } else if self.settings.claudeSwapSource == .openCodex, !accounts.isEmpty {
                hubRole = "hub"
            }
            lastRefreshAt = Self.latest(lastRefreshAt, self.claudeSwapLastRefreshAt)
        } else if provider == .codex, !self.codexAccountSnapshots.isEmpty {
            accountSource = "codex-accounts"
            accounts = self.codexAccountSnapshots.map { account in
                CodexBarAppStateMirror.Account(
                    label: account.account.email,
                    active: account.account.isActive,
                    windows: Self.appStateWindows(account.snapshot),
                    error: account.error)
            }
        }

        let entry = CodexBarAppStateMirror.Provider(
            id: instanceID.rawValue,
            enabled: enabled,
            source: source,
            lastRefreshAt: lastRefreshAt,
            lastSuccessAt: snapshot?.updatedAt,
            error: error,
            accountSource: accountSource,
            accountError: accountError,
            stale: stale,
            windows: Self.appStateWindows(snapshot),
            accounts: accounts)
        return (entry, hubRole)
    }

    static func appStateAccount(_ account: OpenCodexHubAccount) -> CodexBarAppStateMirror.Account {
        var windows: [CodexBarAppStateMirror.Window] = []
        if let window = account.quota.fiveHour {
            windows.append(.init(name: "5h", usedPercent: window.usedPercent, resetAt: window.resetsAt))
        }
        if let window = account.quota.weekly {
            windows.append(.init(name: "weekly", usedPercent: window.usedPercent, resetAt: window.resetsAt))
        }
        if let window = account.quota.monthly {
            windows.append(.init(name: "monthly", usedPercent: window.usedPercent, resetAt: window.resetsAt))
        }
        for window in account.quota.custom {
            windows.append(.init(name: window.label, usedPercent: window.usedPercent, resetAt: window.resetsAt))
        }
        var problem: String?
        if account.requiresReauthentication {
            problem = "needs re-authentication"
        } else if account.quotaUnavailable {
            problem = "quota unavailable"
        }
        return CodexBarAppStateMirror.Account(
            label: account.displayAlias.map { "\($0) (\(account.email))" } ?? account.email,
            active: account.isActive,
            windows: windows,
            error: problem)
    }

    static func appStateWindows(_ snapshot: UsageSnapshot?) -> [CodexBarAppStateMirror.Window] {
        guard let snapshot else { return [] }
        var windows: [CodexBarAppStateMirror.Window] = []
        let slots: [(String, RateWindow?)] = [
            ("primary", snapshot.primary),
            ("secondary", snapshot.secondary),
            ("tertiary", snapshot.tertiary),
        ]
        for (slot, window) in slots {
            guard let window, !window.isSyntheticPlaceholder else { continue }
            windows.append(.init(
                name: Self.appStateWindowName(minutes: window.windowMinutes) ?? slot,
                usedPercent: window.usedPercent,
                resetAt: window.resetsAt))
        }
        for named in snapshot.extraRateWindows ?? [] where !named.window.isSyntheticPlaceholder {
            windows.append(.init(
                name: named.title,
                usedPercent: named.window.usedPercent,
                resetAt: named.window.resetsAt))
        }
        return windows
    }

    static func appStateWindowName(minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        if minutes % 1440 == 0 { return "\(minutes / 1440)d" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }

    static func appStateHubRole(_ pool: OpenCodexHubPool) -> String {
        switch pool.origin {
        case .hubLocal: "hub"
        case .snapshot: "client"
        case .linkedCopy: "client-local-copy"
        }
    }

    /// One role for the app: a hub-local pool wins, then a snapshot, then a local copy.
    static func appStateHubRole(_ roles: [String]) -> String? {
        for role in ["hub", "client", "client-local-copy"] where roles.contains(role) {
            return role
        }
        return nil
    }

    private static func latest(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?): max(lhs, rhs)
        case let (lhs?, nil): lhs
        case let (nil, rhs?): rhs
        case (nil, nil): nil
        }
    }
}
