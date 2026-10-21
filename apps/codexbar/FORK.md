# dalsoop/CodexBar fork (`gujo`)

This is a long-lived, self-managed fork of [steipete/CodexBar](https://github.com/steipete/CodexBar). It is built and shipped as `net.ranode.codexbar` with its own Sparkle feed, separately from the official app (`com.steipete.codexbar`). Upstream closed the pull request for the fork's feature (steipete/CodexBar#4630, 2026-10-19), so the fork keeps it on its own and does not wait for upstream acceptance.

## Upstream is read-only

- Never write to steipete/CodexBar in any way: no pull requests (do not reopen or edit #4630), no issues, no comments, no reactions, no pushes, and no "Sync fork" or "Contribute" buttons that open pull requests.
- Only read from upstream: `git fetch`, releases and tags.
- Pushes go only to this fork (`dalsoop/CodexBar`) and to the owner's private GitLab repositories. The local `upstream` remote has its push URL disabled.

## Branches

- `gujo` is the only long-lived branch and the release branch. It is an upstream commit (from the first weekly sync on, upstream's newest release tag) plus a small stack of fork commits: the opencodex hub account feature (`feat(…)`, `fix(…)`, `test(…)`, `docs(…)`) and the redistribution settings (`build:` commits that let a redistributor set the bundle ID, feed, Sparkle key and build number).
- The stack is rebased onto each new upstream release tag; `gujo` is force-pushed with a lease. Keep fork commits small and independent so a rebase conflict stays in one commit.
- The former pull request branch `feat/opencodex-hub-accounts` is archived as the tag `archive/opencodex-hub-accounts-pr4630` and deleted. Do not recreate it.

## Fork-only features

- opencodex hub accounts for Claude, Codex and Grok (`docs/configuration.md`, "opencodex hub snapshot").
- The app state mirror `~/.swift-app-state/codexbar.json` and `codexbar app-state [--json]` (`docs/app-state.md`), so scripts and agents can see what the menu shows.

## Weekly sync and release

A weekly job rebases `gujo` onto the newest upstream release, runs the build, the fork's focused tests, `make check` and the locale check, and on green signs, notarises, publishes and installs the build. On a rebase conflict or a red gate it stops, leaves the published release as it is and asks the owner. The job lives outside this repository (private `upstream-mono` `tools/codexbar-fork-sync/`), so this branch carries no fleet configuration.

The build number is upstream's `BUILD_NUMBER` × 100 + the fork's revision for that upstream build (upstream 171 → 17101, 17102, …), so a fork build always sorts above the upstream build it follows.
