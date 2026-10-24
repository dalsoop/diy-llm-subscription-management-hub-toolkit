import AppKit
import CodexBarCore
import SwiftUI
import Vision
import WebKit
import XCTest
@testable import CodexBar

/// Opt-in proof: real feature views, memory preferences, fake transport/clipboard, unordered windows only.
@MainActor
final class OpenCodexAccessScreenshotRenderTests: XCTestCase {
    func test_renderKoreanSettingsAndErrors() async throws {
        let directory = try self.proofDirectory()
        try await CodexBarLocalizationOverride.$appLanguage.withValue("ko") {
            let source = AccessRenderSource()
            let harness = AccessRenderHarness(source: source)
            let fixture = try CodexWorkspacesNavigationFixture(userDefaults: harness.defaults)
            defer { fixture.cleanup() }
            await harness.feature.store.enter()
            let selection = PreferencesSelection(userDefaults: harness.defaults)
            selection.pane = .opencodex
            let preferences = PreferencesView(
                settings: fixture.settings,
                store: fixture.store,
                updater: DisabledUpdaterController(),
                selection: selection,
                openCodexAccess: harness.feature)
                .defaultAppStorage(harness.defaults)
                .codexBarLocalized()
            try await self.capture(
                preferences,
                name: "settings-ko",
                directory: directory,
                size: .init(width: 1100, height: 1000),
                expected: ["Opencodex", "Opencodex 실행 파일 경로", "대시보드 열기", "합성 연결 A"],
                checkState: {
                    XCTAssertFalse(harness.feature.store.isRefreshing)
                    XCTAssertTrue(harness.feature.store.canMutate)
                })
            XCTAssertEqual(selection.pane.persistenceToken, "opencodex")
            XCTAssertTrue(harness.pasteboard.events.isEmpty)
            XCTAssertEqual(harness.sessions.count, 0)
            try await self.capture(
                OpenCodexAccessSettingsPane(feature: harness.feature).codexBarLocalized(),
                name: "pane-ko",
                directory: directory,
                size: .init(width: 820, height: 1050),
                expected: ["API 키", "합성 연결 A", "사용 기록이 불완전합니다.", "이전 기록의 일부가 생략되었습니다."],
                checkState: {
                    XCTAssertFalse(harness.feature.store.isRefreshing)
                    XCTAssertTrue(harness.feature.store.canMutate)
                })

            source.setListError(.permissionDenied)
            await harness.feature.store.refresh()
            XCTAssertFalse(harness.feature.store.canMutate)
            try await self.capturePane(harness, name: "stale-permission-ko", directory: directory, expected: [
                "관리 권한이 거부되었습니다.", "갱신하지 못했습니다.", "합성 연결 A",
            ])
            for (name, role, stopped, error, expected) in [
                ("client", OpenCodexRuntimeRole.client, false, nil, "허브에서 키를 관리해 주세요."),
                ("unknown", .unknown, false, nil, "로컬 관리 권한이 없습니다."),
                ("stopped", .hub, true, nil, "Opencodex 서버가 중지되어 있습니다."),
                ("permission", .hub, false, OpenCodexAccessError.permissionDenied, "관리 권한이 거부되었습니다."),
            ] {
                let source = AccessRenderSource(role: role, stopped: stopped, statusError: error)
                let harness = AccessRenderHarness(source: source)
                await harness.feature.store.enter()
                await harness.feature.openDashboard()
                try await self.capturePane(harness, name: "\(name)-ko", directory: directory, expected: [expected])
                XCTAssertFalse(harness.feature.store.canMutate)
                XCTAssertEqual(harness.sessions.count, 0)
                let listCount = source.listCount
                XCTAssertEqual(listCount, 0)
            }
        }
    }

