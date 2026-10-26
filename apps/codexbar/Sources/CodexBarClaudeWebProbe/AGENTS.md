# Claude web diagnostic

Own the explicit diagnostic executable over shared Claude web-fetching facilities. It does not own normal refresh policy, browser consent, account storage, or a second web parser.

Do not make the diagnostic run automatically as part of a build or test. Live web/credential probes require an explicit request; parser/argument changes use stubbed data instead. Retain noninteractive failure behavior and avoid leaking cookies, tokens, account identifiers, or response bodies into diagnostics.

Cover entry/argument/result formatting through synthetic shared-core tests and package checks. State when the live diagnostic was not run; a successful build does not verify an authenticated web session.
