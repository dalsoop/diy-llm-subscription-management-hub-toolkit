import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
final class OpenCodexAccessFakePasteboard: OpenCodexAccessPasteboard {
    var changeCount = 0
    var events: [String] = []
    var value: String?
    var writeSucceeds = true
    var foreignCopyAfterWrite = false
    var foreignCopyDuringOwnershipCheck = false
    var ownership: UUID?
    var writtenOwnerships: [UUID] = []
    func prepareForSecret() {
        self.events.append("device-only")
        self.changeCount += 1
        self.value = nil
        self.ownership = nil
    }

    func writeSecret(_ value: String, ownership: UUID) -> Bool {
        self.events.append("concealed+transient")
        self.changeCount += 1
        if self.writeSucceeds {
            self.value = value
            self.ownership = ownership
            self.writtenOwnerships.append(ownership)
        }
        if self.foreignCopyAfterWrite {
            self.changeCount += 1
            self.value = "foreign item between write and count capture"
            self.ownership = nil
        }
        return self.writeSucceeds
    }

    func containsOwnership(_ ownership: UUID) -> Bool {
        let owned = self.ownership == ownership
        if self.foreignCopyDuringOwnershipCheck {
            self.changeCount += 1
            self.value = "foreign item during ownership check"
            self.ownership = nil
        }
        return owned
    }

    func clear() {
        self.events.append("clear")
        self.changeCount += 1
        self.value = nil
        self.ownership = nil
    }
}

@MainActor
struct OpenCodexAccessClipboardTests {
    @Test
    func `foreign copy between successful write and owned count capture is never cleared`() {
        let pasteboard = OpenCodexAccessFakePasteboard()
        pasteboard.foreignCopyAfterWrite = true
        var expirations: [@MainActor @Sendable () -> Void] = []
        let clipboard = OpenCodexAccessClipboard(pasteboard: pasteboard) { _, action in
            expirations.append(action)
        }
        #expect(clipboard.copy(.init("synthetic")))
        #expect(pasteboard.value == "foreign item between write and count capture")
        expirations[0]()
        #expect(pasteboard.value == "foreign item between write and count capture")
        #expect(!pasteboard.events.contains("clear"))
    }

    @Test
    func `foreign copy during marker lookup is protected by final count check`() {
        let pasteboard = OpenCodexAccessFakePasteboard()
        var expiration: (@MainActor @Sendable () -> Void)?
        let clipboard = OpenCodexAccessClipboard(pasteboard: pasteboard) { _, action in expiration = action }
        #expect(clipboard.copy(.init("synthetic")))
        pasteboard.foreignCopyDuringOwnershipCheck = true
        expiration?()
        #expect(pasteboard.value == "foreign item during ownership check")
        #expect(!pasteboard.events.contains("clear"))
    }

    @Test
    func `only explicit copy prepares local concealed transient data and expiry clears only owned count`() {
        let pasteboard = OpenCodexAccessFakePasteboard()
        var expirations: [@MainActor @Sendable () -> Void] = []
        var delays: [TimeInterval] = []
        let clipboard = OpenCodexAccessClipboard(pasteboard: pasteboard) { delay, action in
            delays.append(delay)
            expirations.append(action)
        }
        #expect(pasteboard.events.isEmpty)
        #expect(clipboard.copy(.init("synthetic")))
        #expect(pasteboard.events == ["device-only", "concealed+transient"])
        #expect(delays == [60])
        pasteboard.changeCount += 1
        pasteboard.value = "user's later content"
        expirations[0]()
        #expect(pasteboard.value == "user's later content")
        #expect(clipboard.copy(.init("second synthetic")))
        #expect(pasteboard.writtenOwnerships.count == 2)
        #expect(pasteboard.writtenOwnerships[0] != pasteboard.writtenOwnerships[1])
        expirations[1]()
        #expect(pasteboard.value == nil)
    }

    @Test
    func `old expiration cannot clear newer secret and failed copy schedules nothing`() {
        let pasteboard = OpenCodexAccessFakePasteboard()
        var expirations: [@MainActor @Sendable () -> Void] = []
        let clipboard = OpenCodexAccessClipboard(pasteboard: pasteboard, expiration: 12) { _, action in
            expirations.append(action)
        }
        #expect(clipboard.copy(.init("first synthetic")))
        #expect(clipboard.copy(.init("second synthetic")))
        expirations[0]()
        #expect(pasteboard.value == "second synthetic")
        expirations[1]()
        #expect(pasteboard.value == nil)
        pasteboard.writeSucceeds = false
        #expect(!clipboard.copy(.init("failed synthetic")))
        #expect(expirations.count == 2)
    }
}
