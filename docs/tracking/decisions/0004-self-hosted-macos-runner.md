# Self-hosted macOS CI runner behind fork-run approval

## Context

The root CodexBar workflow has one job, `macos`, which used to run on a GitHub-hosted macOS image. On 2026-10-27 the maintainer decided that this CI runs on the team's own Mac CI machine instead, the same way that machine already runs the team's GitLab macOS runner: an always-on user LaunchAgent, its own work folder, one job at a time, and builds holding a host compile slot so CI never overloads the machine together with its other builds.

The repository is public. A pull request from a fork runs the workflow file from the fork's own head, and a self-hosted job runs as the CI machine's login account, next to that account's local credentials and app state. The repository rule is that untrusted pull-request code never runs with secrets.

## Decision

Register one persistent repository-level runner named `mac-ci` (labels `self-hosted`, `macOS`, `ARM64`, `mac-ci`) on the Mac CI machine, running as its login account through the vendor's user LaunchAgent with KeepAlive added. The `macos` job targets all four labels, so it has no GitHub-hosted fallback.

Neither the workflow nor the fork decides which jobs reach the runner. The first layer is the repository's fork-PR approval policy, set on 2026-10-27 by the maintainer's decision to require approval for every outside contributor: no fork workflow run starts without an approval, and approving one means running that code on the CI machine as its login account. The second layer is a job-started hook installed outside the runner application directory; it admits only `push`, `workflow_dispatch`, and `pull_request` whose head repository is this repository, and refuses everything else, including an unset, missing, unreadable, or invalid event payload. A refusal fails the job, but GitHub's runner still runs `always()` steps after a failed job-started hook, which is why the approval policy, not the hook, is the boundary. The workflow also skips fork pull requests, as a courtesy that shows a skip instead of a refusal.

The `macos` job keeps its commands. `make check` holds a slot from the host's check pool; the full test run holds one compile slot for the whole step, because the test runner builds and tests in one command and is not split here. Before taking a slot the job waits while the 1-minute load average is 30 or higher, for at most 30 minutes, and never skips the checks after waiting. Checkout does not persist credentials and keeps `apps/codexbar/.build` between runs for incremental builds.

## Alternatives

- Keep a GitHub-hosted fallback for fork pull requests: rejected because no macOS job is to run on GitHub-hosted runners any more.
- Rely on a workflow `if:` to keep forks off the runner: rejected because the fork controls its own copy of the workflow file.
- Rely on the hook alone, keeping the default approval only for first-time contributors: rejected after the security review showed that `always()` steps still run after the hook refuses a job; any outside contributor with an earlier merged pull request would then run code on the machine without an approval.
- Make the hook terminate the job's worker process on refusal so `always()` steps cannot run: not adopted here because it depends on undocumented runner internals and needs its own testing.
- Run the runner under a separate macOS account: rejected because it needs an administrator password and departs from how the team's other runner on the same machine already runs; the exposure is accepted instead (below).
- Use an ephemeral runner: rejected because it loses the incremental build cache and the always-on arrangement.
- Submit the job to the machine's build queue: rejected because the queue may run it on another machine, where the job's checkout does not exist.
- Run the test step in the check pool: rejected because the test step compiles, and builds take the compile slot.
- Name the runner or its label after the machine: rejected because nothing in this public repository names the team's machines or accounts.

## Consequences

- Accepted exposure (2026-10-27): an admitted job can reach the CI machine account's GitHub CLI login with write access to all of that account's repositories, the other CI runner's configuration, the local state of apps installed for that account (including CodexBar, Claude, and OpenCodex state), and the runner's own `.env`, hook, and credential files. The build and `make check` use the real home directory; each test group gets a synthetic home and Keychain suppression from the test runner. This holds only while fork code reaches the runner solely through the maintainer's approval of one pull request at a time, and no `pull_request_target`, `issue_comment`, or `workflow_run` job targets it.
- Fork pull requests get no macOS CI by default, and approving a fork run does not change that: the job's fork condition skips an unchanged fork workflow and the hook refuses one without it, so an approval only runs workflow code the fork controls on the CI machine. Agents never approve fork runs; the maintainer approves one only deliberately, one pull request at a time. macOS CI for a fork pull request comes only from the maintainer pushing its reviewed code to a branch of this repository, one pull request at a time; agents never do that. Otherwise the pull request stays without macOS CI and says so. A skipped fork job can still satisfy a required status check, so it is never success evidence.
- An admitted job runs as the same account and could alter the installed hook, `.env`, or `.path`, or put its own `bash` ahead of `/bin/bash` on the job `PATH`, which the runner uses to start the hook. Drift is detected by comparing the installed hook's SHA-256 with the hook on `main`, checking `.env` and `.path` against their documented lines, and checking that `bash` resolved through `.path` is `/bin/bash`.
- A toolkit test run occupies one of the machine's two compile slots for roughly 20–40 minutes, leaving one for the machine's other CI runner and build-queue jobs. A waiter that passes its wait limit (1800 seconds here) runs without a slot.
- While the machine is off or the runner is stopped, runs wait in GitHub's queue and fail after 24 hours; such a run is not evidence and must be re-run. `main` has no branch protection, so nothing blocks a merge automatically. After a reboot the runner starts only once the account has logged in.
- GitHub prints the runner host's machine name and home-based paths (the work folder and the hook path) in every public job log; this cannot be hidden without renaming the machine. The maintainer accepted it on 2026-10-27. The repository itself does not name the machine or account, and the hook prints only the event name and a fixed reason.
