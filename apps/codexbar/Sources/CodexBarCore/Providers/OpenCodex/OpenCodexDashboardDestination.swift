import Foundation

public struct OpenCodexDashboardDestination: Equatable, Sendable {
    public enum Navigation: Equatable, Sendable {
        case embedded, externalBrowser, requiresUserAction, reject
    }

    public let url: URL

    public init(_ raw: String) throws {
        guard !raw.contains("\\"), raw.rangeOfCharacter(from: .controlCharacters) == nil,
              let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true,
              scheme == "https" || ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host),
              let url = components.url
        else { throw OpenCodexAccessError.invalidDashboardURL }
        self.url = url
    }

    /// Pass true only for an explicit link click or user-initiated new-window action.
    public func navigation(to target: URL, userInitiated: Bool) -> Navigation {
        guard let validated = try? Self(target.absoluteString) else { return .reject }
        if Self.origin(self.url) == Self.origin(validated.url) { return .embedded }
        return userInitiated ? .externalBrowser : .requiresUserAction
    }

    private static func origin(_ url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? ""
        return "\(scheme)://\(host):\(url.port ?? (scheme == "https" ? 443 : 80))"
    }
}
