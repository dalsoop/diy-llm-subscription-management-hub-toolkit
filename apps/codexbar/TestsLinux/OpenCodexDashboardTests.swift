import Foundation
import Testing
@testable import CodexBarCore

struct OpenCodexDashboardTests {
    @Test func `OpenCodexDashboard validates addresses and navigation origins`() throws {
        for raw in [
            "http://localhost:321/path",
            "http://127.0.0.1:321",
            "http://[::1]:321",
            "https://hub.example/path",
        ] {
            _ = try OpenCodexDashboardDestination(raw)
        }
        for raw in [
            "http://localhost.evil",
            "http://127.1",
            "file:///tmp/a",
            "javascript:alert(1)",
            "https://u:p@hub.example",
            "https://@hub.example",
            "https:///path",
        ] {
            #expect(throws: OpenCodexAccessError.invalidDashboardURL) { try OpenCodexDashboardDestination(raw) }
        }
        let destination = try OpenCodexDashboardDestination("https://hub.example/path")
        #expect(try destination.navigation(
            to: #require(URL(string: "https://hub.example:443/next")),
            userInitiated: false) == .embedded)
        #expect(try destination
            .navigation(to: #require(URL(string: "https://other.example")), userInitiated: true) ==
            .externalBrowser)
        #expect(try destination
            .navigation(to: #require(URL(string: "https://other.example")), userInitiated: false) ==
            .requiresUserAction)
        #expect(try destination
            .navigation(to: #require(URL(string: "https://u@other.example")), userInitiated: true) == .reject)
    }
}

extension OpenCodexDashboardTests {
    @Test func `OpenCodexDashboard status gates destination for client unknown stopped and missing URL`() throws {
        for role in [OpenCodexRuntimeRole.client, .unknown] {
            let status = OpenCodexAccessStatus(
                runtimeRole: role,
                proxyRunning: true,
                dashboardURL: URL(string: "https://hub.example"))
            #expect(throws: OpenCodexAccessError.unsupportedRole) { try status.dashboardDestination() }
        }
        let stopped = OpenCodexAccessStatus(
            runtimeRole: .hub,
            proxyRunning: false,
            dashboardURL: URL(string: "http://localhost:123"))
        #expect(throws: OpenCodexAccessError.serverStopped) { try stopped.dashboardDestination() }
        let missing = OpenCodexAccessStatus(runtimeRole: .standalone, proxyRunning: true, dashboardURL: nil)
        #expect(throws: OpenCodexAccessError.invalidDashboardURL) { try missing.dashboardDestination() }
        let valid = OpenCodexAccessStatus(
            runtimeRole: .standalone,
            proxyRunning: true,
            dashboardURL: URL(string: "http://localhost:999"))
        #expect(try valid.dashboardDestination().url.port == 999)
        let destination = try OpenCodexDashboardDestination("https://hub.example")
        #expect(try destination
            .navigation(to: #require(URL(string: "https://hub.example:444")), userInitiated: false) ==
            .requiresUserAction)
        #expect(try destination
            .navigation(to: #require(URL(string: "data:text/html,secret")), userInitiated: true) == .reject)
    }
}
