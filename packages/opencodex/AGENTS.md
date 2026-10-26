# OpenCodex component

## Scope and delivery

OpenCodex (`ocx`) owns the Bun-native provider proxy, account/configuration management, CLI, dashboard, and desktop companion. It does not own the separate CodexBar application's settings or provider identities. Deliver toolkit changes in `dalsoop/diy-llm-subscription-management-hub-toolkit`, targeting `main`; historical standalone destinations do not authorize publishing upstream or adding an upstream remote.

The inherited standalone material describes `dev` integration, `main`/`preview` release promotion, and a different CI policy. Those claims are not the toolkit's executable workflow configuration. Keep the disagreement visible rather than changing workflows, branch protection, or publishing policy to make the inherited descriptions true. Only the root toolkit workflows execute here.

## Runtime and test layout

- The server runs Bun-native TypeScript without a separate compilation step. Native desktop/helper code augments it; do not revive the retired `go/` full-runtime experiment.
- `tests/` mirrors source domains. Put new tests in the owning domain, with at most the existing extra vendor level for providers/adapters. Register new/moved tests in the explicit layout map (or domain shard) and expected fixture shard. Only the two layout guards belong at test-root level.
- Source-oracle tests use `tests/helpers/repo-root.ts` helpers (`repoRoot`, `repoPath`, `helperPath`, `fixturePath`), not an assumed `import.meta.dir + "/.."`.
- GUI packaged output and sidecar/native resources are generated. Native Swift tests are named executable products, not XCTest bundles.
- Review all structure-map documents for a changed source area. Several documents may describe the same area. Update the authority when a shared contract changes and a dependent only when its own explanation changes; unchanged accurate prose need not be copied.

## Optional subsystems

A one-provider/model installation with no Lab configuration must execute no Lab code or timers. `src/router.ts`, `src/server/lifecycle.ts`, and `src/server/responses/core.ts` may not reach `src/lab/` directly or transitively. `tests/lab/core-lab-boundary.test.ts` walks the runtime graph; indirect helper chains count.

Optional services register at activation through core-owned slots such as `src/server/passive-route-linker.ts`, `src/routing/compatibility/provider-slot.ts`, and `src/lib/optional-shutdown-hooks.ts`. The composition root `src/server/index.ts` can import optional services but must gate activation with `labActivationRequired`. Everything from `Bun.serve` through that activation and return stays synchronous: an await would let synchronous fallback routing execute before its evidence provider exists. Preserve both graph and synchronous-start regression checks.

## Security and consent

Never log or commit credentials, real account data, request bodies, authentication headers, or private paths. Unreleased security findings, severity assessments, exploit/reproduction reasoning, draft advisories, and pre-disclosure plans stay in ignored task-owned scratch space, not `devlog/`, `structure/`, a public site, or a private repository. Maintainer status is not an exemption. Published fixes/regressions/advisories and already-public outcomes may enter history.

An agent must never perform or auto-answer actions spending the person's identity, reputation, or credits, including repository starring. Preserve enforcement in the CLI and management action paths, with the startup-prompt, agent-driven, and sidebar-route regressions. A dashboard-session requirement blocks the casual admin-token-only path but does not prove human initiation: a determined process running as the person can obtain local bootstrap credentials. The consent rule binds the agent even when the mechanism is reachable.

Authentication/OAuth, credential handling, management/CORS, dependencies, workflow automation, and release/signing changes require explicit security review. Release/publish/deploy/version-bump actions additionally need explicit task authorization and the owning maintainer policy. `scripts/release.ts` remains the release authority; normal development is not permission to run it.

## Commands

Run from this component directory:

```sh
bun run typecheck
bun run test tests/lab/core-lab-boundary.test.ts
bun run test
bun run privacy:scan
bun run structure:check
bun run skill:surface:check
```

Use the isolated `test` wrapper, not raw tests against inherited homes. The focused example is for optional-boundary work; select the actual affected regressions for other changes. The inherited `test:changed` script compares to `dev`; use `bun run test --changed=origin/main` for this toolkit when that ref is available. Import selection misses subprocess/source-as-data/golden dependencies, so run those files explicitly.

The full suite is the default before a non-trivial PR is review-ready. A proportional resource exception still requires focused regressions, its reason, exact commands/results, and remaining CI coverage in the PR. Run typecheck before readiness. If focused coverage is unreliable, keep the PR in draft until broader validation is available. Do not rerun passing checks on unchanged inputs merely to prepare a report. Historical container failure lists are not permission to disregard a present failure.

Run privacy checks when configuration, credentials, requests, logs, account data, or fixtures change. `bun run prepush` is an explicit comprehensive check, not an automatically installed hook. After pushing, inspect exact-head required checks; missing, skipped, cancelled, awaiting-approval, and older-head results are not passes.

CLI operating material under `skills/ocx/` is generated in part from `src/cli/capabilities.ts`. Regenerate with `bun run skill:surface` after surface changes and check it; do not document a command absent from the registry. Structure index output is generated from its manifest, not hand-edited.

## Merge and review traps

File-size ratchet caps only decrease. Extract a cohesive sibling rather than raise a cap, and register extracted tests in both layout/expected maps. A moved case may have depended on state warmed by earlier tests; verify it in isolation rather than weakening its assertion.

Reconcile exhaustive unions, locale catalogs, and counts against the combined branch state. Two individually green branches can exceed a cap or omit each other's newly added member. Derive inventories/counts from canonical registries rather than copying a plausible total.

PR descriptions retain Summary, Verification, and Checklist. GUI changes include linked screenshot evidence, not committed screenshot bundles; link the issue when applicable. Carried/reimplemented work needs its original author's coauthor trailer. Do not apply historical standalone branch-enforcement automation as if it runs at the toolkit root.

Reviews are specific and English: name file/line, failure mode, and correction. Prioritize secret exposure, token serialization/logging, workflow privilege changes, and mutable third-party actions as blockers. Runtime behavior changes need focused regressions; user-facing changes update public documentation without contradictory translations.

## Historical working records

`devlog/` is ordinary tracked history, not a submodule or private mirror. Open planning, closed public outcomes, and external comparison material retain their existing subdirectories. Reference clones remain ignored; no gitlinks or previously removed security triage may reappear. Build/typecheck/tests do not consume devlog; privacy checks do.