# ADR-0005 — One App Store subscription entitles exactly one account

- **Status:** Accepted
- **Date:** 2026-08-09

## Context

An App Store subscription belongs to an Apple ID and a device. A Tuji account is something
else — the app offers three sign-in providers (email, Google, Apple), and users move
between them.

`PaywallView` calls `refreshFromCurrentEntitlements()` in its `.task`, which forwards the
device's active StoreKit entitlements to `/api/billing/verify` for **whoever is currently
signed in**. That is correct behaviour for a fresh install, but it also means:

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

Exactly one account may hold a given `original_transaction_id`. This is enforced two ways:

- **Structurally** — a UNIQUE partial index on `user_entitlements(original_transaction_id)`.
- **Behaviourally** — writing a subscription entitlement first *transfers* the binding:
  any other account holding that transaction id is set back to free, has its transaction id
  cleared, and gets a `transfer` row in the entitlement ledger. The whole thing runs in one
  transaction.

The semantics are deliberately "the subscription follows the account that most recently
proved it owns the purchase", not "the second attempt is rejected". Rejecting would leave a
user who genuinely migrated accounts unable to use the subscription they are paying for,
with no self-service way out.

A migration de-duplicates any existing conflicts before the unique index is created, since
this runs at build time and a failure there would block deploys.

## Considered options

- **Reject the second binding:** rejected because account migration is a legitimate,
  self-service-impossible situation. The user would be paying and locked out, and the only
  fix would be an operator intervention.
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

- A user who signs in to a second account and opens the paywall silently moves their Pro
  from the first account to the second. This is invisible in the app. The entitlement
  ledger records it as a `transfer`, and `/admin/members` shows it, which is currently the
  only way to explain a "my Pro disappeared" report.
- `getUserIdByOriginalTransaction` is now deterministic, so refunds and expirations always
  reach the account that actually holds the subscription.
- The migration that creates the unique index must keep running de-duplication first; a
  future code path that writes bindings without going through `upsertAtlasEntitlement`
  would break the build rather than corrupt data, which is the intended failure direction.
