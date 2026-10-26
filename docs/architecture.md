# System composition

## Toolkit boundary

The toolkit combines a usage-display application with a separately running provider proxy. CodexBar is not the proxy's credential store, and OpenCodex does not require the menu bar application to route requests. Their integration exchanges account-display projections and explicit account-switch requests, not a shared in-process account model.

| Component | Responsibility and dependency direction |
| --- | --- |
| `apps/codexbar` | Swift macOS menu bar application; coordinates settings, refresh, account selection, and presentation through `CodexBarCore`. |
| `apps/codexbar/Sources/CodexBarCore` | Provider acquisition, parsing, usage models, and snapshot support shared by the application, CLI, and widget. Does not depend on the menu bar application. |
| `apps/codexbar/Sources/CodexBarCLI` | Command-line entry into the shared provider core; not a separate implementation of quota parsing. |
| `apps/codexbar/Sources/CodexBarWidget` | WidgetKit presentation of app-written snapshots; does not own provider polling. |
| `apps/codexbar/Sources/CodexBarClaudeWatchdog` | Separate process supervising a Claude child process; process lifetime is outside UI ownership. |
| `apps/codexbar/Sources/CodexBarClaudeWebProbe` | Explicit diagnostic executable using the shared Claude web-fetching core. |
| `apps/codexbar/Sources/AdaptiveRefreshCore` | Foundation-only refresh decision table used by production and offline replay. No dependency on provider acquisition or UI. |
| `apps/codexbar/Sources/AdaptiveReplayKit` and `AdaptiveReplayCLI` | Caller-supplied trace parsing, simulated schedules, and reports; depend on the pure policy core, not the running application. |
| `packages/opencodex/src` | Bun-native proxy, configuration, account/OAuth management, adapters, service lifecycle, and CLI. No separate server compilation is required. |
| `packages/opencodex/gui` | React/Vite dashboard consuming the proxy management API; packaged `dist` is served by the proxy. |
| `packages/opencodex/desktop` | Tauri shell connecting to the local proxy, preparing its sidecar, and linking macOS native tray support. It does not replace the server's routing owner. |
| `packages/opencodex/app` | Swift native tray, shared menu bar models, and WidgetKit extension for the OpenCodex desktop shell. This is distinct from the CodexBar application and its widget. |
| `packages/opencodex/native/remote-workspace-helper` | Versioned subprocess protocol for command-confinement capability checks and execution requests. Current macOS/Windows backends refuse command execution. |
| `packages/opencodex/scripts` | Isolated test orchestration, package preparation, release tooling, and maintenance checks. |
| `packages/opencodex/docs-site` | Astro/Starlight public documentation source; generated site output is not runtime configuration. |
| `packages/opencodex/structure` | Existing subsystem contract/source map and its generated index; not a runtime dependency. |

## Proxy request flow

A Codex or Claude client sends an HTTP request to the OpenCodex listener. The request enters endpoint-specific admission, configuration/model resolution, routing, and the selected adapter or native passthrough. The adapter translates requests and upstream events into the client protocol; cancellation and upstream failures return through the same request boundary. Responses, Chat Completions, and Messages share routing infrastructure but are not interchangeable wire formats. Live/Realtime transports have their own relay path rather than being treated as ordinary response bodies.

The same server hosts dashboard files and management routes. `/v1/*` carries client data-plane traffic; `/api/*` carries management operations. A linked client obtains the hub's bounded capability projection from `/v1/hub-state` instead of treating its empty local credential store as the hub's state. Provider credentials remain at the provider/account owner; the hub-state response conveys presence and supported models, not credential values.

Optional Compatibility Lab services attach through core-owned registration slots. The server composition root can know about optional services; the default routing/lifecycle/Responses path must not acquire a transitive Lab dependency merely by importing the core.

## Account-display flow

CodexBar resolves the OpenCodex runtime role before choosing an account source. A hub or standalone installation can execute a live account-list command. A client prefers a synchronized snapshot and may use a linked read-only account list when that snapshot is unavailable. An unknown role uses snapshots only. Account rows become provider-specific quota lanes and account cards; the UI does not import proxy credentials.

For a direct switch, CodexBar refreshes the live list, resolves the selected display row to its current full ID, and asks OpenCodex to switch. For a synchronized client, it publishes a bounded JSON request beside the snapshot; the hub owns the eventual action and receipt. A local linked list is not a switch authority. The HTTP hub-state capability projection and this account-usage file are different interfaces and must not be parsed as the same schema.

## External systems and storage

Provider services, browser sessions, OAuth endpoints, local provider CLIs, and OS credential stores are acquisition dependencies, not fixtures for normal tests. CodexBar uses its own settings, caches, app-group snapshots, and optional plugin runtime. The embedded QuickJS sources and system SQLite linkage are dependencies rather than independent toolkit services.

OpenCodex owns its configuration/account state under `OPENCODEX_HOME`; `CODEX_HOME` belongs to the Codex client. Client-configuration changes pass through ownership and restore-journal mechanisms so uninstall/recovery does not erase unrelated user state. Tauri packaging carries generated sidecars and external native keyring resources; a Bun compiled executable cannot load a native `.node` addon directly from its virtual filesystem.
