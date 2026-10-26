# GitHub automation instructions

This directory owns the component's reference automation. GitHub executes only the toolkit's root workflows; editing these references does not deploy or validate an active toolkit workflow.

## Security boundary

Every workflow, ownership, branch-enforcement, release, or repository-automation
change requires explicit security review under `MAINTAINERS.md`.

## Workflow rules

- Grant the minimum required `permissions`.
- Pin third-party actions to immutable full commit SHAs.
- Preserve the human-readable version comment beside each pinned action.
- Do not run untrusted pull-request code with secrets or write permissions.
- Treat `pull_request_target`, workflow dispatch, reusable workflows, artifacts, caches, and generated command input as trust boundaries.
- Do not broaden triggers, write permissions, token exposure, release eligibility, or publish capability without an explicit task requirement.
- Preserve cross-platform coverage where the workflow currently promises Linux, macOS, and Windows behavior.
- Preserve the reviewed branch-enforcement policy across automation and contributor text; do not silently apply standalone `dev` policy as toolkit `main` policy.

## Validation

- Inspect the complete workflow diff, including event triggers, permissions, conditions, interpolation, and shell behavior.
- Run the local commands represented by changed workflow steps where possible.
- Follow the root validation policy: run the suite by default; if a full run is too costly, run at least focused regression tests and document the reason and remaining coverage. Required CI checks still apply before merge.
- Do not claim the workflow itself passed until GitHub Actions reports success for the exact commit.
