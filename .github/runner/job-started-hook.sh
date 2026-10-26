#!/bin/bash
# Job-started hook for the self-hosted macOS runner.
#
# The runner runs this before every job. A non-zero exit fails the job and
# skips its ordinary steps, but steps with an always() condition still run,
# so this is a second layer behind the repository's approval of fork runs.
# It admits only push, workflow_dispatch, and pull_request events whose head
# repository is the base repository. Anything else fails closed, including an
# unset event name or a missing, unreadable, or invalid event payload.
#
# Install a copy outside the runner application directory and reference it
# from the runner's .env as ACTIONS_RUNNER_HOOK_JOB_STARTED. It only reads the
# event payload file and never prints payload content, because job logs are
# public. It uses stock macOS tools only: bash 3.2 and /usr/bin/jq.

set -euo pipefail
export LC_ALL=C # ASCII ranges in the event name pattern below.

readonly jq_bin=/usr/bin/jq
event="${GITHUB_EVENT_NAME:-}"
payload="${GITHUB_EVENT_PATH:-}"

# Print the event name only when it looks like one, so a refusal stays one line.
case "$event" in
  '' | *[!a-z_]*) event_label=unknown ;;
  *) event_label="$event" ;;
esac

refuse() {
  printf 'job-started-hook: refused %s: %s\n' "$event_label" "$1" >&2
  exit 1
}

# jq's own messages are dropped; a failure becomes a refusal line instead.
read_payload() {
  "$jq_bin" -r "$1" "$payload" 2>/dev/null
}

case "$event" in
  push | workflow_dispatch | pull_request) ;;
  '') refuse 'event name unset' ;;
  *) refuse 'event not allowed' ;;
esac

[[ -n "$payload" ]] || refuse 'event payload path unset'
# A regular file only: reading a pipe or device could block the job.
[[ -f "$payload" && -r "$payload" ]] || refuse 'event payload unreadable'
[[ -x "$jq_bin" ]] || refuse 'jq unavailable'

payload_type="$(read_payload 'type')" || refuse 'event payload invalid'
[[ "$payload_type" == object ]] || refuse 'event payload invalid'

if [[ "$event" == pull_request ]]; then
  origin="$(read_payload '
    if (.pull_request.head.repo.full_name | type) != "string"
      or .pull_request.head.repo.full_name == "" then "missing"
    elif .pull_request.head.repo.full_name == .repository.full_name then "same"
    else "other"
    end')" || refuse 'event payload invalid'

  case "$origin" in
    same) ;;
    missing) refuse 'pull request head repository missing' ;;
    *) refuse 'pull request head is in another repository' ;;
  esac
fi

printf 'job-started-hook: admitted %s\n' "$event"
