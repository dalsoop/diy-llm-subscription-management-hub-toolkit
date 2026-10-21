import Foundation

/// Turns an opencodex hub account into the usage snapshot a provider card renders.
///
/// Windows fill the primary, secondary and tertiary lanes in duration order (5-hour, weekly, monthly), each
/// with its real duration so lane classifiers label them correctly; custom windows become named extra
/// windows. The identity carries only the masked email opencodex lists.
public enum OpenCodexHubUsageProjection {
    public static let sourceLabel = "opencodex"
    static let fiveHourMinutes = 5 * 60
    static let weeklyMinutes = 7 * 24 * 60
    static let monthlyMinutes = 30 * 24 * 60

    public static func snapshot(
        for account: OpenCodexHubAccount,
        provider: OpenCodexHubProvider,
        fallbackUpdatedAt: Date) -> UsageSnapshot
    {
        let quota = account.quota
        let lanes: [RateWindow] = [
            quota.fiveHour.map { self.rateWindow($0, minutes: self.fiveHourMinutes) },
            quota.weekly.map { self.rateWindow($0, minutes: self.weeklyMinutes) },
            quota.monthly.map { self.rateWindow($0, minutes: self.monthlyMinutes) },
        ].compactMap(\.self)
        let extra = quota.custom.enumerated().map { index, window in
            NamedRateWindow(
                id: "opencodex-\(index)",
                title: window.label,
                window: RateWindow(
                    usedPercent: window.usedPercent,
                    windowMinutes: nil,
                    resetsAt: window.resetsAt,
                    resetDescription: nil))
        }
        let usageProvider = provider.usageProvider
        return UsageSnapshot(
            primary: lanes.first,
            secondary: lanes.dropFirst().first,
            tertiary: lanes.dropFirst(2).first,
            extraRateWindows: extra.isEmpty ? nil : extra,
            updatedAt: quota.updatedAt ?? fallbackUpdatedAt,
            identity: ProviderIdentitySnapshot(
                providerID: usageProvider.instanceID,
                accountEmail: account.email.isEmpty ? nil : account.email,
                accountOrganization: account.displayAlias,
                loginMethod: nil))
    }

    /// A short quota summary for menus ("Weekly 51% · Monthly 0%").
    public static func summary(_ quota: OpenCodexHubQuota) -> [(label: String, percent: Double)] {
        var parts: [(String, Double)] = []
        if let window = quota.fiveHour { parts.append(("5h", window.usedPercent)) }
        if let window = quota.weekly { parts.append(("Weekly", window.usedPercent)) }
        if let window = quota.monthly { parts.append(("Monthly", window.usedPercent)) }
        for window in quota.custom {
            parts.append((window.label, window.usedPercent))
        }
        return parts
    }

    private static func rateWindow(_ window: OpenCodexHubQuotaWindow, minutes: Int) -> RateWindow {
        RateWindow(
            usedPercent: window.usedPercent,
            windowMinutes: minutes,
            resetsAt: window.resetsAt,
            resetDescription: nil)
    }
}
