import CodexBarCore
import Foundation
import Observation

@MainActor
@Observable
final class CodexResetAnnouncementsStore {
    private(set) var snapshot: CodexResetAnnouncements?
    private(set) var error: CodexResetAnnouncementsError?
    private(set) var isRefreshing = false
    private(set) var checkedAt: Date?
    private(set) var providerURL: URL?
    private(set) var isEnabled = false
    @ObservationIgnored private let client: any CodexResetAnnouncementsFetching
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var nextRequestAt = Date.distantPast

    init(client: any CodexResetAnnouncementsFetching = CodexResetAnnouncementsClient()) {
        self.client = client
    }

    deinit { self.pollTask?.cancel() }

    func configure(
        enabled: Bool,
        address: String,
        automaticallyPoll: Bool = true)
    {
        let url = CodexResetAnnouncements.providerURL(address)
        guard enabled != self.isEnabled || url != self.providerURL else { return }
        self.pollTask?.cancel()
        self.pollTask = nil
        self.generation = UUID()
        self.isEnabled = enabled
        self.providerURL = url
        self.snapshot = nil
        self.checkedAt = nil
        self.isRefreshing = false
        self.nextRequestAt = .distantPast
        self.error = enabled && url == nil ? .invalidURL : nil
        guard enabled, url != nil, automaticallyPoll else { return }
        self.pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard self != nil else { return }
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(300)) } catch { return }
            }
        }
    }

    func refresh(now: Date = Date()) async {
        guard self.isEnabled, let url = self.providerURL,
              !self.isRefreshing, now >= self.nextRequestAt else { return }
        let generation = self.generation
        self.isRefreshing = true
        self.nextRequestAt = now.addingTimeInterval(60)
        defer {
            if generation == self.generation { self.isRefreshing = false }
        }
        do {
            let snapshot = try await self.client.fetch(from: url)
            guard generation == self.generation, !Task.isCancelled else { return }
            self.snapshot = snapshot
            self.checkedAt = now
            self.error = nil
        } catch {
            guard generation == self.generation, !Task.isCancelled else { return }
            let failure = error as? CodexResetAnnouncementsError ?? .unavailable
            self.error = failure
            if case let .retryLater(seconds) = failure {
                self.nextRequestAt = now.addingTimeInterval(seconds)
            }
        }
    }

    var statusText: String {
        if self.isRefreshing { return L("reset_news_loading") }
        if let error = self.error {
            switch error {
            case .invalidURL: return L("reset_news_invalid_url")
            case .unsupportedResponse: return L("reset_news_unsupported")
            case .unavailable: return L("reset_news_unavailable")
            case .retryLater: return L("reset_news_retry_later")
            }
        }
        if let checkedAt = self.checkedAt {
            return L("reset_news_checked", checkedAt.formatted(
                date: .abbreviated,
                time: .shortened))
        }
        return L("reset_news_loading")
    }
}

extension SettingsStore {
    var codexResetAnnouncementsEnabled: Bool {
        get { self.providerConfig(for: .codex)?.codexResetAnnouncementsEnabled ?? false }
        set {
            self.updateProviderConfig(provider: .codex) { $0.codexResetAnnouncementsEnabled = newValue }
        }
    }

    var codexResetAnnouncementsProviderURL: String {
        self.providerConfig(for: .codex)?.codexResetAnnouncementsProviderURL
            ?? CodexResetAnnouncements.defaultProviderURL
    }

    @discardableResult
    func setCodexResetAnnouncementsProviderURL(_ address: String) -> Bool {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = address.isEmpty ? CodexResetAnnouncements.defaultProviderURL : address
        guard CodexResetAnnouncements.providerURL(normalized) != nil else { return false }
        self.updateProviderConfig(provider: .codex) { $0.codexResetAnnouncementsProviderURL = normalized }
        return true
    }
}

extension UsageStore {
    func configureCodexResetAnnouncements() {
        self.codexResetAnnouncements.configure(
            enabled: self.isEnabled(.codex) && self.settings.codexResetAnnouncementsEnabled,
            address: self.settings.codexResetAnnouncementsProviderURL,
            automaticallyPoll: self.startupBehavior.automaticallyStartsBackgroundWork)
    }
}
