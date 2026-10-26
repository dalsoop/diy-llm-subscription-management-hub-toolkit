# Native macOS companion

Own the Swift package's native tray library, shared model/transport layer, WidgetKit extension, and executable tests. Do not implement proxy routing or manage the separate CodexBar application's state. Keep native UI consumption of account/usage data within the proxy's admitted interfaces and reduced snapshots.

The package targets macOS 14. `MenuBarCoreTests` and `NativeTrayTests` are executables because Command Line Tools lacks the required conventional test runtimes; `swift test` is not their coverage command. From the toolkit root run `swift run --package-path packages/opencodex/app MenuBarCoreTests` for model changes and the corresponding NativeTrayTests product for tray changes.

Keep the widget's Swift entry and `_NSExtensionMain` linker entry together, along with extension API restrictions. Model tests do not certify extension loading or signed packaging. Use synthetic transports, snapshot files, and task-owned homes; no real account or interactive Keychain probes.

Preserve the static NativeTray interface linked by the desktop Rust build. Cover polling cancellation, stale/missing snapshots, formatting, discovery, and action failure using existing seams rather than introducing live system dependencies into deterministic tests.
