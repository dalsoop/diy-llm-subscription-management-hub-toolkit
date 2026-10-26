# Replay command line

Own replay argument parsing and human/JSON report formatting over `AdaptiveReplayKit`. Do not collect trace data, scan coding sessions, read provider credentials, or fork refresh-policy calculations.

Preserve strict input/error exits, repeated policy selection, all-policy default, and explicit gap-grace/raw-wall-clock selection. Reject unknown policies, extra positional arguments, and negative/non-finite gap grace rather than silently choosing a default. Report segmentation exclusions and recorded audit separately from counterfactual results.

Run the package's isolated `AdaptiveReplayCLITests` and relevant kit tests with synthetic task-owned trace files. Cover help/missing arguments, invalid policies/grace, unreadable/malformed traces, and table versus JSON output. Never use real session logs as fixtures.
