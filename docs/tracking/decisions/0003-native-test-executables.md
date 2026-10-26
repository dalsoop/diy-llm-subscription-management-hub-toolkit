# Executable tests for native macOS models

## Context

The OpenCodex native companion is built in environments using Command Line Tools, which do not provide the usable XCTest module and Swift Testing runtime expected by a conventional test bundle. The tray and widget still need deterministic model, formatting, polling, and action coverage.

## Decision

Keep the native model and tray tests as explicit executable products in the Swift package. Run those named products directly, using synthetic transports and snapshot data rather than real accounts.

## Alternatives

- Require XCTest bundles for every native test: rejected because that excludes the intended Command Line Tools environment.
- Depend on live GUI/manual validation alone: rejected because it does not provide deterministic regression coverage of model and action behavior.

## Consequences

A generic `swift test` invocation does not establish native companion coverage. Contributors must run the named test executable and preserve its failure exit behavior. These tests do not certify packaged widget loading, Tauri sidecar resources, signing, or live Keychain integration.
