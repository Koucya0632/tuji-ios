# ADR-0004 — Manual Pro grants are stored separately from App Store subscriptions

- **Status:** Accepted
- **Date:** 2026-08-09

## Context

Pro could come from two places — an App Store subscription, or an operator handing it out
(comps, apology credit, reviewer access) — but both wrote the same `user_entitlements` row.
One row per user, with one `tier`, one `expires_at` and one `source`.

Because the row was upserted in place, the two sources overwrote each other, and both
directions were silent:

- Compensating a paying subscriber wrote `expires_at = now() + N days` over their real
  expiry. If they were paid up further out than the compensation, the "compensation"
  **shortened** their access.
- Apple's next renewal notification then wrote the real subscription state back, erasing
  the compensation entirely. Nothing recorded that it had ever been given.

Neither failure produced an error, a log line, or anything visible to the operator. The
first case is the more serious one, because it is triggered by exactly the situation manual
grants exist for: making things right with a paying customer after an outage.

At the time of this decision the product had 27 registered accounts and zero real
subscriptions, so no live data had yet been damaged and no migration was needed beyond
moving one test grant.

## Decision

Manual grants live in their own table, `user_entitlement_grants`. `user_entitlements`
becomes exclusively the App Store subscription — only StoreKit verification and the App
Store Server Notifications webhook write it.

A user's **生效權限 (effective entitlement)** is the union of the two: Pro if either source
is live, with the later expiry winning. The union is computed at read time, in one SQL
round trip (the read sits on the hot path — every AI recognition and capacity check goes
through it). The rule itself is a pure function, `resolveEntitlement`, so it can be tested
without a database.

Grants are append-only: revoking sets `revoked_at` rather than deleting, and a reason is
mandatory on both grant and revoke. A grant never touches the subscription and a revoke
never cancels a purchase.

Every transition is appended to `user_entitlement_events`, a ledger that exists because
both source tables are mutated in place and therefore have no history. It records our
users' entitlement changes; it deliberately does not duplicate App Store Connect, which
remains the authority on revenue, refunds and churn.

## Considered options

- **Keep one row and accept the flaw:** rejected because the case it breaks — compensating
  a paying subscriber — is the most likely real use of a manual grant, and it breaks
  silently in the direction that harms the customer.
- **Keep one row but let `source = 'manual'` win over the webhook:** rejected because it
  inverts the problem. That account's true Apple state — refund, cancellation, expiry —
  could then never be applied again.
- **Grant by extending the subscription's `expires_at`:** rejected for the same reason as
  the first option, plus it makes "is this person a paying customer" permanently
  unanswerable, which corrupts every revenue figure downstream.
- **Defer the ledger until there is traffic worth analysing:** rejected because entitlement
  history cannot be backfilled. The cost now is one INSERT on a path that already writes;
  the cost later is that the data simply does not exist.

## Consequences

- Two writes are needed to fully understand a user's Pro state, and admin surfaces must
  show them **separately**. A single merged "Pro until…" cannot distinguish a paying
  customer from a comped account, and those need different handling in support.
- Any count of "Pro users" must union both tables or it silently omits comped accounts;
  any count of *customers* must read the subscription table alone. `/admin/stats` reports
  both numbers side by side for this reason.
- Pre-existing manual grants written into `user_entitlements` (source `manual-%`) are moved
  into the grants table by migration, so they stop reading as revenue.
- The ledger starts empty. History before this change does not exist and cannot be
  reconstructed; admin surfaces say so rather than implying nothing ever happened.
