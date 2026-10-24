---
summary: "Account quota meters and responsive layout in the merged provider switcher."
read_when:
  - "Changing provider-switcher account meters or popup width handling."
---

# Provider switcher account meters

Each provider tab shows a separate mini-meter for each cached account in its selected account source.
Paused hub registrations are omitted from both usage cards and meters; the hub management inventory
retains them. Masked emails are never used to merge account identities. Meter order follows the account
cards. The active account's fill is fully opaque; other fills are dimmed.
An account with unavailable usage keeps a dim empty track and an unavailable-usage tooltip. Hovering a
meter identifies the account by its ordinal and marks the active account.

Values follow the existing provider metric preference and remaining/used display setting. Hub-backed
providers use the hub's projected accounts; Claude adapters, managed Codex profiles, and selected token
account inventories use their existing cached snapshots. Dormant inventories do not replace a selected
hub source. No additional account fetches or credential reads are introduced by the switcher.

The switcher reserves space below its labels for the largest account count. Account-count changes that
alter the row height replace the native menu row. Clicking a meter selects its provider; account
activation continues through the account card's existing action.

Native popup widths can change with the selected content and system layout. Hosted rows rebuild their
content at the actual container width, including after cached payload swaps. The switcher redistributes
its columns at that width, and wrapped native notices remeasure their height when the width changes.
Open-menu rebuilds and sibling-tab caches use the same resolved popup width.

Focused verification uses synthetic accounts, memory settings, and injected quota values:

```sh
make test-fast FILTER='ProviderSwitcherAccountQuotaTests|MenuRowResponsiveWidthTests|StatusMenuTests|StatusMenuOpenCodexHubAccountsTests|StatusMenuSwitcherLayout|StatusMenuSwitcherRefreshTests|StatusMenuSwitcherWarmupTests'
```

Set `CODEXBAR_ACCOUNT_SWITCHER_PROOF_DIR` to capture synthetic switchers at 310pt and 429pt. The
captures contain only synthetic account meters and provider labels.
