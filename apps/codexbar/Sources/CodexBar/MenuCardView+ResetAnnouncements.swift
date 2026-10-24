import CodexBarCore
import SwiftUI

struct CodexResetAnnouncementsPresentation: Equatable {
    struct Row: Equatable, Identifiable {
        let id: String
        let title: String
        let detail: String?
        let sourceURL: URL?
    }

    let rows: [Row]
    let statusText: String
    let sourceURL: URL
    let isStale: Bool

    @MainActor
    static func make(
        store: CodexResetAnnouncementsStore,
        now: Date) -> Self?
    {
        guard store.isEnabled, let url = store.providerURL else { return nil }
        let snapshot = store.snapshot
        var rows: [Row] = []
        if let event = snapshot?.latest {
            let title = switch event.kind {
            case .banked: L("reset_news_banked")
            case .announcement: L("reset_news_announced")
            case .reset: L(event.isObserved ? "reset_news_observed" : "reset_news_latest")
            case .scheduled: L("reset_news_scheduled")
            }
            rows.append(Row(
                id: "latest",
                title: title,
                detail: event.date?.formatted(
                    date: .abbreviated,
                    time: .shortened),
                sourceURL: event.sourceURL))
        }
        if let event = snapshot?.scheduled {
            rows.append(Row(
                id: "scheduled",
                title: L("reset_news_scheduled"),
                detail: event.date.map { date in
                    date < now ? L("reset_news_awaiting") : date.formatted(
                        date: .abbreviated,
                        time: .shortened)
                } ?? L("reset_news_awaiting"),
                sourceURL: event.sourceURL))
        }
        if let watch = snapshot?.watch, watch.expiresAt > now {
            rows.append(Row(
                id: "watch",
                title: L("reset_news_outlook"),
                detail: watch.text,
                sourceURL: watch.sourceURL))
        }
        let isStale = store.error != nil || snapshot?.generatedAt.map { now.timeIntervalSince($0) > 1800 } == true
        let status = if let generatedAt = snapshot?.generatedAt, store.error == nil {
            L("reset_news_data_time", generatedAt.formatted(
                date: .abbreviated,
                time: .shortened))
        } else {
            store.statusText
        }
        return Self(
            rows: rows,
            statusText: status,
            sourceURL: url,
            isStale: isStale)
    }

    var heightFingerprint: String {
        let rows = self.rows.map {
            "\($0.id):\($0.title):\($0.detail ?? ""):\($0.sourceURL?.absoluteString ?? "")"
        }.joined(separator: "|")
        return "\(rows)|\(self.statusText)|\(self.isStale)|\(self.sourceURL.absoluteString)"
    }
}

struct CodexResetAnnouncementsContent: View {
    let presentation: CodexResetAnnouncementsPresentation

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 6)
        {
            Text(L("reset_news_title"))
                .font(.caption.weight(.semibold))
            ForEach(self.presentation.rows) { row in
                VStack(
                    alignment: .leading,
                    spacing: 2)
                {
                    if let url = row.sourceURL {
                        Link(
                            row.title,
                            destination: url)
                    } else {
                        Text(row.title)
                    }
                    if let detail = row.detail, !detail.isEmpty {
                        Text(detail).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .font(.caption)
            }
            if self.presentation.isStale {
                Text(L("reset_news_stale")).font(.caption).foregroundStyle(.secondary)
            }
            Text(self.presentation.statusText).font(.caption2).foregroundStyle(.secondary)
            Link(
                L("reset_news_attribution", self.presentation.sourceURL.host ?? ""),
                destination: self.presentation.sourceURL)
                .font(.caption2)
            Text(L("reset_news_disclaimer")).font(.caption2).foregroundStyle(.secondary)
        }
        .fixedSize(
            horizontal: false,
            vertical: true)
    }
}
