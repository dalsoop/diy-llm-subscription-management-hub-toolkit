# Engineering notes

## Cached data can look like a successful refresh

A hub snapshot can decode successfully while already stale. Promoting every successful read to fresh usage hides a stopped hub. Keep the hub write time attached, check freshness before publishing, and test that stale data cannot replace a current pool or clear its stale indication. A transient transport failure is different: retaining the same owner's old usage is useful only if its original time remains visible.

A linked installation can also return a plausible account list without being a hub. Resolve the runtime role first; test the client route with a local-list success and assert that no account-use command is executed. Masked emails may collide, so display identity must not substitute for a fresh target resolution.

## Migration tests can escape their synthetic settings

A unique UserDefaults suite name and Keychain suppression do not stop app-group migration from searching shared domains or touching real snapshot paths. Inject dictionary-backed defaults, both old/new snapshot URLs, a synthetic home, and a contained recording FileManager. Verify the recorded operations stay inside that home. Ordinary settings tests should not discover shared defaults or run app-group migration at all.

## Headless menus and actual popup width

Live status-bar/menu construction is unreliable in headless AppKit tests. Prefer a stable menu descriptor, account-section state, or hosted-row model unless the native wiring is the behavior being tested. Native popup chrome changes usable width: asserting only an inner SwiftUI preference width misses the clipping users see. Measure the actual hosted popup/container and verify cached content reflows without changing the selected account source.

## Required and optional Swift children

Sibling `async let` work is hazardous when one child is required and another is best-effort. Cancellation/error unwinding can obscure which child owns a failure. Stacks mentioning `swift_task_dealloc` or `asyncLet_finish_after_task_completion` warrant an audit of the nearby children. Prefer sequential awaits or a drained throwing task group that preserves required failures and contains optional ones; cover optional failure with a successful required result.

## Test discovery and SDK cleanup are separate outcomes

An Xcode discovery subprocess can produce valid test inventory and later encounter a read-only SDK-mount cleanup failure. Preserve successfully parsed discovery evidence rather than replacing it with an empty inventory. Diagnose mount/process cleanup separately; an empty inventory must not turn a test run into a vacuous success.

## Import-based test selection has blind spots

OpenCodex's changed-test selector follows parsed imports. A subprocess invocation, a source file read as text, or a derived/golden file is not an import edge. Select the corresponding regression file explicitly and inspect its result. Moving a test can expose state warmed by preceding cases; if a moved case changes result, check isolation before treating extraction as a behavior change.

The component's `test:changed` shortcut still names `dev` as its base. In this toolkit use an explicit valid `main` base when invoking the wrapper's changed option; a successful no-op against the wrong base is not coverage.

## Clean branches can fail when combined

An exhaustive locale/union consumer added on one branch can omit a member added by another. A file-size cap can also be exceeded only by the sum of two changes. Reconcile the merged member set, derive counts from registries, and re-run affected checks on the combined tree. Raising ratchet caps hides the problem; cohesive extraction retains the limit.

## Native packaging has two filesystem worlds

A Bun standalone executable has a virtual filesystem that cannot directly load the platform keyring `.node` addon. Keep the addon as an external packaged resource and verify the installed artifact resolves it there. Tauri sidecar/widget preparation precedes packaging; a successful frontend build alone is not evidence of a usable desktop bundle.

OpenCodex macOS tests are executables rather than XCTest bundles because the Command Line Tools environment lacks the required XCTest/Swift Testing runtime. Run the named package executable instead of assuming `swift test` covers it. The widget's Swift entry and extension linker entry are both required; removing either can leave a buildable but non-loadable extension.

## UI proof can exercise yesterday's binary

A running menu bar process survives a rebuild and can make a correct source change appear absent. Package and explicitly relaunch the newly built bundle before capturing proof. Capture the screen before automation; a hidden menu extra or an off-screen coordinate is not a successful UI interaction. Parser/settings changes generally need focused tests, not a live provider or app relaunch.

## A workflow condition does not keep forks off the self-hosted runner

A fork pull request runs the workflow file from the fork's own head, so the `if:` and `runs-on` lines GitHub evaluates are whatever the fork wrote, and they can name the registered runner's labels. The `macos` job's fork condition only turns an honest fork's run into a skip. The runner's job-started hook (run before any step, from a path set in the runner's `.env`) fails a refused job, yet GitHub's runner still executes steps marked `if: always()` after that failure, so a fork that adds such a step runs its code anyway. The boundary is the repository's approval policy for outside contributors' runs; the hook is a second layer. Lowering the approval policy back to first-time contributors, or approving a fork run at all, puts fork code on the machine while the workflow and hook still look protective; an approval never yields macOS CI, because the fork condition skips an unchanged fork workflow and the hook refuses one without it. After any runner maintenance, confirm the policy reads `all_external_contributors` and the next run's "Set up runner" log contains `job-started-hook: admitted <event>`.

## Runner configuration rewrites the job PATH and environment

The runner's `config.sh` calls the vendor `env.sh`, which overwrites `.path` with the calling shell's `PATH` and appends variables from that shell (such as `LANG`, `JAVA_HOME`, `NVM_BIN`, `LD_LIBRARY_PATH`) to `.env` when they are not already there; a freshly unpacked runner root has no hook line in `.env` at all. A configuration run over a non-login ssh shell therefore leaves jobs with a `PATH` that puts `/usr/bin` first (the system Python 3.9 instead of Homebrew's, and possibly no `build-pipeline`) and a `.env` that no longer holds exactly its two documented lines. Rewrite `.path` and `.env` after every `config.sh`, before the LaunchAgent starts, and set the credential files back to mode 600; the next run's "Require build slot tool" step and hook admit line confirm both.
