# Optional policy services register into the core

## Context

An ordinary one-provider installation must not start Compatibility Lab code or timers. A prior transitive import chain pulled optional modules into the default request path even though no individual direct import looked suspicious. Policy routing also needs its evidence provider registered before the first route can run.

## Decision

Keep core-owned registration slots for optional services. The composition root activates them only when required. Binding the server through optional activation and returning the server remains one synchronous turn.

## Alternatives

- Let routing/lifecycle import Lab helpers: rejected because a transitive convenience import activates optional dependencies for every installation.
- Defer activation asynchronously after startup: rejected because synchronous fallback routing can execute before evidence registration and silently select a different model.
- Ban optional imports from the composition root too: rejected because that root is precisely where configured subsystems must be assembled.

## Consequences

Core request paths remain independent of Lab runtime imports, while optional configuration can still attach evidence. New optional functionality must use registration seams rather than a core import. Startup cannot insert an await in the binding-to-activation window; import-graph and synchronous-start regression checks protect different parts of the boundary.
