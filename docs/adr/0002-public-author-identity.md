# ADR-0002 — Public Author profiles and authoritative identity edits

- **Status:** Accepted
- **Date:** 2026-08-02

## Context

An Author profile currently exists publicly only when an account has approved Atlas work:
the public read joins `profiles` to approved items, while iOS repairs the resulting 404 for
the signed-in user with a second authenticated read. Public identity is also duplicated
between `profiles`, auth session metadata, Web projections, and iOS fallback logic. This
allowed a stale session nickname to appear set while the public profile rendered the UID.

## Decision

Every registered account has a public Author profile immediately, including accounts with
zero public items. Profiles are addressable by exact UID or an existing link but are not
listed in author search, recommendations, or a public directory.

The server owns the one authoritative Author identity projection. It trims a nickname and
uses it as the display name when non-empty; otherwise it uses the immutable UID. Email is
never a public fallback. The avatar is the chosen public photo or the single default black
cat. Web and iOS render this projection rather than independently deriving identity.

A Profile edit is one operation over nickname, bio, and an optional avatar image. Nickname
and bio both pass public-text moderation. Registration creates only the UID and default
avatar; setting a nickname after authentication is optional. The edit commit point is a
readable new avatar object, when supplied, plus the authoritative `profiles` write. Session
metadata mirroring and obsolete-image cleanup are repairable derived work and do not change
the user-visible result. A successful edit returns the projected Author identity so clients
can update profile state and their last-successful cache immediately; without a cache, an
offline profile read fails explicitly rather than reconstructing identity from session data.

Web and iOS move to one Profile edit interface. Because there are no external TestFlight or
App Store users on old builds, the former separate avatar-upload route and legacy profile
write format are removed rather than kept as compatibility adapters.

Before zero-item profiles become public, one migration re-runs the new nickname moderation
policy over existing `profiles.nickname` values. Passing values remain; failing values are
cleared and fall back to UID. A nickname found only in auth session metadata is never copied
into `profiles`. This migration ships in the same first deployment as the authoritative
identity projection, before public visibility expands. The later stages deepen the server
Profile edit module, move iOS editing behind its own deep module, then simplify the own
Author profile loader by removing its 404 fallback workflow.

## Considered options

- **Keep profiles private until the first published item:** rejected because an Author
  profile is account identity, not a property of published work.
- **Let each client derive display names:** rejected because duplicated fallback rules caused
  the split-brain regression and provide no locality.
- **Require auth metadata mirroring and old-image deletion in the commit:** rejected because
  those systems cannot share a reliable transaction with the authoritative profile write.
- **Keep legacy route adapters for one release:** rejected because no external installed
  clients require the compatibility cost.

## Consequences

- A guessed valid UID can resolve an otherwise inactive account, but the product does not
  expose a directory or discovery interface for those accounts.
- Public Author reads must query account identity independently of approved Atlas work and
  return explicit empty collections and zero counts.
- Behavioral tests cross the same module interfaces as callers: identity projection,
  moderated Profile edit ordering, cache replacement, zero-item profiles, and repairable
  mirror or cleanup failures.
