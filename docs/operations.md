# Development and operations

## Prerequisites and dependency setup

Run commands below from the toolkit root unless a command supplies another working directory. Install Bun before dependency setup. The OpenCodex package declares its pinned test-runner Bun version separately from its runtime dependency; its wrapper selects the test runner. Node's package-launcher minimum is not a substitute for Bun as the proxy runtime.

CodexBar requires the Swift 6.2 package toolchain and targets macOS 14 or later for its macOS products. The OpenCodex native app package uses Swift tools 5.9 and targets macOS 14. The root CodexBar workflow runs on the self-hosted Mac CI runner and requires Xcode 27 there. Desktop Tauri work additionally requires Rust and platform build prerequisites. Builds/tests/lint run only on designated build machines; submit Rust build/test/check work through the build queue.

```sh
bun install --frozen-lockfile
bun install --cwd packages/opencodex --frozen-lockfile
bun install --cwd packages/opencodex/gui --frozen-lockfile
```

GUI dependencies are needed by OpenCodex tests that import GUI source, even if no browser is launched. Do not change lockfiles to get past a failed frozen install; diagnose the missing tool/version first.

## Offline and isolated verification

```sh
bun run codexbar:check
make -C apps/codexbar test-fast FILTER='OpenCodexHubLargePoolTests'
bun run codexbar:test
```

The focused command uses the component's isolated test setup. The last command is the full CodexBar runner; for a bounded parallel full run the root CI invokes `apps/codexbar/Scripts/test.sh --direct-workers 2` from the component directory while holding a host compile slot (`build-pipeline slot-exec --pool compile`). Do not substitute live provider probes or enable prompt-producing Keychain access to satisfy verification.

```sh
bun run --cwd packages/opencodex typecheck
bun run --cwd packages/opencodex test tests/ci-workflows/structure-ssot.test.ts
bun run --cwd packages/opencodex test
bun run --cwd packages/opencodex privacy:scan
bun run --cwd packages/opencodex structure:check
bun run --cwd packages/opencodex skill:surface:check
```

Use `bun run ... test`, not the root `opencodex:test` shortcut or a raw `bun test`, when isolation is required. The wrapper creates a synthetic home, clears inherited admission credentials, pins provider homes and temporary directories, uses the package's pinned runner, and cleans up subprocesses. For changed-import selection against this toolkit's base, invoke `bun run --cwd packages/opencodex test --changed=origin/main`; subprocess/source-as-data regressions still need explicit file selection. The inherited `test:changed` shortcut names `dev` and is not automatically retargeted.

GUI checks, when GUI source changes:

```sh
bun run --cwd packages/opencodex/gui test
bun run --cwd packages/opencodex/gui lint
bun run --cwd packages/opencodex/gui lint:i18n
bun run --cwd packages/opencodex/gui build
```

Site changes use `bun install --cwd packages/opencodex/docs-site --frozen-lockfile`, then `bun run --cwd packages/opencodex/docs-site build`. Native model tests use `swift run --package-path packages/opencodex/app MenuBarCoreTests`. Rust helper tests use the queued command `cargo test --locked --manifest-path native/remote-workspace-helper/Cargo.toml` with `packages/opencodex` as the job working directory; do not bypass the queue through the package shortcut.

## Build and local run

```sh
bun run codexbar:build
bun run --cwd packages/opencodex build:gui
```

The first is a Swift release build, not an installed/signed menu bar bundle. The second builds/prepares GUI package assets, not a desktop release. For CodexBar UI validation, run `./Scripts/package_app.sh` from `apps/codexbar` and explicitly open the newly produced `CodexBar.app`. `Scripts/compile_and_run.sh` also stops/relaunches the app and is appropriate only when runtime UI validation is actually required.

A proxy start is an operational action, not an offline smoke test. It can read configured accounts and initialize protected local state. For an authorized local instance, set a dedicated state home before startup:

```sh
export OPENCODEX_HOME="$PWD/.tmp/opencodex-home"
bun run opencodex:start
```

The root shortcut selects port 10100. Check the intended port/state owner before starting; do not stop an unrelated listener to free it. Production/service repair uses `bun run --cwd packages/opencodex src/cli/index.ts service install --force` only when repairing that installation is requested; it changes persistent service behavior and is not a test setup step.

## Environment and state ownership

| Setting | Role and valid scope |
| --- | --- |
| `OPENCODEX_HOME` | OpenCodex configuration/account/service state root; isolate it for a disposable instance. |
| `CODEX_HOME` | Codex client state; not an alias for the proxy state root. |
| `CLAUDE_CONFIG_DIR`, `GROK_HOME` | Provider client homes; isolate through the test wrapper rather than inheriting real accounts. |
| `OPENCODEX_API_AUTH_TOKEN` | Operator-supplied client data-plane admission secret; never an upstream provider credential. |
| `OCX_API_TOKEN_FILE` | Protected service data-plane token file, not the management token. |
| `OPENCODEX_ADMIN_AUTH_TOKEN` | Separate operator-supplied management admission secret; absent configuration uses protected generated admin state. |
| `TMPDIR`, `TMP`, `TEMP` | Task-owned temporary root; the test wrapper pins child temporary state inside its sandbox. |
| `CODEXBAR_ALLOW_TEST_KEYCHAIN_ACCESS` | Explicit live-access override, not ordinary test configuration; do not set it for automated verification. |
| `CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS` | Noninteractive test protection set by the component's test environment. |

Use existing config ownership, restore journal, and uninstall manifest flows to change or restore client configuration. Deleting the whole client state directory is not a reset procedure; it can destroy unrelated authentication and backups.

## Desktop packaging and publication

