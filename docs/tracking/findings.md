# Unresolved discrepancies

## Standalone integration and automation instructions versus toolkit execution

The inherited OpenCodex instructions describe `dalsoop/opencodex`, feature PRs into `dev`, maintainer promotion to `main`/`preview`, fast Ubuntu PR checks, and manual/release-line cross-platform runs. The toolkit's existing root instructions instead select `dalsoop/diy-llm-subscription-management-hub-toolkit` and `main`; its active root CodexBar workflow runs macOS checks for matching PR paths. Nested workflows do not execute merely because they are committed under a component.

Following the inherited standalone policy literally can publish to the wrong repository, target a nonexistent integration line, or mistake a reference workflow for actual CI evidence. The legacy policy is not rewritten into a new toolkit branch/automation policy by assumption. Resolving all inherited maintainer, contributor, release, and workflow material is outside a documentation-only preservation change and needs a dedicated policy review. Current toolkit deliveries continue using the already-established root destination and actual root checks; no workflow or protection setting is changed here.

## Test shortcuts do not all provide the same isolation

The root `package.json` command `opencodex:test` invokes raw `bun test --cwd packages/opencodex`, while the component's `test` script invokes `scripts/test.ts` and constructs isolated provider homes, credential environment, and subprocess cleanup. Older source instructions also suggest raw focused `bun test` invocations. Likewise, `test:changed` still defaults to `dev` rather than this toolkit's `main`.

Treating these commands as interchangeable can run with inherited local account context or compare against the wrong base. Changing script behavior is outside the current documentation-only scope. Use the existing component wrapper with explicit test files or an explicit valid changed base; a follow-up can align the shortcuts and their tests without weakening isolation.

## Historical platform and verification claims

The desktop README mentions a macOS 13 minimum, while the separate native app Swift package declares macOS 14. These are not proof that every packaged native component runs on macOS 13. Older OpenCodex instructions also record a historical container failure count and advise not reinvestigating those failures; that observation is not current exact-head verification.

Release/support claims and test-result claims can be overstated if copied without reproducing the relevant package/platform. A documentation-only change cannot settle deployment compatibility or certify historical failures as harmless. Validate the assembled desktop artifact on the claimed minimum OS before changing its support promise; evaluate any present failure from its actual output rather than importing an old pass/fail count.

## Source interpretations resolved without behavior changes

Independent migration review rejected two draft interpretations; these are corrected documentation discrepancies, not outstanding runtime defects:

- Fixed gaps in standard quota lanes were not implemented. `OpenCodexHubUsageProjection.snapshot` compacts available five-hour, weekly, and monthly windows into primary/secondary/tertiary while retaining duration classifications. `TestsLinux/OpenCodexHubPoolTests.swift` covers weekly-only and monthly-only primary windows. The business rules now describe compaction, not synthesized zero measurements or reserved empty lanes.
- A missing switch receipt does not always mean pending. `OpenCodexHubPendingSwitch.resolution` first honors a matching terminal receipt, otherwise returns done for a matching observed active suffix and masked email, expired after strictly more than eleven minutes, and pending otherwise. The same fixture suite covers receipt precedence, observed completion, pending, and expiry. The interface contract now distinguishes observation from a request-specific receipt without changing authorization or resolver behavior.

The source instructions also now distinguish reviewing all mapped documents from editing only changed explanations, and use an explicit toolkit-main comparison rather than the inherited `dev` shortcut. The package-script discrepancy above remains unresolved; no source, script, or workflow was changed to satisfy prose.
