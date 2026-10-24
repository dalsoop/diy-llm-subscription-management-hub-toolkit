import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
struct ProviderSwitcherAccountQuotaTests {
    @Test
    func `each account keeps its own track including unknown and exhausted quotas`() throws {
        var values: [ProviderInstanceID: [ProviderSwitcherAccountQuota]] = [
            .codex: [
                .init(id: "one", percent: 90, isActive: false),
                .init(id: "two", percent: 45, isActive: true),
                .init(id: "three", percent: 0, isActive: false),
            ],
            .claude: [
                .init(id: "a", percent: 15, isActive: true),
                .init(id: "b", percent: nil, isActive: false),
            ],
        ]
        let view = Self.view(quotas: { values[$0] ?? [] })
        view.layoutSubtreeIfNeeded()
        #expect(view._test_quotaIndicatorCounts() == [0, 3, 2, 0, 0, 0])
        #expect(view._test_quotaAccountIDs()[1] == ["one", "two", "three"])
        #expect(view._test_quotaIndicatorFillRatios() == [0.9, 0.45, 0, 0.15, 0])
        let frames = view._test_quotaIndicatorTrackFrames()
        #expect(frames.count == 5)
        for (index, frame) in frames.enumerated() {
            #expect(view.bounds.contains(frame))
            for other in frames.dropFirst(index + 1) {
                #expect(!frame.intersects(other))
            }
        }
        let contents = view._test_buttonContentFrames(inSwitcherCoordinates: true)
        for (buttonIndex, tracks) in [(1, Array(frames.prefix(3))), (2, Array(frames.suffix(2)))] {
            let content = try #require(contents[buttonIndex])
            for track in tracks {
                #expect(!content.intersects(track))
            }
        }
        let originalHeight = view.frame.height
        values[.codex] = [.init(id: "two", percent: 60, isActive: true)]
        view.updateQuotaIndicators()
        view.layoutSubtreeIfNeeded()
        #expect(view._test_quotaIndicatorCounts() == [0, 1, 2, 0, 0, 0])
        #expect(view._test_quotaAccountIDs()[1] == ["two"])
        #expect(view.frame.height < originalHeight)
        #expect(view.requiresMenuRowReplacement)
    }

    @Test
    func `text-only tabs keep five account meters below their labels`() throws {
        let view = Self.view(showsIcons: false, quotas: { provider in
            provider == .codex ? (0..<5).map {
                .init(id: "account-\($0)", percent: Double($0) * 20, isActive: $0 == 1)
            } : []
        })
        view.layoutSubtreeIfNeeded()
        #expect(view._test_quotaIndicatorCounts() == [0, 5, 0, 0, 0, 0])
        let content = try #require(view._test_buttonContentFrames(inSwitcherCoordinates: true)[1])
        for track in view._test_quotaIndicatorTrackFrames() {
            #expect(view.bounds.contains(track))
            #expect(!content.intersects(track))
        }
    }

    @Test
    func `native width changes redistribute every switcher row without changing account identities`() {
        let view = Self.view(quotas: { provider in
            provider == .codex ? [
                .init(id: "one", percent: 40, isActive: true),
                .init(id: "two", percent: 80, isActive: false),
            ] : []
        })
        let identities = view._test_quotaAccountIDs()
        for width: CGFloat in [310, 429, 351, 310] {
            view.setFrameSize(NSSize(width: width, height: view.frame.height))
            view.layoutSubtreeIfNeeded()
            let buttons = view._test_buttonFrames()
            #expect(abs(buttons[2].maxX - (width - 16)) <= 1)
            #expect(abs(buttons[5].maxX - (width - 16)) <= 1)
            for frame in buttons {
                #expect(view.bounds.contains(frame))
            }
            #expect(view._test_quotaAccountIDs() == identities)
            #expect(view.intrinsicContentSize.width == width)
        }
    }

    @Test
    func `capture synthetic account quota rows at multiple native popup widths`() throws {
        guard let path = ProcessInfo.processInfo.environment["CODEXBAR_ACCOUNT_SWITCHER_PROOF_DIR"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let view = Self.view(quotas: { provider in
            switch provider {
            case .codex:
                [
                    .init(id: "one", percent: 90, isActive: false),
                    .init(id: "two", percent: 45, isActive: true),
                    .init(id: "three", percent: 0, isActive: false),
                ]
            case .claude:
                [
                    .init(id: "a", percent: 15, isActive: true),
                    .init(id: "b", percent: nil, isActive: false),
                ]
            default: []
            }
        })
        view.appearance = NSAppearance(named: .aqua)
        view.layer?.backgroundColor = NSColor(calibratedWhite: 0.94, alpha: 1).cgColor
        for width: CGFloat in [310, 429] {
            view.setFrameSize(NSSize(width: width, height: view.frame.height))
            let window = NSWindow(contentRect: view.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.backgroundColor = .windowBackgroundColor
            window.orderFront(nil)
            window.layoutIfNeeded()
            view.layoutSubtreeIfNeeded()
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: directory.appendingPathComponent("account-bars-\(Int(width)).png"))
            window.contentView = nil
            window.close()
        }
    }

    private static func view(
        showsIcons: Bool = true,
        quotas: @escaping (ProviderInstanceID) -> [ProviderSwitcherAccountQuota]) -> ProviderSwitcherView
    {
        ProviderSwitcherView(
            providers: [.codex, .claude, .cursor, .antigravity, .grok],
            selected: .provider(.claude),
            includesOverview: true,
            width: 310,
            showsIcons: showsIcons,
            iconProvider: { _ in NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil) ?? NSImage() },
            weeklyRemainingProvider: { _ in nil },
            accountQuotaProvider: quotas,
            onSelect: { _ in })
    }
}
