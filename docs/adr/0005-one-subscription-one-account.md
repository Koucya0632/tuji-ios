# ADR-0005 — One App Store subscription entitles exactly one account

- **Status:** Accepted
- **Date:** 2026-08-09
- **Security amendment:** 2026-09-01

## Context

An App Store subscription belongs to an Apple ID and a device. A Tuji account is something
else — the app offers three sign-in providers (email, Google, Apple), and users move
between them.

`PaywallView` calls `refreshFromCurrentEntitlements()` in its `.task`, which forwards the
device's active StoreKit entitlements to `/api/billing/verify`. A transaction by itself did
not identify the Tuji account that purchased it, so the old flow effectively accepted it
for **whoever was currently signed in**. That meant:

1. A user subscribes while signed in as account A.
2. Later they sign in with a different provider, creating or using account B.
3. B shows Free, so they open the paywall to find out why — which is the natural thing to
   do, and is all it takes.
4. The same `original_transaction_id` is now written to B as well.

`user_entitlements.original_transaction_id` had only a non-unique index, so both rows
persisted and both accounts were Pro on one payment. Worse, the webhook's reverse lookup
(`getUserIdByOriginalTransaction`) selected `LIMIT 1` with no `ORDER BY`: renewals, expiry
and **refunds** landed on an arbitrary one of the two. The account that did not receive the
refund notification stayed Pro until its stored expiry ran out.

The cost is not only correctness. Pro carries 500 ordinary AI recognitions and 30 precision
recognitions per month, so a duplicated binding doubles the AI spend a single subscription
pays for.

At the time of this decision there were zero real subscriptions, so the invariant could be
introduced with no data to reconcile.

## Decision

Exactly one account may hold a given `original_transaction_id`. This is enforced in four
ways:

- **Structurally** — a UNIQUE partial index on `user_entitlements(original_transaction_id)`.
- **At purchase** — iOS supplies the signed-in Tuji UUID as StoreKit's `appAccountToken`.
  The server accepts the signed transaction only for that UUID.
- **For legacy purchases** — a transaction without `appAccountToken` may refresh only the
  account already bound to its `original_transaction_id`. An unbound legacy transaction is
  rejected and requires an explicit support-side migration.
- **For state ordering** — the server persists Apple's signed date and transaction ID and
  rejects stale or ambiguous privilege-raising replays. Each subscription update is
  serialized in one database transaction.

An existing binding moves only when Apple's signed `appAccountToken` proves the destination
account. It never follows the account that merely submitted the JWS. Account migration for
an untokened legacy purchase is deliberately a support operation because the bearer JWS
cannot prove which Tuji account should receive it.

A migration de-duplicates any existing conflicts before the unique index is created, since
this runs at build time and a failure there would block deploys.

## Considered options

- **Let the most recent submitter take the binding:** rejected after security review because
  the same signed JWS can be replayed by multiple Tuji accounts and rotate subscription
  quotas. A signed `appAccountToken`, not possession of the JWS, now authorizes a move.
- **Allow N accounts per subscription (family-style sharing):** rejected because it is not
  a product we decided to sell, and it arrived by accident rather than by design. Nothing
  prevents revisiting it deliberately later.
- **Fix only the `LIMIT 1` non-determinism:** rejected because it makes the webhook
  predictable without stopping one payment from entitling two accounts.
- **Leave it until a real subscriber hits it:** rejected on timing. With zero subscriptions
  the change is a schema addition with nothing to migrate; after launch it means
  reconciling live paid accounts, deciding which of two Pro users to demote, and doing it
  under support pressure.

## Consequences

- A user who signs in to a second account cannot silently move Pro by replaying or restoring
  a transaction bound to the first account. New purchases are permanently tied to the Tuji
  UUID Apple signed into the transaction.
- Existing untokened subscriptions continue to renew and restore on their current binding.
  Unbound legacy purchases need a reviewed support migration instead of first-claim wins.
- `getUserIdByOriginalTransaction` is now deterministic, so refunds and expirations always
  reach the account that actually holds the subscription.
- The migration that creates the unique index must keep running de-duplication first; a
  future code path that writes bindings without going through `upsertAtlasEntitlement`
  would break the build rather than corrupt data, which is the intended failure direction.