    func test_renderMaskedCreationAndCloseReleasesSecret() async throws {
        let directory = try self.proofDirectory()
        try await CodexBarLocalizationOverride.$appLanguage.withValue("ko") {
            let source = AccessRenderSource()
            let harness = AccessRenderHarness(source: source)
            await harness.feature.store.enter()
            XCTAssertTrue(harness.feature.store.create(name: "합성 새 연결"))
            await harness.feature.store.waitForMutation()
            weak var secret = harness.feature.store.disclosure?.secret
            XCTAssertNotNil(secret)
            XCTAssertTrue(harness.pasteboard.events.isEmpty)
            // A fresh disclosure starts masked. Never reveal it or collect a revealed accessibility tree.
            try await self.capture(
                OpenCodexAccessDisclosureView(store: harness.feature.store, clipboard: harness.feature.clipboard),
                name: "created-masked-ko",
                directory: directory,
                size: .init(width: 540, height: 420),
                expected: ["새 API 키", "합성 새 연결", "••••••••••••••••", "비밀값 복사", "닫고 비밀값 해제"],
                press: "닫고 비밀값 해제")
            XCTAssertNil(harness.feature.store.disclosure)
            XCTAssertNil(secret)
            XCTAssertTrue(harness.pasteboard.events.isEmpty)
            let createCount = source.createCount
            XCTAssertEqual(createCount, 1)
        }
    }

