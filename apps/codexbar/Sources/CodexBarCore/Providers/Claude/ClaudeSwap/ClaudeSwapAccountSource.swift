import Foundation

/// The external tool CodexBar runs to list Claude accounts.
///
/// claude-swap and tcr print claude-swap's list schema v1, so one parser and one
/// projection serve them; a source only fixes the argument array, the account
/// identity prefix and the label shown on cards. opencodex prints its own
/// account list, which `OpenCodexAccountListParser` translates into the same
/// `ClaudeSwapAccountList` before the shared projection runs.
public enum ClaudeSwapAccountSource: String, CaseIterable, Sendable {
    /// claude-swap (`cswap --list --json`), github.com/realiti4/claude-swap.
    case claudeSwap = "claude-swap"
    /// tcr (`tcr list --json`), the teamclaude-rs pooling proxy. tcr routes
    /// each request to a pooled account, so its list reports no active account
    /// and `supportsAccountSwitching: false`.
    case tcr
    /// opencodex (`ocx account list anthropic --quota --json`), github.com/lidge-jun/opencodex.
    /// On the opencodex hub the list is the pool's Anthropic OAuth accounts and
    /// `ocx account use anthropic <id>` switches the pool's active account. A Mac
    /// linked to a hub cannot read the hub's accounts: it reads the snapshot file
    /// the hub writes and asks for a switch with a request file next to it.
    case openCodex = "opencodex"

    /// The source used while none is configured: claude-swap, unless the build reads the opencodex hub by
    /// default (`OpenCodexHubDefaults.sourceEnabledByDefault`).
    public static var defaultSource: ClaudeSwapAccountSource {
        OpenCodexHubDefaults.sourceEnabledByDefault ? .openCodex : .claudeSwap
    }

    /// Identity prefix (`<source>:<slot>`) and card label.
    public var label: String {
        self.rawValue
    }

    /// The fixed list argument array. Never a shell, never config-defined arguments.
    public var listArguments: [String] {
        switch self {
        case .claudeSwap: ["--list", "--json"]
        case .tcr: ["list", "--json"]
        case .openCodex: OpenCodexAccountListParser.listArguments
        }
    }

    /// Whether the source has a switch command at all. A source that can switch
    /// still reports per list whether switching is available right now.
    public var canSwitchAccounts: Bool {
        switch self {
        case .claudeSwap, .openCodex: true
        case .tcr: false
        }
    }

    public init?(identitySource: String) {
        self.init(rawValue: identitySource)
    }
}
