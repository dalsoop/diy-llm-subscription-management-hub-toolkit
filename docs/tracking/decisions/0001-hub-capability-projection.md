# Reduced hub capability projection

## Context

A linked client's local credential store can be empty while its hub has configured and authenticated providers. Reporting local login state as hub state misleads the operator. Giving the client management access just to inspect provider capability would expand its authority beyond inference.

## Decision

Expose an admitted, bounded hub-state projection on the data plane. Send provider names/adapters, credential-presence and OAuth-login booleans, authentication modes, and featured models; do not send credentials, account identities, or disabled-provider inventory. Keep the hub role gate after admission so unauthenticated callers do not gain a hub-role probe.

## Alternatives

- Read the linked client's local login state: rejected because it cannot represent the hub's actual capabilities.
- Share an admin token and read management inventory: rejected because a reporting fix does not justify account/configuration administration authority.
- Copy the hub account store to the client: rejected because presence/model reporting does not require credential transfer.

## Consequences

Clients can explain missing credentials and configured capabilities without acquiring management rights. They must preserve the hub identity, parse bounds, and truncation flag; malformed hub state cannot become local state. The projection cannot serve credential reveal, complete management inventory, or provider account switching.
