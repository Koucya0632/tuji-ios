# ADR-0001 — Dependency injection & the singleton graph

- **Status:** Accepted
- **Date:** 2026-07-28
- **Context:** the "整體架構" review (`/improve-codebase-architecture`), which
  planned a six-part refactor arc. This ADR records the decisions that govern
  the arc's seam and injection style so future architecture reviews don't
  re-litigate them.

## Context

Almost every module in the app is a process-global `static let shared`
(~26 of them). "Injection" comes in two cosmetic flavours: init parameters that
default to `.shared`, and `@Environment` objects that hold the `.shared`
instance. Only `CommunityFeedRefresh()` is a genuinely fresh instance. A prior
review flagged this as a candidate to "remove the singletons," but the graph is
load-bearing for cross-cutting lifecycle glue:

- `AuthService.signOut` resets `AtlasStore.shared` (clear per-account state).
- `NetworkMonitor` and `TujiApp`'s scenePhase replay `StudyAnswerOutbox.shared`.

Removing the singletons wholesale would **move** this wiring into a hand-built
composition root, not delete it — high blast radius for a solo-scale app, and
no test or preview substitutes a store today regardless.

## Decision

1. **Injection convention.** A module that depends on another accepts it as an
   `init` parameter (or, for stores, an `@Environment` value) **defaulted to
   `.shared`**. The default is a *migration bridge*, not the design goal: it
   keeps call sites terse while making the dependency substitutable at the seam.
   Construct a dependency at the root (no `.shared`) only when a real second
   adapter exists — the `CommunityFeedRefresh` precedent. One adapter is a
   hypothetical seam; two is a real one.

2. **Prefer a narrow read seam over the whole store.** When a module needs only
   a slice of a store's state, depend on a small role protocol the store
   conforms to (e.g. `LanguageContext`, `StudyQueueInputs`), not the concrete
   store. Test fakes then stub two properties, not a whole `@Observable` class.

3. **Lazy narrowing of fat protocols.** A one-to-one `protocol XRepository` +
   `struct LiveXRepository` is shallow indirection, but splitting all of them
   into role seams up front is speculative. Rule: **carve a role seam when a
   consumer's slice actually diverges**, and split a fat protocol the next time
   a test needs the narrower slice. `BillingRepository` (one method) stays whole.

4. **Keep the cross-cutting lifecycle singletons.** `AuthService`,
   `AtlasStore`, `StudyAnswerOutbox`, `NetworkMonitor`, and the app-root stores
   remain `.shared`. Their reset/replay wiring is deliberate app-lifecycle glue.
   Revisit only if the app grows to need multiple isolated store graphs (e.g.
   multi-account, or a hosted test harness) — the trigger for building a real
   composition root.

## Consequences

- The refactor arc removes *specific* static reach-ins (a repository reaching
  `SettingsStore.shared`, a coordinator reaching `StudyQueueStore.shared`) by
  turning them into injected seams — it does **not** attempt a big-bang removal
  of `.shared`.
- New code follows the convention: accept dependencies as defaulted seams;
  reach for `.shared` statically only inside lifecycle glue.
- A future reviewer who proposes "delete the singletons" should read this ADR
  first: the answer is "by attrition, behind seams — and never the lifecycle
  glue in decision 4 until its trigger fires."
