# Desktop shell

Own Tauri bootstrap UI, Rust shell lifecycle, sidecar/resource preparation, and local-proxy integration. Do not move provider routing or account authorization into the shell; the proxy owns those behaviors. The macOS native tray/widget and the separate CodexBar app are not interchangeable artifacts.

Prepare the sidecar before Tauri dev/build and the widget before macOS packaging. Generated binaries, keyring resources, app bundles, and distribution output are not committed. Bun's executable VFS cannot load a native `.node` keyring addon; retain the external resource and installed-path resolution.

Use `bun run build:local` for an authorized unsigned local build, not release publication. A release-style build that emits an app then fails for a missing updater key has not completed successfully. Do not weaken signing/update gates or supply another app's key.

Run shell/resource tests for the changed behavior and verify the assembled app when claiming installed behavior. Rust build/test/check commands go through the build queue on a designated build machine, including compilation invoked by Tauri. State untested platforms explicitly; a GUI Vite build alone does not verify sidecar or widget loading.
