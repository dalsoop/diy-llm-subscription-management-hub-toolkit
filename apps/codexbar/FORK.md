# CodexBar in the subscription management toolkit

This component is maintained in `apps/codexbar` of
[dalsoop/diy-llm-subscription-management-hub-toolkit](https://github.com/dalsoop/diy-llm-subscription-management-hub-toolkit).
Submit toolkit branches and pull requests against this repository's `main` branch. The historical
`dalsoop/CodexBar` `gujo` fork is a source of earlier changes, and
[steipete/CodexBar](https://github.com/steipete/CodexBar) remains read-only upstream.

The app uses the existing `net.ranode.codexbar` identity and redistribution configuration. Building or
testing this component does not publish a release. Release assets and signing credentials remain outside Git.

## Fork-only features

- Local Opencodex access-key management and an embedded dashboard, with role checks,
  temporary secret disclosure, and an isolated web session.
- Hub account sign-in handoff and refresh controls in provider settings.
- Per-account quota meters and responsive rows in the merged provider switcher
  (`docs/provider-switcher-accounts.md`).

- Configurable public Codex reset news in Settings → Providers → Codex and the Codex menu
  (`docs/reset-announcements.md`).
- opencodex hub accounts for Claude, Codex and Grok (`docs/configuration.md`, "opencodex hub snapshot").
- The app state mirror `~/.swift-app-state/codexbar.json` and `codexbar app-state [--json]` (`docs/app-state.md`), so scripts and agents can see what the menu shows.

## Source and local previews

The original toolkit import matches historical fork commit `fcb1d1abb`, apart from excluded
environment files and proof logs. The installed 0.80.0 feature set is migrated from immutable
commit `844b2d358`, preserving the toolkit's subsequent account-meter, width, provider-architecture,
and localization fixes. Historical deployment records and private redistribution settings are not imported.
The stale-snapshot changes remain owned by toolkit PR #1 and are excluded from this migration.

`version.env` contains only public version metadata and is tracked despite the general `*.env`
ignore rule. Other environment files remain ignored.

For a signed local debug replacement that retains a redistributor's settings and app group:

```sh
CODEXBAR_LOCAL_PREVIEW=1 \
CODEXBAR_BUNDLE_ID=org.example.codexbar \
CODEXBAR_SIGNING=identity \
APP_IDENTITY='Developer ID Application: Example Developer (TEAMID)' \
./Scripts/package_app.sh debug
```

Use the existing installation's bundle and signing identity. Local previews disable update checks
and record `CodexBuildConfiguration=local-debug-preview`. Packaging creates a bundle; installation
and rollback remain separate operations. Normal debug packages retain their `.debug` identity.
