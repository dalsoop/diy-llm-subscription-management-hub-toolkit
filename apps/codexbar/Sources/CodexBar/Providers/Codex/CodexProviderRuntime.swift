import CodexBarCore
import Foundation

@MainActor
final class CodexProviderRuntime: ProviderRuntime {
    let id: UsageProvider = .codex

    func start(context: ProviderRuntimeContext) {
        context.store.configureCodexResetAnnouncements()
    }

    func settingsDidChange(context: ProviderRuntimeContext) {
        context.store.configureCodexResetAnnouncements()
    }

    func stop(context: ProviderRuntimeContext) {
        context.store.codexResetAnnouncements.configure(
            enabled: false, address: context.settings.codexResetAnnouncementsProviderURL)
    }

    func providerDidRefresh(context: ProviderRuntimeContext, provider: UsageProvider) {
        guard provider == .codex else { return }
        Task { [weak store = context.store.codexResetAnnouncements] in await store?.refresh() }
    }

    func perform(action: ProviderRuntimeAction, context: ProviderRuntimeContext) async {
        switch action {
        case let .openAIWebAccessToggled(enabled):
            guard enabled == false else { return }
            context.store.resetOpenAIWebState()
        case .forceSessionRefresh:
            break
        }
    }
}
