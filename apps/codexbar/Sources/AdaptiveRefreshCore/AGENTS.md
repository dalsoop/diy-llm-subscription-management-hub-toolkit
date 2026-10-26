# Pure refresh policy

Own the Foundation-only decision table shared by production and replay. Do not depend on the app, provider core, replay kit, process discovery, filesystem scanning, or network access. Callers supply time, activity, menu, and constrained-state inputs; this target does not read the clock or collect activity itself.

Keep the production/replay policy identical rather than copying thresholds into either consumer. Constrained conditions take precedence over activity-based shortening; absent activity/consent must not manufacture evidence.

Test decision boundaries with injected instants: recent menu thresholds, ordinary/long idle, constrained state, and recent coding activity. Run the existing focused policy/replay tests through the package runner and `make check`. No test needs a running coding agent or provider account.
