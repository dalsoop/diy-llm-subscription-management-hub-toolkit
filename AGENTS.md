# DIY LLM Subscription Management Hub Toolkit

This repository is the canonical home for this toolkit. Change the menu bar app in
`apps/codexbar` and the proxy/session hub in `packages/opencodex`.

- Prepare branches and pull requests in `dalsoop/diy-llm-subscription-management-hub-toolkit`, targeting `main`.
- Treat the historical standalone CodexBar fork as a source of history; deliver toolkit changes here.
- Read the component's `AGENTS.md` before editing it. Keep provider account identities isolated.
- Never include credentials, real account data, per-host configuration, or compiled app bundles in commits.
- Use the component's isolated test runners. Do not run real account, Keychain, or cookie probes as tests.
- Root shortcuts use `bun run codexbar:check`, `bun run codexbar:test`, and `bun run codexbar:build`.
- GitHub executes workflows from the root `.github/workflows` directory; nested component workflows are references.
- Only stage paths belonging to the current task. Do not revert another contributor's changes.
