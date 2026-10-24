import AppKit
import CodexBarCore
import SwiftUI
import XCTest
@testable import CodexBar

@MainActor
final class OpenCodexHubAccountManagementRenderTests: XCTestCase {
    func test_syntheticBrowserHandoffAndStaleList() throws {
        guard let path = ProcessInfo.processInfo.environment["CODEXBAR_HUB_FLOW_PROOF_DIR"] else {
            throw XCTSkip("Set CODEXBAR_HUB_FLOW_PROOF_DIR for synthetic rendering")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fixture = try CodexWorkspacesNavigationFixture(userDefaults: InMemoryUserDefaults())
        defer { fixture.cleanup() }
        fixture.settings.codexOpenCodexHubEnabled = true
        for language in ["en", "ko"] {
            try CodexBarLocalizationOverride.$appLanguage.withValue(language) {
                for (name, phase) in [
                    ("browser", OpenCodexHubManagementState.Phase.awaitingReturn),
                    ("stale", .waitingForSync),
                    ("checked", .checked),
                ] {
                    let account = OpenCodexHubAccount(
                        idSuffix: "aaaa",
                        label: "Synthetic Go",
                        email: "t***t@example.invalid",
                        isActive: true,
                        quota: .init(monthly: .init(usedPercent: 0, resetsAt: Date().addingTimeInterval(86400))))
                    let origin: OpenCodexHubPoolOrigin = name == "stale"
                        ? .snapshot(hubName: "fixture", updatedAt: Date().addingTimeInterval(-86400)) : .hubLocal
                    fixture.store.applyOpenCodexHubPool(.init(
                        provider: .openai, accounts: [account], switchable: false, origin: origin), provider: .codex)
                    fixture.store.openCodexHubManagementStates[.codex] = .init(
                        executablePath: fixture.settings.codexOpenCodexHubExecutablePath,
                        snapshotPath: fixture.settings.codexOpenCodexHubSnapshotPath,
                        configRevision: fixture.settings.providerConfigRevision(for: .codex),
                        phase: phase)
                    let view = OpenCodexHubAccountManagementView(
                        provider: .codex,
                        store: fixture.store,
                        openAccounts: {})
                        .padding(24)
                        .frame(width: 620, height: 540, alignment: .topLeading)
                        .background(Color(nsColor: .windowBackgroundColor))
                    let hosting = NSHostingView(rootView: view)
                    hosting.frame = NSRect(x: 0, y: 0, width: 620, height: 540)
                    hosting.appearance = NSAppearance(named: .aqua)
                    hosting.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                    let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                    let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    try data.write(to: directory.appendingPathComponent("\(name)-\(language).png"))
                }
            }
        }
    }
}
