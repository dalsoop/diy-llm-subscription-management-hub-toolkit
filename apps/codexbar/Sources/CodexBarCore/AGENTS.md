# Shared provider core

Own provider acquisition/parsing, account-bound usage models, local stores, and app/widget snapshots. Do not import the menu bar app, WidgetKit UI, or replay tooling into this core. The CLI and app must reuse these parsers rather than fork protocol behavior.

Keep provider identities and history owners distinct. Optional profile/identity lookup failure must not erase successful quota acquisition. Real-account, cookie, and Keychain paths are not test fixtures; inject transports, clocks, stores, and synthetic homes.

For the OpenCodex bridge, resolve runtime role before choosing live versus snapshot/linked reads. Never execute account use on a client. Keep full IDs only in the fresh in-memory live list; publish suffix/display-value requests, not credentials. Reject malformed/multiple-active pools, preserve display rows with unusable IDs as nonswitchable, and match success receipts to the requested active ID. Preserve writer timestamps and stale state.

Run relevant isolated parser/account tests from the package root with `make test-fast FILTER='<suite>'`, plus `make check` before handoff. Cover provider mismatch, duplicate/invalid IDs, missing quota versus zero, stale/missing timestamps, client read-only fallback, source changes during refresh, and mismatched receipts. Do not validate by invoking real provider usage.
