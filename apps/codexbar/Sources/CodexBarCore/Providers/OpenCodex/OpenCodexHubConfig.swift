import Foundation

/// Defaults for the opencodex hub source. Upstream builds leave the source off and the snapshot path
/// unset, so nothing is read until a user configures it; a redistribution that ships for one hub layout
/// can change these defaults in one place.
///
/// This build reads them from the app's Info.plist, which `Scripts/package_app.sh` fills for the fleet
/// (`CODEXBAR_OPENCODEX_HUB_SNAPSHOT_PATH`, `CODEXBAR_OPENCODEX_HUB_NAME`): the hub writes its snapshot to
/// every Mac, so the packaged app reads the hub without manual settings. Builds without those keys (tests,
/// `swift run`) keep the upstream defaults.
public enum OpenCodexHubDefaults {
    static let snapshotPathKey = "CodexBarOpenCodexHubSnapshotPath"
    static let hubNameKey = "CodexBarOpenCodexHubName"

    /// Whether the Claude, Codex and Grok cards read the opencodex hub when the user has not chosen.
    public static let sourceEnabledByDefault = Self.snapshotPath != nil
    /// The hub snapshot file read when no path is configured.
    public static let snapshotPath: String? = Self.infoString(Self.snapshotPathKey)
    /// The managing machine's name when the snapshot does not carry one.
    public static let hubName: String? = Self.infoString(Self.hubNameKey)

    private static func infoString(_ key: String) -> String? {
        SettingsValue.cleaned(Bundle.main.object(forInfoDictionaryKey: key) as? String)
    }
}

extension ProviderConfig {
    /// Codex and Grok: whether the card reads accounts from the opencodex hub instead of the provider's own
    /// sources. (Claude uses the account adapter with `claudeSwapSource = "opencodex"`.)
    public var openCodexHubEnabled: Bool? {
        get { self.extensionValue(forKey: "openCodexHubEnabled") }
        set { self.setExtensionValue(newValue, forKey: "openCodexHubEnabled") }
    }

    /// Codex and Grok: the `ocx` executable used on the hub. Empty means the usual install locations.
    public var openCodexHubExecutablePath: String? {
        get { self.extensionValue(forKey: "openCodexHubExecutablePath") }
        set { self.setExtensionValue(newValue, forKey: "openCodexHubExecutablePath") }
    }

    public var sanitizedOpenCodexHubExecutablePath: String? {
        SettingsValue.cleaned(self.openCodexHubExecutablePath)
    }

    /// The hub snapshot file a Mac that is not the hub reads (and next to which it writes switch requests).
    public var openCodexHubSnapshotPath: String? {
        get { self.extensionValue(forKey: "openCodexHubSnapshotPath") }
        set { self.setExtensionValue(newValue, forKey: "openCodexHubSnapshotPath") }
    }

    public var sanitizedOpenCodexHubSnapshotPath: String? {
        SettingsValue.cleaned(self.openCodexHubSnapshotPath)
    }

    /// The configured snapshot path, or the default one.
    public var resolvedOpenCodexHubSnapshotPath: String? {
        self.sanitizedOpenCodexHubSnapshotPath ?? OpenCodexHubDefaults.snapshotPath
    }

    public var resolvedOpenCodexHubEnabled: Bool {
        self.openCodexHubEnabled ?? OpenCodexHubDefaults.sourceEnabledByDefault
    }
}
