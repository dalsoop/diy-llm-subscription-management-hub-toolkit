import Foundation

/// Public community reports, independent of every signed-in account's quota and reset credits.
public struct CodexResetAnnouncements: Equatable, Sendable {
    public struct Event: Equatable, Sendable {
        public enum Kind: String, Sendable {
            case reset, banked, announcement, scheduled
        }

        public let id: String
        public let kind: Kind
        public let date: Date?
        public let text: String
        public let sourceURL: URL?
        public let isObserved: Bool
    }

    public struct Watch: Equatable, Sendable {
        public let text: String
        public let expiresAt: Date
        public let sourceURL: URL?
    }

    public let latest: Event?
    public let scheduled: Event?
    public let watch: Watch?
    public let generatedAt: Date?

    public static let defaultProviderURL = "https://codex-resets.com/api/v1/status"

    /// A full, public JSON endpoint. Never accept embedded credentials or non-HTTPS transports.
    public static func providerURL(_ value: String) -> URL? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: value),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.fragment == nil, parts.query == nil,
              let url = parts.url
        else { return nil }
        return url
    }

    public static func sourceURL(_ value: String?) -> URL? {
        guard let value else { return nil }
        return self.providerURL(value)
    }

    public static func decode(_ data: Data) throws -> Self {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexResetAnnouncementsError.unsupportedResponse
        }
        if let status = root["data"] as? [String: Any], status.keys.contains("latest_reset") {
            return try self.decodeStatus(
                status,
                meta: root["meta"] as? [String: Any])
        }
        if let posts = root["resets"] as? [[String: Any]] {
            let events = try posts.map { post in
                try self.event(
                    post,
                    idKey: "postId",
                    dateKey: "postedAt",
                    kind: .announcement)
            }
            return Self(
                latest: self.newest(events),
                scheduled: nil,
                watch: nil,
                generatedAt: self.date(root["lastPolledAt"]))
        }
        if let posts = root["events"] as? [[String: Any]] {
            let events = try posts.map { post in
                let delivered = self.date(post["delivered_at"]) != nil
                return try self.event(
                    post,
                    idKey: "id",
                    dateKey: delivered ? "delivered_at" : "announced_at",
                    kind: delivered
                        ? (post["kind"] as? String == "banked" ? .banked : .reset) : .announcement)
            }
            let scheduled = try (root["scheduled"] as? [String: Any]).map { post in
                try self.event(
                    post,
                    idKey: "url",
                    dateKey: "scheduled_for",
                    kind: .scheduled)
            }
            return Self(
                latest: self.newest(events),
                scheduled: scheduled,
                watch: nil,
                generatedAt: self.date(root["generated_at"]))
        }
        throw CodexResetAnnouncementsError.unsupportedResponse
    }

    private static func decodeStatus(
        _ status: [String: Any],
        meta: [String: Any]?) throws -> Self
    {
        let latest = try (status["latest_reset"] as? [String: Any]).map { post in
            try self.event(
                post,
                idKey: "id",
                dateKey: "announced_at",
                kind: post["reset_type"] as? String == "banked" ? .banked : .reset)
        }
        let scheduled = try (status["scheduled_reset"] as? [String: Any]).map { post in
            try self.event(
                post,
                idKey: "id",
                dateKey: "scheduled_for",
                kind: .scheduled)
        }
        let watch: Watch? = if let value = status["active_watch"] as? [String: Any],
                               let expiresAt = self.date(value["expires_at"])
        {
            Watch(
                text: String((value["text"] as? String ?? "").prefix(500)),
                expiresAt: expiresAt,
                sourceURL: self.link(value))
        } else {
            nil
        }
        return Self(
            latest: latest,
            scheduled: scheduled,
            watch: watch,
            generatedAt: self.date(meta?["generated_at"]))
    }

    private static func event(
        _ post: [String: Any],
        idKey: String,
        dateKey: String,
        kind: Event.Kind) throws -> Event
    {
        guard let id = post[idKey] as? String, !id.isEmpty else {
            throw CodexResetAnnouncementsError.unsupportedResponse
        }
        return Event(
            id: id,
            kind: kind,
            date: self.date(post[dateKey]) ?? (kind == .scheduled ? nil : self.date(post["ts"])),
            text: String((post["text"] as? String ?? post["summary"] as? String ?? "").prefix(500)),
            sourceURL: self.link(post),
            isObserved: (post["source"] as? [String: Any])?["type"] as? String == "observed")
    }

    private static func link(_ post: [String: Any]) -> URL? {
        self.sourceURL((post["source"] as? [String: Any])?["url"] as? String ?? post["url"] as? String)
    }

    private static func newest(_ events: [Event]) -> Event? {
        events.max { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    private static func date(_ value: Any?) -> Date? {
        guard let value = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

public enum CodexResetAnnouncementsError: Error, Equatable, Sendable {
    case invalidURL
    case unsupportedResponse
    case unavailable
    case retryLater(TimeInterval)
}

extension ProviderConfig {
    public var codexResetAnnouncementsEnabled: Bool {
        get { self.extensionValue(forKey: "codexResetAnnouncementsEnabled") ?? false }
        set { self.setExtensionValue(
            newValue,
            forKey: "codexResetAnnouncementsEnabled") }
    }

    public var codexResetAnnouncementsProviderURL: String {
        get {
            self.extensionValue(forKey: "codexResetAnnouncementsProviderURL")
                ?? CodexResetAnnouncements.defaultProviderURL
        }
        set { self.setExtensionValue(
            newValue,
            forKey: "codexResetAnnouncementsProviderURL") }
    }
}
