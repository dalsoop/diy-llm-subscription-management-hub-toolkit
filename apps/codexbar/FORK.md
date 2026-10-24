# CodexBar in the subscription management toolkit

This component is maintained in `apps/codexbar` of
[dalsoop/diy-llm-subscription-management-hub-toolkit](https://github.com/dalsoop/diy-llm-subscription-management-hub-toolkit).
Submit toolkit branches and pull requests against this repository's `main` branch. The historical
`dalsoop/CodexBar` `gujo` fork is a source of earlier changes, and
[steipete/CodexBar](https://github.com/steipete/CodexBar) remains read-only upstream.

The app uses the existing `net.ranode.codexbar` identity and redistribution configuration. Building or
testing this component does not publish a release. Release assets and signing credentials remain outside Git.

## Fork-only features

- Per-account quota meters and responsive rows in the merged provider switcher
  (`docs/provider-switcher-accounts.md`).

- Configurable public Codex reset news in Settings → Providers → Codex and the Codex menu
  (`docs/reset-announcements.md`).
- opencodex hub accounts for Claude, Codex and Grok (`docs/configuration.md`, "opencodex hub snapshot").
- The app state mirror `~/.swift-app-state/codexbar.json` and `codexbar app-state [--json]` (`docs/app-state.md`), so scripts and agents can see what the menu shows.
