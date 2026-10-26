import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct OpenCodexHubLargePoolTests {
    @Test(arguments: [12, 20, 50], OpenCodexHubProvider.allCases)
    func `large linked pools keep every account through projection and expanded compact layout`(
        count: Int, provider: OpenCodexHubProvider) throws
    {
        let accounts = (0..<count).map { index in
            OpenCodexHubAccount(
                idSuffix: String(format: "%04x", index),
                label: nil,
                email: "a\(index)***e@example.com",
                isActive: index == 0,
                quota: index == count - 1 ? OpenCodexHubQuota() :
                    OpenCodexHubQuota(weekly: .init(usedPercent: Double(index % 100), resetsAt: nil)))
        }
        let pool = OpenCodexHubPool(
            provider: provider,
            accounts: accounts,
            switchable: false,
            origin: .linkedCopy(hubName: "hub-mac"))
        let projected = OpenCodexHubAccountProjection.accounts(for: pool, allowsSwitching: true)
        #expect(projected.count == count)
        #expect(Set(projected.map(\.id)).count == count)
        #expect(projected.allSatisfy { !$0.canActivate })
        let last = try #require(projected.last)
        #expect(OpenCodexHubAccountProjection.hubAccount(for: last, in: pool)?.idSuffix
            == String(format: "%04x", count - 1))
        #expect(last.error != nil)
        let plan = AccountMenuLayoutPlanner.plan(accounts: projected, healthyTailExpanded: true)
        #expect(plan.usesCompactLayout)
        #expect(plan.rows.count == count)
        let represented = plan.rows.compactMap { row -> ProviderAccountIdentity? in
            switch row {
            case let .card(id): id
            case let .compact(row): row.accountID
            case .collapsedHealthy: nil
            }
        }
        #expect(Set(represented) == Set(projected.map(\.id)))
    }
}
