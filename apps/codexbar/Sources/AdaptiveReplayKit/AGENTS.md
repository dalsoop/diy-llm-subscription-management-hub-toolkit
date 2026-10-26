# Offline refresh replay

Own caller-supplied JSONL trace parsing, policy adapters, simulated schedules, metrics, legacy-gap segmentation, and recorded schedule audit. Depend only on the pure refresh policy; do not import the app/provider core, capture traces, scan sessions, call providers, or mutate production policy.

Strict parsing is the default. A tolerant exploratory entry point may skip malformed records only when the caller explicitly selects that behavior. Optional activity fields are inputs, not permission to discover data. Old records without those fields remain readable.

Counterfactual refresh assumes zero-duration work; recorded timer advances are a separate audit, not a directly equivalent count. Expose excluded gap duration and segmentation parameters without guessing whether a gap was sleep, reboot, or stalled work.

Use synthetic traces to cover malformed input, older fields, segmentation edges, manual/fixed/adaptive policies, constrained-state compliance, and recorded-vs-simulated metrics. Run `AdaptiveReplayKitTests` through the package's isolated focused runner.
