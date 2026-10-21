import CodexBarCore
import Foundation

/// The "opencodex hub accounts" toggle of the Codex and Grok settings panes.
enum OpenCodexHubSettingsDescriptors {
    @MainActor
    static func toggle(
        provider: UsageProvider,
        enabled: ReferenceWritableKeyPath<SettingsStore, Bool>,
        executablePath: ReferenceWritableKeyPath<SettingsStore, String>,
        snapshotPath: ReferenceWritableKeyPath<SettingsStore, String>,
        context: ProviderSettingsContext) -> ProviderSettingsToggleDescriptor
    {
        let executableField = ProviderSettingsFieldDescriptor(
            id: "\(provider.rawValue)-opencodex-executable-path",
            title: "opencodex executable",
            subtitle: "Optional. Path to the ocx executable on the hub; empty looks in the usual install locations.",
            kind: .plain,
            placeholder: "/opt/homebrew/bin/ocx",
            binding: context.binding(executablePath),
            actions: [],
            isVisible: nil)
        let snapshotField = ProviderSettingsFieldDescriptor(
            id: "\(provider.rawValue)-opencodex-snapshot-path",
            title: "Hub snapshot file",
            subtitle: "On a Mac that is not the hub, read the hub's accounts from this snapshot file; " +
                "switch requests are written next to it.",
            kind: .plain,
            placeholder: "~/.swift-app-state/opencodex-hub-accounts.json",
            binding: context.binding(snapshotPath),
            actions: [],
            isVisible: nil)
        return ProviderSettingsToggleDescriptor(
            id: "\(provider.rawValue)-opencodex-hub-accounts",
            title: "Read accounts from an opencodex hub",
            subtitle: "Shows this provider's accounts and limits from an opencodex hub instead of its own sources. " +
                "On the hub CodexBar switches accounts through `ocx`; other Macs read the hub's snapshot file and " +
                "ask the hub to switch. Credentials stay on the hub; CodexBar never reads them.",
            binding: context.binding(enabled),
            statusText: { Self.statusText(provider: provider, store: context.store) },
            actions: [],
            inlineFields: [executableField, snapshotField],
            isVisible: nil,
            isEnabled: nil,
            onChange: { _ in await context.store.refreshProvider(provider) },
            onAppDidBecomeActive: nil,
            onAppearWhenEnabled: nil)
    }

    @MainActor
    private static func statusText(provider: UsageProvider, store: UsageStore) -> String? {
        guard let state = store.openCodexHubCardState(for: provider) else { return nil }
        if let error = state.lastError { return error }
        guard let pool = state.pool, let refreshedAt = state.lastRefreshAt else { return nil }
        let accounts = pool.accounts.count == 1 ? "1 account" : "\(pool.accounts.count) accounts"
        var parts = ["\(accounts), updated \(refreshedAt.relativeDescription())"]
        if !pool.isHubLocal {
            let hub = pool.hubName ?? OpenCodexHubDefaults.hubName ?? "the hub"
            parts.append(pool.switchable ? "copy from \(hub), switches by request" : "read-only copy from \(hub)")
        }
        return parts.joined(separator: " — ")
    }
}
