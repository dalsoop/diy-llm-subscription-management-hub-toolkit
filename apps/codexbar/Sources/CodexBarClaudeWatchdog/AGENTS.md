# Claude child-process watchdog

Own supervision, termination, and exit propagation for the launched child process. Do not add provider parsing, account persistence, browser access, or UI dependencies here; the watchdog is a separate executable with process-lifetime responsibility.

Keep argument-vector execution separate from shell interpretation. Preserve child/process-tree termination and signal behavior; do not leave descendant processes behind when the parent cancels. Diagnostics must not echo credential-bearing arguments or inherited environment values.

Validate argument refusal, child exit status, timeout/termination, and cleanup using harmless synthetic child processes in task-owned temporary directories. Do not launch an installed provider session as a test. Run the package's focused runner and `make check` for changes to this target.
