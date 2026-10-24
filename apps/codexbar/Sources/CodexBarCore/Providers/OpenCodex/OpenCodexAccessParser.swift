import CoreFoundation
import Foundation

/// Strict required fields, allowlisted projection, and no raw response in any thrown error.
public enum OpenCodexAccessParser {
    public static let maxOutputBytes = 262_144

    static func object(_ data: Data, limit: Int = Self.maxOutputBytes) throws -> [String: Any] {
        guard data.count <= limit else { throw OpenCodexAccessError.outputTooLarge }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenCodexAccessError.invalidResponse
        }
        return object
    }

    static func string(_ value: Any?) throws -> String {
        guard let string = value as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              string.rangeOfCharacter(from: .controlCharacters) == nil
        else { throw OpenCodexAccessError.invalidResponse }
        return string
    }

    static func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0 else { return nil }
        return number.doubleValue
    }

    static func date(_ value: Any?) -> Date? {
        guard let value = value as? String,
              value.range(
                  of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$"#,
                  options: .regularExpression) != nil else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsed = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        guard let parsed, formatter.string(from: parsed).prefix(19) == value.prefix(19) else { return nil }
        return parsed
    }

    static func requiredDate(_ value: Any?) throws -> Date {
        guard let date = self.date(value) else { throw OpenCodexAccessError.invalidResponse }
        return date
    }

    static func scope(_ value: Any?) throws -> [String]? {
        guard let value else { return nil }
        guard let items = value as? [String], items.allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf16.count <= 256 &&
                $0.rangeOfCharacter(from: .controlCharacters) == nil
        }) else { throw OpenCodexAccessError.invalidResponse }
        return items
    }

    public static func status(
        _ data: Data, maxOutputBytes: Int = Self.maxOutputBytes) throws -> OpenCodexAccessStatus
    {
        let object = try self.object(data, limit: maxOutputBytes)
        guard self.number(object["schemaVersion"]) == 1,
              let role = object["runtimeRole"] as? String,
              let proxy = object["proxy"] as? [String: Any], let running = self.bool(proxy["running"])
        else { throw OpenCodexAccessError.invalidResponse }
        let dashboard = object["dashboard"] as? [String: Any]
        var url: URL?
        if let raw = dashboard?["url"] {
            url = try OpenCodexDashboardDestination(self.string(raw)).url
        }
        return .init(
            runtimeRole: OpenCodexRuntimeRole(rawValue: role) ?? .unknown,
            proxyRunning: running,
            dashboardURL: url)
    }

    public static func list(
        _ data: Data, maxOutputBytes: Int = Self.maxOutputBytes) throws -> OpenCodexAccessKeyList
    {
        let object = try self.object(data, limit: maxOutputBytes)
        guard let rows = object["keys"] as? [[String: Any]] else { throw OpenCodexAccessError.invalidResponse }
        let since = self.date(object["attributionSince"])
        var ids = Set<String>()
        let keys = try rows.map { row -> OpenCodexAccessKey in
            let id = try self.string(row["id"])
            guard ids.insert(id).inserted else { throw OpenCodexAccessError.invalidResponse }
            return try .init(
                id: id,
                name: self.string(row["name"]),
                prefix: self.string(row["prefix"]),
                createdAt: self.requiredDate(row["createdAt"]),
                allowedProviders: self.scope(row["allowedProviders"]),
                allowedModels: self.scope(row["allowedModels"]),
                usage: self.usage(row["usage"], available: since != nil))
        }
        return .init(
            keys: keys,
            attributionSince: since,
            historyTruncated: self.bool(object["historyTruncated"]) == true,
            usageIncomplete: self.bool(object["usageIncomplete"]) == true,
            usageIncompleteReason: object["usageIncompleteReason"] as? String)
    }

    private static func usage(_ value: Any?, available: Bool) -> OpenCodexAccessUsage {
        guard let usage = value as? [String: Any] else { return .unavailable }
        if self.bool(usage["ambiguous"]) == true { return .ambiguous }
        guard available else { return .unavailable }
        if let ambiguous = usage["ambiguous"], self.bool(ambiguous) == nil { return .unavailable }
        let recent = self.number(usage["requests7d"])
        let total = self.number(usage["totalRequests"])
        let last = self.date(usage["lastUsedAt"])
        guard usage["requests7d"] == nil || recent != nil,
              usage["totalRequests"] == nil || total != nil,
              usage["lastUsedAt"] == nil || last != nil, recent != nil || total != nil
        else { return .unavailable }
        return .recorded(requests7d: recent, totalRequests: total, lastUsedAt: last)
    }

    public static func created(_ data: Data, expectedName: String) throws -> OpenCodexAccessCreatedKey {
        let object = try self.object(data)
        guard try self.string(object["name"]) == expectedName else { throw OpenCodexAccessError.invalidResponse }
        return try .init(
            id: self.string(object["id"]),
            name: expectedName,
            createdAt: self.requiredDate(object["createdAt"]),
            secret: OpenCodexAccessSecret(self.string(object["key"])))
    }

    public static func renamed(_ data: Data, id: String, name: String) throws -> OpenCodexAccessRenamedKey {
        let object = try self.object(data)
        guard try self.string(object["id"]) == id, try self.string(object["name"]) == name else {
            throw OpenCodexAccessError.invalidResponse
        }
        return try .init(
            id: id,
            name: name,
            createdAt: self.requiredDate(object["createdAt"]),
            allowedProviders: self.scope(object["allowedProviders"]),
            allowedModels: self.scope(object["allowedModels"]))
    }

    public static func revoked(_ data: Data) throws {
        guard try self.bool(self.object(data)["success"]) == true else { throw OpenCodexAccessError.invalidResponse }
    }
}
