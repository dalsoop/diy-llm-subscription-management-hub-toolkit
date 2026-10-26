# Usage and account rules

## Identity and source ownership

A provider account owns its identity, plan, usage windows, and history. A Claude card must not borrow a Codex identity or plan, even if their display emails match. A masked email and a user-visible label are display values, not identity merge keys.

The selected account source determines which inventory is displayed. Dormant accounts from another source must not replace that selection. Pausing a hub registration removes it from selectable account cards and mini-meters but retains it in management inventory. Selecting a provider's mini-meter selects that provider; it does not activate a different account or trigger an extra credential read.

A linked client can report cached accounts without owning a hub. A successful read from that cache must not imply that the client can switch accounts. Failure to obtain hub state must not silently substitute the client's local login state as if it described the hub.

## Quota meaning

A measured zero and an unavailable measurement are different states. Missing usage renders an unavailable/dim empty meter, not a measured zero-percent result. Account mini-meters follow account-card order rather than an independently sorted order.

For a set of known quota windows, the account's highest used percentage is `max(known used percentages)`. Missing windows are excluded; an account with no known percentages has no highest-used value. Finite percentages are bounded to the display interval from zero through one hundred; non-finite values do not become measurements.

OpenCodex quota projection compacts available standard windows into primary, secondary, and tertiary lanes in five-hour, weekly, then monthly order, retaining their duration classifications. A weekly-only or monthly-only window therefore occupies primary; missing measurements are omitted, never synthesized as zero. The monthly thirty-day classification value is a lane sentinel, not evidence that the provider reported exactly thirty days.

## Freshness and refresh

Snapshot freshness uses the hub's write time, not the time the display last read the file. A snapshot with no write time, or with age strictly greater than five minutes, is stale. Re-reading it successfully must not relabel its usage as current. A stale result must not overwrite a newer current pool already displayed.

A transient network failure may retain the prior snapshot for the same owner, preserving its original timestamp. Authentication failure, provider/account-source changes, and owner changes retain their invalidation boundaries; old usage must not survive by being reassigned to a new owner. A refresh that finishes after the selected source changes must not publish into the new selection.

Fresh installations default to Adaptive refresh. Existing installations without the newer setting retain the legacy five-minute fallback. Manual refresh and fixed intervals remain explicit alternatives. Adaptive timing is fifteen minutes for ordinary idle, thirty minutes for long idle or constrained conditions, two minutes for a menu opened within five minutes, and five minutes for a menu opened within an hour. Recent coding activity can shorten slower adaptive timing to five minutes; it does not override constrained mode. Agent-aware activity is considered only after explicit consent; undecided is not permission.

## Explicit account switching

An account is an eligible target only when it is not already active, not paused, not awaiting reauthentication, has an addressable ID suffix, and the selected pool permits switching. A near-limit account at or above eighty percent is allowed with a warning; this is not the same as a forbidden target.

Before acting, refresh the account source and resolve the target again. A display label or an old list position must not authorize a switch. Duplicate or invalid live IDs leave a row displayable but not directly switchable; multiple active rows make the live list malformed. A success receipt naming a different active ID is not a successful switch to the requested account.

A hub/standalone installation may perform the direct account-use operation. A client publishes an explicit request using the current snapshot; it must not invoke account use locally. A pending request is not completion. Terminal receipts distinguish done, refused, and failed; a superseded request does not prove that its originally requested target became active.

## Consent and optional behavior

Actions spending a person's identity, credits, or reputation require that person's consent. An agent must not answer a repository-star prompt or equivalent action on their behalf. Access to a local management session is not evidence of such consent.

Agent-aware activity scanning is opt-in, bounded to supported process/file metadata, and does not collect transcript contents. Activity timestamps are not persisted, logged, or uploaded and are cleared when consent is revoked. An undecided or revoked setting must not keep scanning.

A default proxy installation with one provider/model and no optional Lab configuration must execute no Lab code and start no Lab timer. Enabling optional policy evidence must not create an interval in which a request can route before its selected evidence provider is registered.
