# Remote-workspace confinement helper

Own the versioned stdin/stdout command-confinement protocol and platform backends. Do not implement proxy admission, workspace file tools, or an unconstrained fallback shell here.

Validate bounded JSON and command authority before platform code. A probe cannot carry root/cwd/command/toolchain/timeout/output/network authority. Reject unknown wire fields, unsupported versions/operations, oversized input, and invalid command/path bounds. Output is one JSON response with base64-encoded command streams, not interleaved human logs.

Current macOS and Windows backends report confinement unavailable and refuse command execution. File tools remaining usable is not permission to bypass this refusal. Platform support requires proving the authority boundary, not merely making a process launch succeed.

Run Rust tests/checks only through `build-pipeline submit` on the designated build fleet, with one command per job; use the package's locked Cargo manifest and task-owned fixtures. Cover authority smuggling, unknown fields, size/timeout limits, unsupported operations, failure JSON, and confinement refusal. Never probe real workspaces or execute untrusted commands to test availability.
