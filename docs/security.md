# Security policy

## Protected assets

Provider credentials, browser cookies, Keychain items, OAuth refresh/access tokens, proxy admission secrets, account identifiers, request contents, and private filesystem paths are sensitive. Commits must contain none of these, no real account fixtures, no host-specific configuration, and no compiled application bundles. Account-display snapshots are reduced projections, not a channel for transferring provider secrets.

Unreleased security findings, reproduction steps, exploit reasoning, draft advisories, and pre-disclosure patch plans stay in task-owned ignored scratch space. A private repository is not an embargo boundary. Only a public fix, regression test, published advisory, or already-disclosed outcome belongs in tracked history. Maintainers and agents follow the same rule.

## Admission and failure paths

Data-plane and management admission are different credential domains. The configured data token, protected service token, and configured API keys admit client traffic according to the endpoint. A loopback data listener may operate without requiring a token; this is not a loopback management bypass. A proxy admission secret must never be forwarded as an upstream provider credential. A caller-owned Codex bearer and a proxy-owned admission bearer must be distinguished before passthrough.

Management uses a separate configured admin token or protected generated admin token. Reusing a data-plane credential as the management secret must not grant management access. Admin-secret initialization validates the directory and file type, rejects symlinks, restricts permissions, and requires platform hardening. Invalid material, unsafe storage, or hardening failure makes management unavailable rather than falling back to anonymous access.

A browser bootstrap/pairing flow issues a short-lived session bound to server and browser origin. Admission checks the session, expiry, server origin, browser origin, and mutation CSRF value. A missing/expired session or any failed binding is refused. Local sessions expire after five minutes; remote sessions after twelve hours. Pairing grants expire after five minutes, have bounded capacity and attempt limits, and cannot become unlimited reusable credentials. The process bounds live sessions to 128.

Trusted hub-management ingress is an explicitly configured listener/context. A forwarded header by itself is not evidence of trusted ingress or identity. A dashboard session cannot authenticate arbitrary data-plane traffic.

| Subject | Permitted action and condition | Explicitly forbidden |
| --- | --- | --- |
| Data-plane caller | Client inference/catalog operations with the endpoint's accepted admission and key scope. | Using a data credential to administer accounts or forwarding it upstream. |
| Management caller | Administrative operations with valid separate management admission. | Anonymous loopback bypass; treating an admin token alone as human consent. |
| Dashboard session | Management actions while origin, expiry, and mutation-CSRF checks pass. Stronger paired/trusted-identity issuance is required for stored-key reveal. | Using a generic session to reveal stored keys or to access arbitrary data-plane routes. |
| Scoped native/bootstrap capability | Its single permitted operation, bound to method, path, nonce, process, port, and expiry; account-switch authority also binds the request body digest. | Replaying the capability or reusing it for another target/body. |
| Linked client | Read reduced hub state and submit the supported explicit switch request. | Claiming local cached accounts are switch authority or exporting full hub credentials. |
| Background provider refresh | Noninteractive access allowed by its source and credential policy. | Opening a browser-cookie or Keychain consent prompt from background/settings work. |
| Operating agent | Repository and runtime work within the person's instructions. | Auto-consenting to actions that spend the person's account identity, credits, or reputation. |
| CI job on the self-hosted runner | Build and test this repository's own code for `push`, `workflow_dispatch`, and same-repository `pull_request` events, holding host build slots. | Running fork pull-request code; any `pull_request_target`, `issue_comment`, or `workflow_run` job on the runner; pushing to the repository; reading credentials beyond what the build and tests need. |

## Credential lifecycle

Generated management secrets use cryptographically random material and protected files: private state directories use mode 0700 and token files mode 0600, with platform hardening required where applicable. Creation uses exclusive temporary output and no-replace publication, and a concurrent existing file is revalidated. An environment-provided admin secret is operator-owned; it must not be copied into examples, diagnostics, or history.

Provider OAuth lifetimes and remote revocation are provider-owned; there is no universal provider-token expiry or rotation interval. Use the account's reauthentication/removal flow rather than editing credentials into source files. Removing local material does not by itself prove a provider remotely revoked it. Session expiry and process-local session state are distinct from persistent admission-token lifetime; do not claim that rotating a file instantly revokes every established connection. Established WebSocket per-frame reauthentication/revocation is not a guaranteed capability.

Cookie acquisition first finds host-matching rows, then accesses Safe Storage. One manual action allows at most one interactive Keychain read. Denials retain cooldowns, including manual retries; only an explicit cookie-refresh action with the prompt override can override that cooldown. Traversal stops at the first validated session. Tests never exercise live cookies, real account probes, or prompt-producing Keychain paths without an explicit request.

## Self-hosted CI runner boundary

CI jobs run on the team's Mac CI machine as its login account, the same trust as the team's other CI runner on that machine. Accepted on 2026-10-27: an admitted job can reach that account's GitHub CLI login with write access to all of the account's repositories, the other runner's configuration, the local state of apps installed for that account (including CodexBar, Claude, and OpenCodex state), and the runner's own `.env`, hook, and credential files. The build and `make check` use the real home directory; each test group gets a synthetic home and Keychain suppression from the test runner, so a change that weakens that isolation reaches real local state.

Admission happens on the runner, not in the workflow. A job-started hook installed outside the runner application directory reads the event name and payload before any step and admits only `push`, `workflow_dispatch`, and `pull_request` whose head repository is this repository. Every other event, a fork pull request, a pull request without a head repository, and an unset, missing, unreadable, or invalid payload are refused (fail closed). A fork's pull request carries its own copy of the workflow file, so the workflow's fork condition is not a control. A fork's code reaches the machine only when the maintainer directly instructs, for that one pull request, that it be pushed into this repository. Weakening or bypassing the hook to get a run through is forbidden. An admitted job runs as the same account and could alter the installed hook or `.env`; the committed hook is the reference, and a SHA-256 comparison of the installed copy with it detects drift.

Runner registration and removal tokens are short-lived and created on the CI machine at the moment of use, passed to the runner configuration only through the `ACTIONS_RUNNER_INPUT_TOKEN` environment variable, and never printed, logged, stored, or committed. The runner's credential files stay on the machine with owner-only permissions. Checkout does not persist the job token in the persistent workspace.

GitHub prints the runner host's machine name and home-based work paths in every job log of this public repository; this cannot be hidden without renaming the machine and was accepted on 2026-10-27. The repository itself does not name the team's machines or accounts, and the hook prints only the event name and a fixed reason.

## Recording and diagnostic limits

Usage accounting records routing/usage metadata and token counts, not prompts, response bodies, authentication headers, credential values, or private account data. Security diagnostics can identify a failed operation, refusal category, or file/line requiring repair without echoing the sensitive value. Switch handling exposes request outcome categories rather than credential contents.

Keep consent, admission refusal, initialization failure, switch refusal/failure, and package/recovery failure distinguishable in their existing result/diagnostic paths. Do not describe these outputs as a complete immutable security audit trail: the toolkit does not promise a centralized append-only audit service. New logging must not introduce secrets, account identifiers, request bodies, or private paths to make an event easier to diagnose.

Local agents running as the person can reach the same local credentials and bootstrap mechanisms as the browser. Dashboard-session gating stops the casual admin-token-only action; it is not a technical proof that a human, rather than a determined local agent, initiated an action. The consent rule still applies.
