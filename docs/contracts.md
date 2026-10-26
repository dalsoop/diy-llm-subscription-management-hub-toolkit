# Consumer interfaces

## HTTP access conventions

Client inference uses the configured proxy origin and `/v1/*`. Management uses `/api/*` with separate management admission, not the provider API key. The dedicated data-plane header is `x-opencodex-api-key`. When authentication is required, a valid dedicated header takes precedence over a bearer; an invalid dedicated value does not fall through to a different credential.

| Data-plane endpoint | Methods / input | Accepted admission headers |
| --- | --- | --- |
| `/v1/responses` | POST Responses JSON (`model`, `input`, optional `stream` and supported tool/options fields). | Dedicated header or proxy-owned bearer; not `x-api-key`. |
| `/v1/chat/completions` | POST Chat Completions JSON (`model`, `messages`, optional `stream`). | Dedicated header or proxy-owned bearer; not `x-api-key`. |
| `/v1/messages` | POST Anthropic Messages JSON (`model`, `messages`, `max_tokens`, optional `stream`). | Dedicated, bearer, or `x-api-key`. |
| `/v1/models`, `/v1/catalog` | GET model/catalog discovery; no request body. | Dedicated, bearer, or `x-api-key`. |
| `/v1/hub-state` | GET or HEAD; no request body. | Dedicated, bearer, or `x-api-key`. |
| `/v1/usage` | GET usage attributed to a configured API-key identity. | Dedicated configured key only; an unscoped environment key is insufficient. |
| `/v1/audio/transcriptions` | POST audio transcription request. | Dedicated, bearer, or `x-api-key`. |
| `/v1/live`, `/v1/realtime/calls` | Live/Realtime transport setup rather than an ordinary inference JSON response. | Dedicated, bearer, or `x-api-key`. |

A proxy-owned bearer is substituted with the selected upstream credential, never forwarded as provider authentication. A caller-owned native Codex bearer is a separate passthrough credential and is not itself remote proxy admission. Cross-origin admission remains subject to the configured origin policy. Loopback data-plane configuration can make authentication unnecessary; consumers must not infer that management shares this exception.

Inference returns the corresponding client protocol's nonstreaming JSON or streaming event representation, not one common DTO. Responses events, Chat Completions chunks, and Messages events must be consumed according to the requested protocol; disconnect/cancellation is not an extra successful completion. Provider support varies by adapter/model; a model name alone does not promise image, tool, audio, or live support.

Formatted proxy errors use JSON `{ "error": { "type": "...", "message": "...", "code": "..." } }`; `code` is a classified machine value and clients must not assume arbitrary upstream codes survive. Missing required data admission returns 401 with the message `opencodex API key required`. Invalid request/unsupported input, origin refusal, upstream failure, and quota refusal are not interchangeable; use the status and classified code instead of parsing message prose. Preserve bounded `Retry-After` when supplied. A deterministic replay refusal is not permission to automatically replay a request that may already have spent quota. Management/bootstrap failures can instead use a simple `{ "error": "..." }` body; do not impose the inference error schema on every administrative response.

## Liveness and readiness

`GET /healthz` returns 200 JSON with `status: "ok"`, `service: "opencodex"`, version, uptime, PID, actual listener port, and supported local capability versions. It is unauthenticated and confirms identity/liveness, not readiness. A foreign server's 200 response is not evidence of an OpenCodex process.

Exact `GET /readyz` returns identity/version/uptime/PID/port and `status`. `ready` returns 200; `pending` or `failed` returns 503 with `Retry-After: 1`. Draining reports pending. It exposes sanitized readiness, not sync messages, account data, or catalog paths. A trailing slash or another method returns a JSON 404 rather than GUI fallback. A package-tree guard can fence normal service behavior, including health responses; callers must not treat a non-OK fence as ready.

## Hub capability projection

An admitted `GET /v1/hub-state` returns schema version 1:

```json
{
  "schemaVersion": 1,
  "runtimeRole": "hub",
  "hubVersion": "example-version",
  "origin": null,
  "providers": [],
  "oauth": [],
  "subagentModels": [],
  "truncated": false,
  "claudeCode": { "enabled": false }
}
```

Provider rows contain `name`, `adapter`, `authMode` (`key`, `forward`, `oauth`, `local`, or null), `hasCredential`, and `disabled`. Current hubs omit disabled providers. OAuth rows contain only `provider` and `loggedIn`, not emails or IDs. `origin` is the explicitly configured public data origin or null. Unknown fields are ignored for forward compatibility; malformed required fields/version/role are rejected by consumers rather than replaced by local account state.

The projection is bounded to 64 KiB, 200 provider rows, 200 OAuth rows, and 32 featured subagent models, with bounded strings. `truncated: true` means the lists are a prefix, not the complete inventory. HEAD returns no body. Admission failure is 401, rejected origin is 403, and an admitted request to a non-hub role returns 404. This response is not the account/quota snapshot consumed by CodexBar.

## Dashboard provider inventory

`GET /api/providers`, with valid management admission, returns an array of provider configuration summaries: name, adapter, sanitized base URL, model/default-model metadata, disabled state, auth mode, and presence flags such as `hasApiKey` and `hasHeaders`. Header names/values and API-key values are not returned by this inventory. Stored-key reveal is a separate, stronger-session operation. Invalid management credentials are refused; unavailable protected admin state fails closed. Browser mutations additionally require the session's origin and CSRF binding; a data-plane token is not an administrative credential.