    func test_renderRealDashboardWithOfflineHTMLAndWindowReuse() async throws {
        let directory = try self.proofDirectory()
        try await CodexBarLocalizationOverride.$appLanguage.withValue("ko") {
            let harness = AccessRenderHarness(source: AccessRenderSource())
            defer { harness.feature.dashboard.close() }
            await harness.feature.openDashboard()
            await harness.feature.openDashboard()
            XCTAssertEqual(harness.sessions.count, 1)
            let session = try XCTUnwrap(harness.sessions.first)
            XCTAssertEqual(session.presentations, 2)
            XCTAssertEqual(session.loads, 1)
            let webView = try XCTUnwrap(session.native.webView)
            XCTAssertFalse(webView.configuration.websiteDataStore.isPersistent)
            XCTAssertTrue(webView.configuration.userContentController.userScripts.isEmpty)
            let deadline = ContinuousClock.now.advanced(by: .seconds(15))
            while harness.feature.dashboard.state.phase == .loading, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertEqual(harness.feature.dashboard.state.phase, .ready)
            XCTAssertEqual(webView.title, "합성 대시보드")
            let content = try XCTUnwrap(session.window?.contentView)
            session.window?.layoutIfNeeded()
            content.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            // WebKit paints asynchronously; snapshot its local HTML separately, then the native window content.
            let snapshot = try await webView.takeSnapshot(configuration: nil)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(snapshot.tiffRepresentation)))
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: directory.appendingPathComponent("dashboard-html-ko.png"))
            try await self.capture(
                OpenCodexDashboardView(
                    state: harness.feature.dashboard.state,
                    webView: webView,
                    retry: {},
                    openExternal: {}),
                name: "dashboard-window-ko",
                directory: directory,
                size: .init(width: 980, height: 760),
                expected: ["대시보드 다시 시도", "localhost:18432/dashboard"])

            session.callbacks.event(.failed(.tls))
            try await Task.sleep(for: .milliseconds(100))
            try await self.capture(
                OpenCodexDashboardView(
                    state: harness.feature.dashboard.state,
                    webView: webView,
                    retry: {},
                    openExternal: {}),
                name: "dashboard-error-ko",
                directory: directory,
                size: .init(width: 980, height: 760),
                expected: ["대시보드에 안전하게 연결하지 못했습니다."])
            harness.feature.dashboard.close()
            XCTAssertNil(session.native.webView)
            XCTAssertNil(session.window?.contentView)
            XCTAssertEqual(harness.feature.dashboard.state.phase, .closed)
            await harness.feature.openDashboard()
            XCTAssertEqual(harness.sessions.count, 2)
            XCTAssertFalse(webView.configuration.websiteDataStore === harness.sessions[1].native.webView?
                .configuration.websiteDataStore)
        }
    }

    private func proofDirectory() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["CODEXBAR_OPENCODEX_ACCESS_PROOF_DIR"] else {
            throw XCTSkip("Set CODEXBAR_OPENCODEX_ACCESS_PROOF_DIR for synthetic UI proof.")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func capturePane(
        _ harness: AccessRenderHarness, name: String, directory: URL, expected: [String]) async throws
    {
        try await self.capture(
            OpenCodexAccessSettingsPane(feature: harness.feature).codexBarLocalized(),
            name: name,
            directory: directory,
            size: .init(width: 820, height: 1050),
            expected: expected)
    }

    private func capture(
        _ view: some View,
        name: String,
        directory: URL,
        size: NSSize,
        expected: [String],
        press: String? = nil,
        checkState: (@MainActor () -> Void)? = nil) async throws
    {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            DispatchQueue.main.async {
                do {
                    // Non-task thread scope covers AppKit's lazy native Form drawing without global defaults.
                    try CodexBarLocalizationOverride.$appLanguage.withValue("ko") {
                        let root = AnyView(view
                            .environment(\.locale, Locale(identifier: "ko_KR"))
                            .environment(\.colorScheme, .light)
                            .environment(\.accessibilityEnabled, true)
                            .frame(width: size.width, height: size.height)
                            .background(Color(nsColor: .windowBackgroundColor)))
                        let surface = AccessRenderSurface(root: root, size: size)
                        defer { surface.close() }
                        try self.captureSynchronously(
                            surface,
                            name: name,
                            directory: directory,
                            expected: expected,
                            press: press,
                            checkState: checkState)
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func captureSynchronously(
        _ surface: AccessRenderSurface,
        name: String,
        directory: URL,
        expected: [String],
        press: String? = nil,
        checkState: (@MainActor () -> Void)? = nil) throws
    {
        let hosting = surface.hosting
        for _ in 0..<5 {
            surface.window.layoutIfNeeded()
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        checkState?()
        let accessibility = MenuLayoutScreenshotRenderTests.accessibilityText(hosting)
        let target = name == "settings-ko" ? (hosting.superview ?? hosting) : hosting
        let png = try self.pngData(target)
        let pixels = try self.recognizedText(png)
        let visible = accessibility + "\n" + pixels
        // Check both pixel recognition and accessibility before writing any evidence or diagnostics.
        XCTAssertFalse(visible.contains("synthetic-never-capture"))
        guard !visible.contains("synthetic-never-capture") else { return }
        // OCR may omit spaces between Latin and Hangul glyphs; preserve the complete text assertion.
        let normalized = visible.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        for text in expected {
            let expectedText = text.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            XCTAssertTrue(normalized.contains(expectedText), "\(name): missing \(text)")
        }
        try accessibility.write(
            to: directory.appendingPathComponent("\(name)-accessibility.txt"),
            atomically: true,
            encoding: .utf8)
        try pixels.write(
            to: directory.appendingPathComponent("\(name)-ocr.txt"),
            atomically: true,
            encoding: .utf8)
        XCTAssertLessThan(png.count, 2 * 1024 * 1024)
        try png.write(to: directory.appendingPathComponent("\(name).png"))
        if let press {
            let button = try XCTUnwrap(Self.button(named: press, in: hosting))
            let selector = NSSelectorFromString("accessibilityPerformPress")
            typealias Press = @convention(c) (AnyObject, Selector) -> Bool
            let action = unsafeBitCast(button.method(for: selector), to: Press.self)
            XCTAssertTrue(action(button, selector))
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private func recognizedText(_ data: Data) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(data: data).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private func pngData(_ view: NSView) throws -> Data {
        let data: Data?
        if view.window != nil {
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            data = bitmap.representation(using: .png, properties: [:])
        } else {
            data = MenuLayoutScreenshotRenderTests.pngDataWithWindow(hosting: view)
        }
        return try XCTUnwrap(data)
    }

    private static func button(named name: String, in element: Any, depth: Int = 0) -> NSObject? {
        guard depth < 30, let object = element as? NSObject else { return nil }
        let label = #selector(NSAccessibilityProtocol.accessibilityLabel)
        if object.responds(to: label),
           object.perform(label)?.takeUnretainedValue() as? String == name,
           object.responds(to: NSSelectorFromString("accessibilityPerformPress")) { return object }
        let children = #selector(NSAccessibilityProtocol.accessibilityChildren)
        guard object.responds(to: children),
              let values = object.perform(children)?.takeUnretainedValue() as? [Any] else { return nil }
        return values.lazy.compactMap { self.button(named: name, in: $0, depth: depth + 1) }.first
    }
}

@MainActor
private final class AccessRenderSurface {
    let hosting: NSHostingView<AnyView>
    let window: NSWindow

    init(root: AnyView, size: NSSize) {
        self.hosting = NSHostingView(rootView: root)
        self.hosting.appearance = NSAppearance(named: .aqua)
        self.window = NSWindow(
            contentRect: .init(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        self.window.isReleasedWhenClosed = false
        self.window.appearance = self.hosting.appearance
        self.window.contentView = self.hosting
    }

    func close() { self.window.contentView = nil; self.window.close() }
}

@MainActor
private final class AccessRenderSource: OpenCodexAccessSource {
    let role: OpenCodexRuntimeRole
    let stopped: Bool
    let statusError: OpenCodexAccessError?
    var listError: OpenCodexAccessError?
    private(set) var listCount = 0
    private(set) var createCount = 0
    private static let date = Date(timeIntervalSince1970: 1_800_000_000)

    init(role: OpenCodexRuntimeRole = .hub, stopped: Bool = false, statusError: OpenCodexAccessError? = nil) {
        self.role = role; self.stopped = stopped; self.statusError = statusError
    }

    func setListError(_ value: OpenCodexAccessError) { self.listError = value }
    func status() async throws -> OpenCodexAccessStatus {
        if let statusError { throw statusError }
        return .init(
            runtimeRole: self.role,
            proxyRunning: !self.stopped,
            dashboardURL: URL(string: "http://localhost:18432/dashboard"))
    }

    func list() async throws -> OpenCodexAccessKeyList {
        self.listCount += 1
        if let listError { throw listError }
        return .init(
            keys: [.init(
                id: "synthetic-id-a",
                name: "합성 연결 A",
                prefix: "demo-masked",
                createdAt: Self.date,
                allowedProviders: ["openai"],
                allowedModels: ["synthetic-model"],
                usage: .recorded(requests7d: 3, totalRequests: 8, lastUsedAt: Self.date))],
            attributionSince: Self.date,
            historyTruncated: true,
            usageIncomplete: true)
    }

    func create(name: String) async throws -> OpenCodexAccessCreatedKey {
        self.createCount += 1
        return .init(
            id: "synthetic-created",
            name: name,
            createdAt: Self.date,
            secret: .init("synthetic-never-capture"))
    }

    func rename(id: String, name: String) async throws -> OpenCodexAccessRenamedKey {
        XCTFail("Unexpected rename in render fixture")
        throw OpenCodexAccessError.renameUnsupported
    }

    func revoke(id: String) async throws { XCTFail("Unexpected revoke in render fixture") }
}

@MainActor
private final class AccessRenderSession: OpenCodexDashboardSession {
    let native: OpenCodexDashboardWebSession
    let callbacks: OpenCodexDashboardSessionCallbacks
    var window: NSWindow?
    var loads = 0
    var presentations = 0

    init(state: OpenCodexDashboardState, callbacks: OpenCodexDashboardSessionCallbacks) {
        self.callbacks = callbacks
        var containedWindow: NSWindow?
        self.native = OpenCodexDashboardWebSession(
            state: state,
            callbacks: callbacks,
            presentWindow: { containedWindow = $0 })
        self.native.present()
        self.window = containedWindow
    }

    func load(_ url: URL) {
        self.loads += 1
        // No URLRequest or listening server: CSP also prevents accidental subresource fetches.
        self.native.webView?.loadHTMLString("""
        <!doctype html><html lang="ko"><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
        <title>합성 대시보드</title><style>body{font:18px -apple-system;padding:36px;background:#f4f5f7}
        section{padding:24px;background:white;border-radius:12px}p{color:#444}</style>
        <h1>Opencodex 합성 대시보드</h1><section><h2>합성 연결 A</h2>
        <p>오프라인 화면 검증 · 실제 서버 연결 없음</p><p>허용 공급자: openai · 요청 횟수: 8</p>
        <p>인증과 운영 데이터는 검증하지 않았습니다.</p></section></html>
        """, baseURL: url)
    }

    func present() { self.presentations += 1; self.native.present() }
    func stop() { self.native.stop() }
    func close() { self.native.close() }
}

@MainActor
private final class AccessRenderHarness {
    let defaults = InMemoryUserDefaults()
    let pasteboard = OpenCodexAccessFakePasteboard()
    var sessions: [AccessRenderSession] = []
    var feature: OpenCodexAccessSettings!

    init(source: AccessRenderSource) {
        let dashboard = OpenCodexDashboardWindowController(makeSession: { [weak self] state, callbacks in
            let session = AccessRenderSession(state: state, callbacks: callbacks)
            self?.sessions.append(session)
            return session
        }, openBrowser: { _ in XCTFail("Unexpected browser open"); return false })
        self.feature = OpenCodexAccessSettings(
            defaults: self.defaults,
            clipboard: OpenCodexAccessClipboard(pasteboard: self.pasteboard, schedule: { _, _ in }),
            dashboard: dashboard,
            makeConnection: { _ in .init(source: source, identity: "synthetic", renameCapability: .available) })
    }
}
