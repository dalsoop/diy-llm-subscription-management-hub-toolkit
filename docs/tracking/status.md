# Toolkit status

## Implemented capabilities

| Area | Current state | Verification boundary |
| --- | --- | --- |
| CodexBar usage UI | Provider-specific cards, account mini-meters, settings, refresh, and WidgetKit snapshot presentation are implemented. | Focused parser/model/UI test sources exist. No new application build or full runtime-suite pass is asserted here. |
| OpenCodex account bridge | Role-aware live/snapshot/linked reads, explicit switches, pending receipts, and stale-snapshot handling are implemented. | Parser, client-role, large-pool, account-card, and stale-usage regressions exist; live accounts are not verification fixtures. |
| Adaptive refresh/replay | Pure shared policy, optional consent-gated activity inputs, offline JSONL replay, and recorded schedule audit are implemented. | Offline policy/replay test targets exist; replay is not production telemetry collection. |
| Proxy and management | Bun-native routing/adapters, separate management admission, dashboard, service tools, and reduced hub-state projection are implemented. | Isolated Bun runner, typecheck, privacy, structure-map, and CLI-surface checks exist. Their existence is not a current full-suite pass. |
| Desktop/native UI | Tauri sidecar preparation, native tray, model layer, and widget sources are present. | Native tests are executable targets. Frontend compilation alone does not verify the installed app or signed update path. |
| Public documentation and source map | User docs and the existing subsystem ownership/contract registry are present. | Site-build and structure-map validation are distinct checks. |
| Root CI | The `macos` job runs only on the self-hosted Mac CI runner `mac-ci`; a runner-side hook admits only push, workflow_dispatch, and same-repository pull requests. Check and test hold host build slots. | The hook's admission cases were exercised against synthetic payloads on the installed copy. A run on the runner is evidence only for the exact head it ran on; fork pull requests get no macOS run, and a skipped fork job is not a pass. |

## Remaining work

1. Remote-workspace command execution on macOS/Windows remains unavailable pending a native confinement implementation that closes the platform authority boundaries. Existing file-tool access does not make command execution available.

No broader product roadmap, billing system, or new provider policy is assumed beyond the existing implemented behavior and explicitly approved work.

## Current verification limits

Documentation-only changes do not establish a fresh successful Swift application build, complete Bun suite, signed release, live provider login, or installed desktop validation. Required PR checks must be inspected on the exact head being merged. Runtime paths involving real accounts, Keychain, browser cookies, and service installation are deliberately outside routine offline verification.
