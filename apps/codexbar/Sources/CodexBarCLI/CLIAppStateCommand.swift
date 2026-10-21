import CodexBarCore
import Commander
import Foundation

extension CodexBarCLI {
    /// Commands that only read or clear local files (one dispatch case keeps `main` within its complexity limit).
    static func runLocalFileCommand(path: [String], values: ParsedValues) {
        if path == ["app-state"] {
            self.runAppState(values)
        } else {
            self.runCacheClear(values)
        }
    }

    /// `codexbar app-state [--json]`: prints the state mirror the running app keeps
    /// (`.swift-app-state/codexbar.json` under the fleet state root, else the home copy). Read-only; it starts no
    /// provider fetch.
    static func runAppState(_ values: ParsedValues) {
        let output = CLIOutputPreferences.from(values: values)
        let url = CodexBarAppStateMirror.existingFileURL() ?? CodexBarAppStateMirror.fileURL()
        let envelope: CodexBarAppStateMirror.Envelope
        do {
            envelope = try CodexBarAppStateMirror.read(from: url)
        } catch {
            Self.exit(
                code: .failure,
                message: "No CodexBar app state at \(url.path). Is CodexBar running?",
                output: output,
                kind: .runtime)
        }
        switch output.format {
        case .json:
            Self.printJSON(envelope, pretty: output.pretty)
        case .text:
            print(Self.renderAppState(envelope))
        }
        Self.exit(code: .success, output: output, kind: .runtime)
    }

    static func renderAppState(_ envelope: CodexBarAppStateMirror.Envelope) -> String {
        let state = envelope.state
        var lines: [String] = []
        let version = [state.appVersion, state.appBuild.map { "(\($0))" }].compactMap(\.self).joined(separator: " ")
        lines.append("CodexBar \(version.isEmpty ? "?" : version) — \(state.status), updated \(envelope.updatedAt)")
        var details: [String] = []
        if let layout = state.multiAccountMenuLayout { details.append("layout \(layout)") }
        if let role = state.hubRole { details.append("hub role \(role)") }
        if let commit = state.gitCommit { details.append("commit \(commit)") }
        if !details.isEmpty { lines.append(details.joined(separator: ", ")) }
        for provider in state.providers {
            var head = "- \(provider.id)"
            if !provider.enabled { head += " (unavailable)" }
            if let source = provider.source { head += " [\(source)]" }
            if provider.stale { head += " stale" }
            if let at = provider.lastSuccessAt { head += " usage \(at)" }
            lines.append(head)
            if let error = provider.error { lines.append("    error: \(error)") }
            if let error = provider.accountError { lines.append("    accounts error: \(error)") }
            if !provider.windows.isEmpty { lines.append("    \(Self.renderAppStateWindows(provider.windows))") }
            for account in provider.accounts {
                var line = "    \(account.active ? "*" : " ") \(account.label)"
                if !account.windows.isEmpty { line += "  \(Self.renderAppStateWindows(account.windows))" }
                if let error = account.error { line += "  (\(error))" }
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func renderAppStateWindows(_ windows: [CodexBarAppStateMirror.Window]) -> String {
        windows.map { window in
            let percent = window.usedPercent.rounded() == window.usedPercent
                ? String(Int(window.usedPercent))
                : String(format: "%.1f", window.usedPercent)
            return "\(window.name) \(percent)%"
        }.joined(separator: ", ")
    }
}

struct AppStateOptions: CommanderParsable {
    @OptionGroup
    var common: CLICommonOptions
}
