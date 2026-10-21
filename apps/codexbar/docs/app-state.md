---
summary: "The app's state mirror file (~/.swift-app-state/codexbar.json) and `codexbar app-state`, for tools that cannot read the menu."
read_when:
  - "Checking what the menu shows from a script, an agent or SSH."
  - "Changing what the app publishes after a refresh."
---

# App state mirror

The menu is not readable from SSH or by agents, so the app also writes what it shows to
`.swift-app-state/codexbar.json` under the fleet state root, the StateMirror convention other apps and
`agent-ui-monitor state CodexBar` use: `SWIFT_APP_STATE_ROOT`, else the tenant root `~/.tenants/<slug>` named by
`ROOM_TENANT`, `AGENT_TENANT`, `TENANT_ID` or `~/.agent-tenant-isolation-manager/current-context.json`, else the home
directory. Under a tenant root the app also keeps the same file at `~/.swift-app-state/codexbar.json`.
`SWIFT_APP_STATE_DIRECTORY` replaces both with one directory. The file is rewritten
atomically after each provider refresh, after each account adapter refresh and whenever the widget snapshot is saved;
an unchanged state is rewritten at most once a minute, so `updatedAt` also shows that the app is running.

```bash
codexbar app-state          # summary
codexbar app-state --json   # the file as JSON
```

`codexbar app-state` only reads the file (the state root's, else the home copy); it starts no provider fetch. It
exits 1 when neither file exists.

## Format

The file uses the StateMirror envelope:

```json
{"app": "codexbar", "updatedAt": "2026-10-19T13:20:00Z", "state": {
  "schemaVersion": 1, "status": "error", "lastError": "codex: …",
  "appVersion": "0.77.1", "appBuild": "17107", "bundleID": "net.ranode.codexbar", "gitCommit": "abcdef123",
  "multiAccountMenuLayout": "stacked", "hubRole": "client",
  "providers": [
    {"id": "codex", "enabled": true, "source": "opencodex-hub", "accountSource": "opencodex-hub",
     "lastRefreshAt": "…", "lastSuccessAt": "…", "error": "…", "stale": false,
     "windows": [{"name": "7d", "usedPercent": 58, "resetAt": "…"}],
     "accounts": [{"label": "pro (a***e@example.com)", "active": true,
                   "windows": [{"name": "weekly", "usedPercent": 58, "resetAt": "…"}]}]}]}}
```

- `status` is `error` when an enabled provider has an `error` or an `accountError`; `lastError` names the first one
  and is left out otherwise.
- `providers` lists the providers shown in the menu, in menu order. `enabled` is false for a shown provider that
  is currently unavailable.
- `source` is `opencodex-hub` for a Codex or Grok card that reads an opencodex hub pool, otherwise the source label
  the card shows. `accountSource` says where the account list comes from (`opencodex-hub`, `opencodex`,
  `claude-swap`, `tcr`, `codex-accounts`); `accountError` is the account list's own error.
- `windows` are the card's quota windows, named by length (`5h`, `7d`, `30d`) or by slot; hub accounts use the
  hub's names (`5h`, `weekly`, `monthly`, custom labels). `stale` is true when the hub snapshot behind the card
  is more than five minutes old.
- `hubRole`: `hub` when a card reads this Mac's own opencodex pools, `client` when it reads the hub's snapshot,
  `client-local-copy` when it shows this Mac's read-only copy because the snapshot is missing or old.

The file holds summaries only: error text is one line of at most 300 characters with anything that looks like a
credential replaced by `<redacted>`, and account labels keep emails masked (`a***e@example.com`). Tokens, cookies,
account ids and unmasked emails are never written.
