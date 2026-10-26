# DIY LLM Subscription Management Hub Toolkit

This toolkit combines the Swift CodexBar usage/account menu bar app with the Bun-native OpenCodex provider proxy, dashboard, and desktop companion. It serves people managing several provider subscriptions and linked hub/client installations; it is not a shared credential pool across unrelated provider identities.

## Project structure

```text
.
├── AGENTS.md                         → shared agent entry point
├── CLAUDE.md                         → identical Claude entry point
├── .github/
│   ├── workflows/codexbar.yml        → active root CI on the self-hosted macOS runner
│   └── runner/job-started-hook.sh    → runner-side job admission (installed on the CI machine)
├── docs/
│   ├── architecture.md               → components, boundaries, and request/data flow
│   ├── business-rules.md             → identity, quota, freshness, and account transitions
│   ├── security.md                   → admission, consent, credentials, and sensitive data
│   ├── standards.md                  → delivery, dependency, and verification rules
│   ├── engineering-notes.md          → failure mechanisms and regression traps
│   ├── operations.md                 → setup, isolated checks, builds, and authorized operation
│   ├── contracts.md                  → HTTP, CLI, snapshot, and subprocess interfaces
│   └── tracking/
│       ├── status.md                 → implemented scope, remaining work, verification limits
│       ├── findings.md               → unresolved source/instruction discrepancies
│       └── decisions/
│           ├── index.md              → decision inventory
│           ├── 0001-hub-capability-projection.md → least-privilege linked-client reporting
│           ├── 0002-optional-lab-registration.md → optional activation and synchronous startup
│           ├── 0003-native-test-executables.md → native coverage without test-bundle runtimes
│           └── 0004-self-hosted-macos-runner.md → self-hosted CI runner and fork refusal
├── apps/
│   └── codexbar/
│       ├── AGENTS.md                 → menu bar application, Swift package, and safe validation
│       └── Sources/
│           ├── CodexBarCore/AGENTS.md → shared provider parsing, stores, and account bridge
│           ├── CodexBarCLI/AGENTS.md  → command arguments and provider-core output
│           ├── CodexBarWidget/AGENTS.md → snapshot-only WidgetKit presentation
│           ├── CodexBarClaudeWatchdog/AGENTS.md → child lifetime and termination
│           ├── CodexBarClaudeWebProbe/AGENTS.md → explicit diagnostic, not a test probe
│           ├── AdaptiveRefreshCore/AGENTS.md → pure production/replay policy
│           ├── AdaptiveReplayKit/AGENTS.md → offline traces and simulated metrics
│           └── AdaptiveReplayCLI/AGENTS.md → replay command and reports
└── packages/
    └── opencodex/
        ├── AGENTS.md                 → proxy package, optional boundaries, and isolated tests
        ├── src/AGENTS.md             → runtime/adapters/configuration/management implementation
        ├── gui/AGENTS.md             → dashboard, translations, and accessibility
        ├── desktop/AGENTS.md         → Tauri lifecycle and packaged resources
        ├── app/AGENTS.md             → native tray, model library, widget, executable tests
        ├── native/
        │   └── remote-workspace-helper/AGENTS.md → bounded protocol and confinement refusal
        ├── docs-site/AGENTS.md       → public user documentation and translations
        ├── scripts/AGENTS.md         → release/maintenance safety and test orchestration
        ├── structure/AGENTS.md       → existing source map and contract-validation rules
        └── .github/AGENTS.md         → reference automation, not active toolkit workflows
```

## Hard gates

1. Keep provider/account identities isolated. Never show one provider's identity/plan as another's or treat display emails as credential/account authority.
2. Never commit credentials, real account data, host-specific configuration, or compiled app bundles. Unreleased security material stays in ignored scratch space.
3. Use isolated test runners and synthetic data. No real-account, cookie, or prompt-producing Keychain probes without explicit authorization.
4. Deliver toolkit work here through PRs targeting `main`; historical standalone forks are history, not publishing authority. GitHub executes only root workflows.
5. Release/publish/deploy/signing and actions spending a person's identity, credits, or reputation require their explicit authorization; reachable local credentials do not imply consent.

## Before editing

Read `docs/standards.md`, `docs/engineering-notes.md`, and the relevant component instructions. Stage only current-task paths and never revert another contributor's work.

- For account/usage UI or refresh changes, read the identity/freshness/switch rules and the OpenCodex bridge implementation before choosing display or activation behavior.
- For authentication, OAuth, management, CORS, cookie access, or credential logging, read the security policy and existing admission/access-gate patterns; obtain explicit security review.
- For shared OpenCodex source, inspect its existing structure manifest/index and every mapped subsystem contract before editing; a source area can have several owning explanations.
- For GUI copy, inspect the canonical locale, all locale modules, and existing design-system contracts; machine text is not a translation label.
- For test-runner or CI work, inspect the root workflow, the runner-side admission hook and the self-hosted runner's operating rules, isolated environment setup, direct-test inventory, and cache/fallback checks. Nested workflows are not active CI evidence.
- For release or installed-app work, inspect the owning release/preparation scripts and maintainer policy before running a command; a plain build is not signed or installed proof.

Root shortcuts are `bun run codexbar:check`, `bun run codexbar:test`, and `bun run codexbar:build`. OpenCodex isolated tests use the component's `bun run test` wrapper, not the root raw-test shortcut.

## Problem routing

Report provider/account identity leakage, admission bypass, credential disclosure, unintended account switching, or destructive client-configuration recovery to the user immediately. Keep unreleased security details out of tracked findings. Record other unresolved product problems in `docs/tracking/findings.md` with a reproducible condition, impact, and why they cannot be fixed in the current scope. Do not turn an unrelated observation into an unrequested code change.
