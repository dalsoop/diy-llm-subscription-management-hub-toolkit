import AppKit
import CodexBarCore
import Foundation

@MainActor
public protocol OpenCodexAccessPasteboard: AnyObject {
    var changeCount: Int { get }
    func prepareForSecret()
    func writeSecret(_ value: String, ownership: UUID) -> Bool
    func containsOwnership(_ ownership: UUID) -> Bool
    func clear()
}

@MainActor
public final class OpenCodexAccessSystemPasteboard: OpenCodexAccessPasteboard {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }
    public var changeCount: Int {
        self.pasteboard.changeCount
    }

    public func prepareForSecret() {
        // This already clears contents. clearContents here would reset currentHostOnly.
        self.pasteboard.prepareForNewContents(with: [.currentHostOnly])
    }

    public func writeSecret(_ value: String, ownership: UUID) -> Bool {
        let item = NSPasteboardItem()
        guard item.setString(value, forType: .string),
              item.setData(Data(), forType: .init("org.nspasteboard.ConcealedType")),
              item.setData(Data(), forType: .init("org.nspasteboard.TransientType")),
              item.setData(Data(), forType: Self.ownershipType(ownership)) else { return false }
        return self.pasteboard.writeObjects([item])
    }

    public func containsOwnership(_ ownership: UUID) -> Bool {
        // Inspect only type metadata, never read clipboard content or the secret back.
        self.pasteboard.types?.contains(Self.ownershipType(ownership)) == true
    }

    private static func ownershipType(_ ownership: UUID) -> NSPasteboard.PasteboardType {
        .init("app.codexbar.opencodex-access.owner.\(ownership.uuidString.lowercased())")
    }

    public func clear() { self.pasteboard.clearContents() }
}

/// Keeps only a nonsecret ownership marker and change count during expiry, never the copied value.
@MainActor
public final class OpenCodexAccessClipboard {
    public typealias Schedule = @MainActor (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void
    private let pasteboard: any OpenCodexAccessPasteboard
    private let expiration: TimeInterval
    private let schedule: Schedule

    public init(
        pasteboard: any OpenCodexAccessPasteboard,
        expiration: TimeInterval = 60,
        schedule: @escaping Schedule = OpenCodexAccessClipboard.scheduleExpiration)
    {
        self.pasteboard = pasteboard
        self.expiration = expiration.isFinite && expiration >= 0 ? expiration : 60
        self.schedule = schedule
    }

    @discardableResult
    public func copy(_ secret: OpenCodexAccessSecret) -> Bool {
        self.pasteboard.prepareForSecret()
        let ownership = UUID()
        guard self.pasteboard.writeSecret(secret.reveal(), ownership: ownership) else { return false }
        let ownedCount = self.pasteboard.changeCount
        // Retain the clipboard dependency, not the secret, even if the pane/controller goes away.
        let pasteboard = self.pasteboard
        self.schedule(self.expiration) {
            guard pasteboard.changeCount == ownedCount,
                  pasteboard.containsOwnership(ownership),
                  pasteboard.changeCount == ownedCount else { return }
            pasteboard.clear()
        }
        return true
    }

    public static func scheduleExpiration(
        after delay: TimeInterval,
        action: @escaping @MainActor @Sendable () -> Void)
    {
        Task { @MainActor in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            action()
        }
    }
}
