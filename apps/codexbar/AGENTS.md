# CodexBar application

## Scope

This Swift package owns the menu bar application, shared provider core, CLI, widget, Claude helper processes, and offline refresh replay. The menu bar application owns UI/settings/refresh coordination; it does not own OpenCodex's account store or server lifecycle. Keep changes focused and reuse existing typed helpers.

`Package.swift` is the target/dependency map. Build/package helpers live under `Scripts`; application bundles, root archives, and appcasts are generated output. Read-only release helpers resolve `MAC_RELEASE_TOOL` or the shared release tooling; publication remains CI/maintainer-owned, not a local development action. Nested release workflows are historical references in this toolkit.

## Swift patterns

- Four-space indentation, 120-column formatting, SwiftFormat/SwiftLint, and explicit `self` are intentional. Keep existing `MARK` organization and descriptive small structs/enums.
- Existing XCTest cases keep their suite/method idiom; Swift Testing tests use backticked sentences, not camelCase. Test/code model names are released names or unmistakably fictitious names.
- Prefer `@Observable` models with `@State` ownership and `@Bindable` views over introducing `ObservableObject`/`@ObservedObject`/`@StateObject`. Prefer modern macOS APIs when refactoring without silently raising the package deployment floor.
- Audit sibling `async let` tasks when one child is required and another best-effort. Prefer sequential awaits or a drained throwing task group that surfaces required failures and contains optional failures. `swift_task_dealloc`/`asyncLet_finish_after_task_completion` crash frames warrant checking nearby child lifetimes.

## Provider and credential boundaries

Never render one provider's identity or plan from another provider's data. A masked email is not an account merge key. Preserve the selected account source and usage timestamp through cached display and refresh failure.

Claude's user-configurable CLI status line is not a default usage parser. An explicitly enabled, default-off JSON statusLine feed is allowed only when clearly labeled as the person's own configured source and soft-failing on format drift.

Cookie import uses the shared browser order and `BrowserCookieAccessGate`: no background/settings prompts, host-matching cookie rows before Safe Storage access, at most one interactive Keychain read per manual action, denial cooldown on manual retries, and stop at the first validated session. Only explicit `codexbar cookie refresh --allow-keychain-prompt` overrides cooldown. A provider-specific browser subset needs a technical reason beside the code.

## Tests

Run from this component directory:

```sh
make test-fast FILTER='OpenCodexHubLargePoolTests'
make check
```

Select focused suites for the actual touched behavior; the example is not universal coverage. `make test` is the sharded full suite; a bounded parallel local run can use `./Scripts/test.sh --direct-workers 8` when resources permit. The full suite is not a foreground handoff blocker: use background execution or PR CI. Final code still needs focused coverage plus one `make check`; run formatting/lint on touched files while iterating and fix reported failures before handoff. Root `codexbar:check`, `codexbar:test`, and `codexbar:build` shortcuts delegate to this package.

Do not run a test/check/probe that can show a Keychain prompt. Live account usage, browser-cookie imports, or real SecItem reads require an explicit request; use parsers, stubs, test stores, and `KeychainNoUIQuery` instead. App-group migration tests inject dictionary defaults, both snapshot URLs, a synthetic home, and a contained recording FileManager. Unique defaults-suite names and Keychain flags alone do not isolate defaults/filesystem access. Ordinary settings tests must not discover shared defaults or run migrations.

Headless AppKit menus are brittle; use stable descriptor/state seams unless native wiring itself is under test. Test actual popup/container width when layout depends on native chrome, including cached-content reflow. Preserve full direct-test inventory, deadlines, failure behavior, cache validation, and clean fallback if changing runner mechanics. Reuse incremental builds within the worktree; never copy compiled products between worktrees. Clean build state only for diagnosed contamination, cold comparison, or requested cleanup. Repeat passing full checks only for relevant changes, failures/concerns, or a maintainer request.

## Packaging and UI proof

`swift build`/`swift build -c release` compile; `./Scripts/package_app.sh` refreshes `CodexBar.app`. `./Scripts/compile_and_run.sh` stops old instances, builds/packages/relaunches, and verifies the new app remains running; use it only for UI/runtime work. Prefer CLI/focused tests for parser/settings behavior rather than bundle-level live validation.

Validate UI changes against the freshly built bundle, not an existing background process. Capture the target screen before automation and verify the icon is visible; off-display `click-extra` coordinates and hidden menu extras are not proof. Widget/Tahoe issues use an appropriate macOS VM with screenshots/clicks when that environment is available. Keep UI screenshots linked as evidence, and PR summaries include commands/results and references.

Release publication stays with the authorized release process: wait for artifact/feed/tap handoff and never publish locally. `SPARKLE_PRIVATE_KEY` must match the existing AGCY public key in `.github/release.json`; another application's key is not a substitute. Do not introduce dependencies/tooling without confirmation.