For authorized local desktop work, install the desktop dependencies, then run `prepare-sidecar`, `prepare-widget` on macOS, and `dev` or `build:local` from `packages/opencodex/desktop`, in that order. Widget preparation and Rust/Tauri compilation use the designated build/queue infrastructure. A missing updater signing key can cause a release-style Tauri command to fail after producing an app; that artifact is not a completed signed release.

CodexBar release signing remains in `Scripts/sign-and-notarize.sh`; OpenCodex release coordination remains in `scripts/release.ts`. Publication requires explicit authorization, the owning maintainer policy, exact-head checks, and complete artifact/update-feed handoff verification. Nested release workflows do not execute as toolkit workflows. No local publish, signing-key substitution, or unrequested service installation is part of development verification.

## Self-hosted macOS CI runner

The root workflow's `macos` job runs only on a self-hosted runner on the team's Mac CI machine. No GitHub-hosted runner carries its labels, so while that runner is offline the job waits in GitHub's queue and fails after 24 hours instead of falling back; a queue-expired run is not evidence and is re-run. There are no non-macOS jobs.

| Item | Value |
| --- | --- |
| Registration | This repository only (repository-level), persistent, vendor auto-update enabled; one job at a time |
| Name and labels | `mac-ci`; `self-hosted`, `macOS`, `ARM64`, `mac-ci` (the job's `runs-on` lists all four) |
| Software | Official `actions/runner` osx-arm64 release (2.338.2 at installation); the tarball's SHA-256 is compared with the value in the release notes before extraction |
| Runner root | `~/github-runner/diy-llm-subscription-management-hub-toolkit` — the runner application directory with `.runner`, credential files (mode 600), `.path`, `.env` |
| Work folder | `_work` inside the runner root, separate from the other CI runner's and the build queue's folders; `apps/codexbar/.build` persists there between runs |
| Admission hook | `~/github-runner/hooks/job-started-hook.sh`, a copy of `.github/runner/job-started-hook.sh`, outside the application directory that auto-update rewrites |
| LaunchAgent | `~/Library/LaunchAgents/actions.runner.<owner>-diy-llm-subscription-management-hub-toolkit.mac-ci.plist` in the `gui/<uid>` domain, generated by the runner's `svc.sh install` with `KeepAlive` added; runs as the machine's login account |
| Logs | `~/Library/Logs/<label>/stdout.log` and `stderr.log`, plus `_diag/` in the runner root |

`.path` holds exactly `$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin` with `$HOME` expanded, so jobs find `build-pipeline` and Homebrew's `python3`. `.env` holds exactly `LANG=en_US.UTF-8` and `ACTIONS_RUNNER_HOOK_JOB_STARTED=<absolute home>/github-runner/hooks/job-started-hook.sh`; values are literal, so `~` is not usable there. The runner's `config.sh` rewrites both files, so they are restored after every configuration run and before the service starts.

The job does not use `sudo`: it sets `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` and fails unless that Xcode's major version is 27. It waits while the 1-minute load average is 30 or higher (at most 30 minutes), runs `make check` under `build-pipeline slot-exec --pool check --wait-max 1800`, and runs the full test under `build-pipeline slot-exec --pool compile --wait-max 1800`. The machine has two compile slots, so a toolkit test run holds one of them for roughly 20–40 minutes; a command that waits past its wait limit runs without a slot rather than failing.

Run these on the Mac CI machine as its login account, from the runner root unless stated, with `label=actions.runner.<owner>-diy-llm-subscription-management-hub-toolkit.mac-ci` and `repo=<owner>/diy-llm-subscription-management-hub-toolkit`:

```sh
# Status
launchctl print "gui/$(id -u)/$label" | grep -E 'state|pid'
gh api "repos/$repo/actions/runners" --jq '.runners[] | {name, status, busy, labels: [.labels[].name]}'

# Restart, stop, start
launchctl kickstart -k "gui/$(id -u)/$label"
launchctl bootout "gui/$(id -u)/$label"
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$label.plist"

# Update the hook from a checkout of this repository, then confirm no drift
install -m 755 .github/runner/job-started-hook.sh "$HOME/github-runner/hooks/job-started-hook.sh"
shasum -a 256 .github/runner/job-started-hook.sh "$HOME/github-runner/hooks/job-started-hook.sh"
```

Re-register (service stopped first): create the token and configure in one shell so the token never reaches a command line, file, or output, then restore the runner files before starting the service again.

```sh
tok="$(gh api -X POST "repos/$repo/actions/runners/registration-token" --jq .token)"
ACTIONS_RUNNER_INPUT_TOKEN="$tok" ./config.sh --unattended --replace \
  --url "https://github.com/$repo" --name mac-ci --labels mac-ci --work _work
unset tok
printf '%s\n' "$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" > .path
printf 'LANG=en_US.UTF-8\nACTIONS_RUNNER_HOOK_JOB_STARTED=%s\n' "$HOME/github-runner/hooks/job-started-hook.sh" > .env
chmod 600 .credentials .credentials_rsaparams .runner
```

Remove: stop the service, run `./svc.sh uninstall`, then `tok="$(gh api -X POST "repos/$repo/actions/runners/remove-token" --jq .token)"; ACTIONS_RUNNER_INPUT_TOKEN="$tok" ./config.sh remove; unset tok`, and delete the runner root and `~/github-runner/hooks/`. If the local configuration is already gone, delete the registration with `gh api -X DELETE "repos/$repo/actions/runners/<id>"`, taking the id from the runner list.

Recover disk: stop the service, delete `_work`, and start it; the next run rebuilds without a cache. The runner is a user LaunchAgent, so after a reboot it starts only once the account has logged in.
