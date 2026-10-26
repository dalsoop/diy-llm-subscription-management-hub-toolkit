# Source runtime instructions

`src/` owns CLI/runtime routing, adapters, account/configuration services, and management endpoints. It does not own generated dashboard assets, the desktop shell, or the separate CodexBar application.

## Runtime and module rules

- `src/` is Bun-native TypeScript in strict mode and uses ES modules only.
- Do not assume a separate server compilation step.
- Prefer Bun and Web-platform APIs. Introduce a Node-only runtime dependency only when the task explicitly requires compatibility code and the owning module already has that role.
- Preserve existing public exports and configuration compatibility unless the task explicitly changes them.
- Read the applicable documents in `structure/` before changing shared routing, adapters, transports, sidecars, authentication, configuration, or server architecture. [`structure/INDEX.md`](../structure/INDEX.md) maps each source area to its documents, often more than one because documents follow topics while `src/` follows modules. Review every mapped document; update the authority when a shared contract changes and dependents when their own explanations change. Accurate unchanged prose need not be edited. Preserve the existing manifest, contract registry, invariant IDs, and approved crosslinks.

## Implementation rules

- Follow the existing subsystem boundaries and naming patterns.
- Do not combine unrelated responsibilities to avoid creating another large shared module.
- Handle asynchronous failures at request, transport, and sidecar boundaries. Optional integrations must degrade through the existing failure representation rather than crash the request path.
- Provider catalog metadata belongs in the canonical provider registry and derivation flow. Do not duplicate provider facts across independent pickers or seeds.
- Adapter changes must preserve the internal event contract, streaming behavior, tool calls, cancellation, error mapping, and image handling relevant to that adapter.
- Authentication, OAuth, token, credential, management API, and CORS changes are security-boundary changes.

## Tests and validation

- Place focused regression coverage near the existing tests for the affected subsystem.
- For focused behavior, use the component's isolated `bun run test tests/<domain>/<name>.test.ts` wrapper and `bun run typecheck`; raw test shortcuts do not provide the same synthetic-home setup.
- For multi-file development feedback, use the isolated wrapper with a valid toolkit comparison, such as `bun run test --changed=origin/main` when available. The inherited `test:changed` shortcut still compares to `dev`. Import selection misses subprocess/source-as-data/golden dependencies; run those regression files explicitly.
- Run the full `bun run test` suite before a non-trivial PR is review-ready by default. A proportional resource exception requires focused regressions, its reason, exact commands/results, and remaining CI coverage in the PR. Keep the PR in draft when focused coverage is unreliable; changed-file selection alone is not a readiness substitute.
- For logging, requests, credentials, account data, or fixtures, also run `bun run privacy:scan`.
- Update `docs-site/` when the change affects user-visible behavior or configuration.
