import Foundation

public enum OpenCodexHubManagementError: Error, Equatable, Sendable {
    case managementAddressRequired
}

/// Opens the hub's existing account UI. Only the address is projected; credentials are never forwarded.
public enum OpenCodexHubManagement {
    public static func accountsURL(
        executablePath: String?,
        provider: OpenCodexHubProvider,
        managementOrigin: String? = nil,
        transport: any OpenCodexAccessTransport = OpenCodexAccessProcessTransport()) async throws -> URL
    {
        guard let binary = OpenCodexHubReader.resolvedExecutablePath(executablePath) else {
            throw OpenCodexHubReaderError.noHubSource("no ocx executable")
        }
        let data: Data
        do {
            data = try await transport.run(.init(
                binary: binary,
                arguments: OpenCodexRuntimeRoleProbe.statusArguments,
                mutation: false,
                timeout: OpenCodexRuntimeRoleProbe.timeout,
                maxOutputBytes: OpenCodexHubReader.maxOutputBytes))
        } catch {
            throw OpenCodexAccessError.communicationFailed
        }
        // Deliberately do not include command output in errors: status contains unrelated private fields.
        guard let url = self.accountsURL(status: data, provider: provider, managementOrigin: managementOrigin) else {
            if self.connectedClient(data) {
                throw OpenCodexHubManagementError.managementAddressRequired
            }
            throw OpenCodexHubReaderError.noHubSource("no connected, secure management address")
        }
        return url
    }

    public static func accountsURL(
        status: Data,
        provider: OpenCodexHubProvider,
        managementOrigin: String? = nil) -> URL?
    {
        guard status.count <= OpenCodexHubReader.maxOutputBytes,
              let object = try? JSONSerialization.jsonObject(with: status) as? [String: Any],
              OpenCodexAccessParser.number(object["schemaVersion"]) == 1,
              OpenCodexAccessParser.bool((object["proxy"] as? [String: Any])?["running"]) == true
        else { return nil }
        let role = OpenCodexRuntimeRoleProbe.parseRole(status)
        let address: String?
        switch role {
        case .client:
            let connection = object["connection"] as? [String: Any]
            guard connection?["state"] as? String == "connected" else { return nil }
            // Remote Link reports its data tunnel as managementUrl. It serves no browser UI.
            // Use only an explicitly configured browser origin for this transport.
            if connection?["transport"] as? String == "link" {
                address = managementOrigin
            } else {
                let reported = connection?["managementUrl"] as? String
                // Older status documents can omit transport; a loopback address still cannot be the hub UI.
                address = reported.map(self.isRemoteManagementOrigin) == true ? reported : managementOrigin
            }
        case .hub:
            address = (object["hub"] as? [String: Any])?["managementPublicOrigin"] as? String
        case .standalone:
            address = (object["dashboard"] as? [String: Any])?["url"] as? String
        case .unknown:
            return nil
        }
        guard let address, var url = self.originComponents(address) else { return nil }
        // Remote management must be an HTTPS origin. Only standalone owns a local browser UI.
        guard role == .standalone ? self.isLoopback(url) : self.isRemoteManagementOrigin(address) else { return nil }
        url.path = "/"
        // Provider-specific by design: the hub's OpenAI pool uses its dedicated Codex account-manager route.
        url.fragment = provider == .openai ? "codex-set" : "providers?provider=\(provider.rawValue)&tab=accounts"
        return url.url
    }

    public static func isRemoteManagementOrigin(_ address: String) -> Bool {
        guard let url = self.originComponents(address) else { return false }
        return url.scheme?.lowercased() == "https" && !self.isLoopback(url)
    }

    private static func originComponents(_ address: String) -> URLComponents? {
        guard let destination = try? OpenCodexDashboardDestination(address),
              let url = URLComponents(url: destination.url, resolvingAgainstBaseURL: false),
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/"
        else { return nil }
        return url
    }

    private static func isLoopback(_ url: URLComponents) -> Bool {
        ["localhost", "127.0.0.1", "[::1]", "::1"].contains(url.host?.lowercased() ?? "")
    }

    private static func connectedClient(_ data: Data) -> Bool {
        guard data.count <= OpenCodexHubReader.maxOutputBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              OpenCodexAccessParser.number(object["schemaVersion"]) == 1,
              OpenCodexAccessParser.bool((object["proxy"] as? [String: Any])?["running"]) == true,
              OpenCodexRuntimeRoleProbe.parseRole(data) == .client
        else { return false }
        return (object["connection"] as? [String: Any])?["state"] as? String == "connected"
    }
}
