import CodexBarCore
import Foundation

/// opencodex hub settings for the Claude, Codex and Grok cards. A Claude card that reads the hub replaces the
/// opencodex account adapter (`claudeSwapSource == .openCodex`), which stays for Macs without a hub source.
extension SettingsStore {
    /// The providers whose card can read an opencodex hub pool through these settings. The hub pool is what the
    /// hub routes to; the provider's own sources behind an opencodex proxy read another login or none.
    static let openCodexHubCardProviders: [UsageProvider] = [.claude, .codex, .grok]

    func openCodexHubEnabled(for provider: UsageProvider) -> Bool {
        guard Self.openCodexHubCardProviders.contains(provider) else { return false }
        return self.configSnapshot.providerConfig(for: provider.instanceID)?.resolvedOpenCodexHubEnabled
            ?? OpenCodexHubDefaults.sourceEnabledByDefault
    }

    func setOpenCodexHubEnabled(_ enabled: Bool, for provider: UsageProvider) {
        guard Self.openCodexHubCardProviders.contains(provider) else { return }
        self.updateProviderConfig(provider: provider) { entry in
            entry.openCodexHubEnabled = enabled == OpenCodexHubDefaults.sourceEnabledByDefault ? nil : enabled
        }
        self.logProviderModeChange(provider: provider, field: "openCodexHubEnabled", value: String(enabled))
    }

    func openCodexHubExecutablePath(for provider: UsageProvider) -> String {
        self.configSnapshot.providerConfig(for: provider.instanceID)?.sanitizedOpenCodexHubExecutablePath ?? ""
    }

    func setOpenCodexHubExecutablePath(_ path: String, for provider: UsageProvider) {
        self.updateProviderConfig(provider: provider) { entry in
            entry.openCodexHubExecutablePath = self.normalizedConfigValue(path)
        }
        self.logProviderModeChange(
            provider: provider,
            field: "openCodexHubExecutablePath",
            value: path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "cleared" : "set")
    }

    /// The configured snapshot path, or the build's default one (empty when neither exists).
    func openCodexHubSnapshotPath(for provider: UsageProvider) -> String {
        self.configSnapshot.providerConfig(for: provider.instanceID)?.sanitizedOpenCodexHubSnapshotPath
            ?? OpenCodexHubDefaults.snapshotPath ?? ""
    }

    func setOpenCodexHubSnapshotPath(_ path: String, for provider: UsageProvider) {
        self.updateProviderConfig(provider: provider) { entry in
            entry.openCodexHubSnapshotPath = self.normalizedConfigValue(path)
        }
        self.logProviderModeChange(
            provider: provider,
            field: "openCodexHubSnapshotPath",
            value: path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "cleared" : "set")
    }

    var codexOpenCodexHubEnabled: Bool {
        get { self.openCodexHubEnabled(for: .codex) }
        set { self.setOpenCodexHubEnabled(newValue, for: .codex) }
    }

    var codexOpenCodexHubExecutablePath: String {
        get { self.openCodexHubExecutablePath(for: .codex) }
        set { self.setOpenCodexHubExecutablePath(newValue, for: .codex) }
    }

    var codexOpenCodexHubSnapshotPath: String {
        get { self.openCodexHubSnapshotPath(for: .codex) }
        set { self.setOpenCodexHubSnapshotPath(newValue, for: .codex) }
    }

    var grokOpenCodexHubEnabled: Bool {
        get { self.openCodexHubEnabled(for: .grok) }
        set { self.setOpenCodexHubEnabled(newValue, for: .grok) }
    }

    var grokOpenCodexHubExecutablePath: String {
        get { self.openCodexHubExecutablePath(for: .grok) }
        set { self.setOpenCodexHubExecutablePath(newValue, for: .grok) }
    }

    var grokOpenCodexHubSnapshotPath: String {
        get { self.openCodexHubSnapshotPath(for: .grok) }
        set { self.setOpenCodexHubSnapshotPath(newValue, for: .grok) }
    }
}
