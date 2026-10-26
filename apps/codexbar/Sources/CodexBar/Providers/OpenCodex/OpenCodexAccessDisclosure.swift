import CodexBarCore
import Foundation
import SwiftUI

/// The only app-owned container for a newly created secret. No serialization or reflected children.
public final class OpenCodexAccessDisclosure: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let id: String
    public let name: String
    public let createdAt: Date
    let secret: OpenCodexAccessSecret

    public init(result: OpenCodexAccessCreatedKey) {
        self.id = result.id
        self.name = result.name
        self.createdAt = result.createdAt
        self.secret = result.secret
    }

    public var description: String {
        "OpenCodexAccessDisclosure(<redacted>)"
    }

    public var debugDescription: String {
        self.description
    }

    public var customMirror: Mirror {
        Mirror(self, children: [:])
    }
}

/// Attach once to a stable settings/app root, never to the replaceable pane.
@MainActor
public struct OpenCodexAccessDisclosurePresenter: ViewModifier {
    private let store: OpenCodexAccessStore
    private let clipboard: OpenCodexAccessClipboard

    public init(store: OpenCodexAccessStore, clipboard: OpenCodexAccessClipboard) {
        self.store = store
        self.clipboard = clipboard
    }

    public func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(
            get: { self.store.disclosure != nil },
            set: { if !$0 { self.store.dismissDisclosure() } }))
        {
            OpenCodexAccessDisclosureView(store: self.store, clipboard: self.clipboard)
        }
    }
}

@MainActor
public struct OpenCodexAccessDisclosureView: View {
    private let store: OpenCodexAccessStore
    private let clipboard: OpenCodexAccessClipboard
    @State private var isRevealed = false
    @State private var copySucceeded: Bool?

    public init(store: OpenCodexAccessStore, clipboard: OpenCodexAccessClipboard) {
        self.store = store
        self.clipboard = clipboard
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("opencodex_access_created_title")).font(.headline)
            if let disclosure = self.store.disclosure {
                Text(disclosure.name)
                Text(disclosure.createdAt, format: .dateTime.year().month().day().hour().minute().second())
                Text(L("opencodex_access_secret_once"))
                // No TextField, selectable text, context-menu Copy, or stored revealed String.
                if self.isRevealed {
                    Text(verbatim: disclosure.secret.reveal())
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.disabled)
                        .privacySensitive()
                } else {
                    Text("••••••••••••••••").textSelection(.disabled)
                }
                HStack {
                    Button(L(self.isRevealed ? "opencodex_access_hide" : "opencodex_access_reveal")) {
                        self.isRevealed.toggle()
                    }
                    Button(L("opencodex_access_copy")) {
                        if let secret = self.store.disclosure?.secret {
                            self.copySucceeded = self.clipboard.copy(secret)
                        }
                    }
                }
                Text(L("opencodex_access_clipboard_policy")).font(.caption).foregroundStyle(.secondary)
                if let copySucceeded {
                    Text(L(copySucceeded ? "opencodex_access_copied" : "opencodex_access_copy_failed"))
                }
            }
            Button(L("opencodex_access_close")) { self.store.dismissDisclosure() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(width: 480)
        .textSelection(.disabled)
    }
}
