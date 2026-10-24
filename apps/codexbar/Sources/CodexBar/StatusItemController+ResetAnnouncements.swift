import AppKit
import CodexBarCore
import SwiftUI

extension StatusItemController {
    /// Public reports belong to the provider, so account renderers never own or duplicate this section.
    func addCodexResetAnnouncementsSection(to menu: NSMenu, provider: UsageProvider, width: CGFloat) {
        guard provider == .codex,
              let presentation = CodexResetAnnouncementsPresentation.make(
                  store: self.store.codexResetAnnouncements,
                  now: Date())
        else { return }
        menu.addItem(self.makeMenuCardItem(
            { resolvedWidth in
                CodexResetAnnouncementsContent(presentation: presentation)
                    .padding(.horizontal, UsageMenuCardLayout.horizontalPadding)
                    .padding(.vertical, 6)
                    .frame(width: resolvedWidth, alignment: .leading)
            },
            id: "codexResetAnnouncements",
            width: width,
            heightCacheScope: provider.rawValue,
            heightCacheFingerprint: presentation.heightFingerprint,
            containsInteractiveControls: true))
        menu.addItem(.separator())
    }
}
