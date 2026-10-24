---
summary: "Configurable community Codex reset feeds in settings and the Codex menu."
read_when:
  - "Configuring or extending the public reset news provider."
  - "Changing reset feed parsing, polling, or presentation."
---

# Public Codex reset news

In **Settings → Providers → Codex**, enable **Codex reset news**. This opt-in adds community
reports to the Codex menu, independently of account quota, banked reset credits, and quota notifications.
It appears once in a shared provider section, above the account cards, for both stacked and segmented
account layouts. Account cards do not carry copies of the public feed. Settings and this section use
the same app-owned feed store. It never redeems a reset, changes an account, or resumes work.

**Provider URL** takes the full HTTPS JSON endpoint. Choose **Save URL and check** to apply it;
an empty field restores the default. Supported response formats:

| Provider | Endpoint |
| --- | --- |
| [Codex Resets](https://codex-resets.com/api/docs) (default) | `https://codex-resets.com/api/v1/status` |
| [tokenusage.dev](https://tokenusage.dev/developers) | `https://tokenusage.dev/api/resets` |
| [CodexReset](https://codexreset.ai/developers/) | `https://codexreset.ai/api/v1/resets.json` |

A compatible provider can use any of these response shapes at its own URL. The URL is saved in the
Codex provider's configuration as `codexResetAnnouncementsProviderURL`, alongside the
`codexResetAnnouncementsEnabled` boolean. The endpoint must not contain credentials, a query, or a
fragment. Invalid input leaves the saved URL intact. Turning the feature off clears the displayed feed.

Enabled Codex instances poll every five minutes. Manual checks are limited to once a minute and also
respect `Retry-After` on HTTP 429/503 responses. Requests use an isolated ephemeral session without
account credentials or browser cookies and bypass the local HTTP cache. The provider's edge cache can
still delay updates. The menu links the data provider for attribution and links each original source
when available. It shows the source's update time separately from the last successful local check.

Forecasts are unofficial and disappear after their expiry. A scheduled reset stays pending when its
ETA passes; time alone never proves execution. Observed reports have their own label. tokenusage.dev
posts and CodexReset events without delivery evidence remain announcements. A failed refresh keeps
the previous report with a stale indicator; a source timestamp older than 30 minutes also marks data
as potentially outdated. Changing the URL clears the old feed and rejects late responses from it.

All three services are community sources. Their reports do not establish any personal account's
eligibility or current limits. Check the account's own usage view before acting.

## Verification

```sh
make test-fast FILTER='CodexResetAnnouncements|StatusMenuOpenCodexHubAccountsTests'
make check
```

The tests use synthetic feeds, memory settings, and injected clients, including provider changes during
a request, disabling during a request, throttling, stale data, and credential-free HTTP requests.
`CODEXBAR_RESET_NEWS_SCREENSHOT_DIR` optionally renders English and Korean menu content from synthetic
data without replacing or launching the installed app.
