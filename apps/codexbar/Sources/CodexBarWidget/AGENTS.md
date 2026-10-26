# CodexBar widget

Own WidgetKit entries, account/provider selection, tile planning, and snapshot presentation. Read app-written snapshots through the shared core; do not acquire provider credentials, poll live providers, or own proxy account switching.

Missing snapshots use empty/preview behavior appropriate to the WidgetKit context, not fabricated live measurements. Preserve provider/account identity when selecting entries, and keep stale timestamps rather than implying that timeline generation refreshed usage. Keep resource localization aligned with visible widget copy.

Cover snapshot decoding, account/provider selection, missing data, tile plans, and refresh scheduling with synthetic data in package tests. Prefer stable model tests over headless live widget/AppKit construction. Bundle loading and Tahoe presentation require an appropriate packaged/macOS environment; compilation alone is not visual proof.