## Account CLI bridge

CodexBar invokes a configured OpenCodex executable with argument arrays, never shell interpolation. Provider names are `anthropic`, `openai`, and `xai`, displayed as Claude, Codex, and Grok respectively.

| Invocation | Input / result | Errors |
| --- | --- | --- |
| `ocx status --json` | Runtime role used to choose hub, standalone, client, or unknown behavior. | Unresolved role does not authorize a direct account switch. |
| `ocx account list <provider> --quota --json` | JSON object with an `accounts` array; live quota acquisition for the owning hub/standalone route. | Non-JSON/object, missing array, malformed row, missing active flag, or multiple active rows is rejected. |
| `ocx account list <provider> --json` | Read-only list used for a linked client; not a direct-switch authority. | Command failure is not an empty successful pool. |
| `ocx account use <provider> <id> --json` | Success receipt `{ok: true, provider, type, activeId}`; `activeId` must match the freshly resolved target. | Non-OK/malformed receipt or mismatched active ID fails the operation. Never invoked locally on a client. |

Rows carry `id` for the live list, `active`, optional masked `email`/`label`, paused/reauth/health fields, and optional quota. Quota fields are `fiveHourPercent`, `weeklyPercent`, `monthlyPercent`, their corresponding `*ResetAt` fields, optional `updatedAt`, and additive `customWindows` entries `{label, percent, resetAt}`. Finite percentages are clamped to 0–100; malformed custom rows are skipped. Timestamps accept ISO 8601 or numeric epoch values (seconds below 100 billion, otherwise milliseconds). Provider-mismatched rows are excluded. Invalid/duplicate live IDs retain display rows without a usable switch target.

The reader's default subprocess timeout is thirty seconds and captured output is bounded to 262144 bytes. Missing executable, timeout, oversized output, or invalid shape remains an explicit read error, not fresh usage.

## Synchronized account snapshot and switch request

The account snapshot envelope contains `app`, `updatedAt`, and `state`; an unwrapped state is also readable. Current state has provider-keyed pools under `providers`, each with `accounts`, `switchable`, and optional `switchReason`, plus `lastRequests`. Snapshot account rows use `idSuffix` rather than full IDs. Legacy Anthropic-only `accounts` snapshots remain readable but are not switchable. The reader rejects oversized/non-object/malformed snapshots. It preserves the writer's time; reading does not renew freshness.

A remote switch publishes `<requestId>.json` in the adjacent `opencodex-hub-requests` directory:

```json
{
  "schemaVersion": 1,
  "requestId": "synthetic-request",
  "provider": "anthropic",
  "targetIdSuffix": "demo",
  "targetEmail": "synthetic-display-value",
  "requestedAt": "2026-01-01T00:00:00Z"
}
```

The request ID is 1–64 ASCII letters/digits/hyphens. Suffix and display email must be nonempty; the whole request is at most 4096 bytes. Directory mode is 0700, file mode 0600; a hidden temporary file is renamed atomically into the visible request. No full ID or credential is sent. Invalid request IDs, empty targets, oversized JSON, or filesystem failure prevent publication.

Terminal receipts arrive asynchronously in `lastRequests` as `requestId`, optional provider, `result` (`done`, `refused`, `failed`), optional code/reason/time. Within the provider's parsed pool, a matching request-ID receipt takes precedence. Without one, the pending-switch resolver returns `done` when the observed active account matches both the requested ID suffix and masked email; otherwise it returns `expired` when request age is strictly greater than eleven minutes, and `pending` in the remaining case. Observing the target as active is distinct from receiving a request-specific success receipt; neither grants target authorization or proves which action activated it. Display bounded refusal reasons without treating them as account identifiers.

## Offline refresh replay

`AdaptiveReplayCLI <trace.jsonl> [--policy <name>] [--json] [--gap-grace <seconds> | --raw-wall-clock]` reads an existing caller-supplied trace and emits a comparison table or JSON report. Repeat `--policy` to select several; absent selection runs all supported policies (`adaptive`, `adaptive-activity`, fixed two/five/fifteen/thirty minutes, and `manual`). Invalid policy/arguments, a negative or non-finite grace, unreadable input, or a strict parse failure is an error, not a partial successful analysis. The tool does not discover sessions, capture traces, call providers, or change production refresh settings. Counterfactual refresh timing and excluded legacy gaps are reported separately from recorded schedule audit.

## Remote-workspace helper subprocess

The helper reads one JSON object from stdin until EOF and writes one JSON response plus newline to stdout. Version is 1; requests are at most 64 KiB and unknown fields are rejected. `probe` carries no command authority. `run` accepts absolute `root`/`cwd`, a nonempty argument vector, optional toolchain roots, `timeoutMs` from 1 through 60000, `maxOutputBytes` from 1024 through 262144, and `networkAccess` (default false). Shape validation does not itself grant confinement authority.

Responses contain `version` and `ok`. Probe success adds `probe: true`; run success adds `exitCode`, `stdoutBase64`, and `stderrBase64`. Failure adds a bounded `error` and `ok: false`. Unsupported versions/operations, invalid/oversized requests, and unavailable platform confinement return failure JSON; inability to write the response exits 2. Current macOS and Windows confinement backends refuse commands and probes. File-tool availability is separate; clients must not fall back to unconstrained shell execution.
