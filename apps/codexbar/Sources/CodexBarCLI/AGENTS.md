# CodexBar command line

Own CLI argument handling and output over `CodexBarCore`; do not implement a second provider parser or import application UI. Preserve machine-readable output separately from human diagnostics and keep existing exit behavior for invalid arguments and acquisition failure.

Credential-prompt overrides are explicit user actions, not defaults or test configuration. Claude's configurable status line is not a default usage source. Do not print secrets, raw cookie material, or another provider's identity with a usage result.

Test arguments, JSON/output shape, failure exits, and missing optional fields using isolated fixtures through the package's focused runner. Run `make check` from the package root before handoff. A `codexbar usage` call against installed accounts is a live probe and needs explicit authorization; it is not a CLI smoke test.
