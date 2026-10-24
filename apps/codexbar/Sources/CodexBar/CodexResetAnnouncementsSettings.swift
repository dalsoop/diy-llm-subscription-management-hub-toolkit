import CodexBarCore
import SwiftUI

enum CodexResetAnnouncementsSettings {
    @MainActor
    static func toggle(context: ProviderSettingsContext) -> ProviderSettingsToggleDescriptor {
        let draftKey = "codex-reset-news-url-draft"
        let errorKey = "codex-reset-news-url-error"
        let field = ProviderSettingsFieldDescriptor(
            id: "codex-reset-news-url",
            title: "reset_news_provider_url",
            subtitle: "reset_news_url_help",
            kind: .plain,
            placeholder: CodexResetAnnouncements.defaultProviderURL,
            binding: Binding(
                get: { context.statusText(draftKey) ?? context.settings.codexResetAnnouncementsProviderURL },
                set: { context.setStatusText(draftKey, $0) }),
            actions: [ProviderSettingsActionDescriptor(
                id: "codex-reset-news-save",
                title: "reset_news_save",
                style: .bordered,
                isVisible: nil,
                perform: {
                    let address = context.statusText(draftKey) ?? context.settings.codexResetAnnouncementsProviderURL
                    guard context.settings.setCodexResetAnnouncementsProviderURL(address) else {
                        context.setStatusText(errorKey, L("reset_news_invalid_url"))
                        return
                    }
                    context.setStatusText(errorKey, nil)
                    context.setStatusText(draftKey, nil)
                    context.store.configureCodexResetAnnouncements()
                    await context.store.codexResetAnnouncements.refresh()
                })],
            isVisible: nil)
        return ProviderSettingsToggleDescriptor(
            id: "codex-reset-news",
            title: "reset_news_title",
            subtitle: "reset_news_help",
            binding: context.binding(\.codexResetAnnouncementsEnabled),
            statusText: { context.statusText(errorKey) ?? context.store.codexResetAnnouncements.statusText },
            actions: [ProviderSettingsActionDescriptor(
                id: "codex-reset-news-refresh",
                title: "Refresh",
                style: .link,
                isVisible: nil,
                perform: {
                    context.store.configureCodexResetAnnouncements()
                    await context.store.codexResetAnnouncements.refresh()
                })],
            inlineFields: [field],
            isVisible: nil,
            onChange: { _ in context.store.configureCodexResetAnnouncements() },
            onAppDidBecomeActive: nil,
            onAppearWhenEnabled: { context.store.configureCodexResetAnnouncements() })
    }
}
