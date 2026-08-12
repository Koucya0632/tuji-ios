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

## Amendment — 2026-08-03 (圖鑑管理 review)

Decision 3's trigger fired for the two screens it had left view-injected.
`AtlasCollectionCreateSheet` and `AtlasCollectionItemPicker` were "a single
fetch" when the rule was written; they had since grown validation, a
re-entrancy guard, and an optimistic mutation set — and the proof that nothing
could reach them was `FakeCollectionManaging.createCollection` throwing
`NotImplemented` in the tests. Both now sit behind `CollectionCreateModel` /
`CollectionCandidatesModel`. The rule is unchanged: split when a test needs the
narrower slice. `WordCommunityAtlasSection` is still genuinely one fetch and
stays view-injected.

The same review made `AtlasStore.init(repository:)` non-private. This is not a
retreat from decision 4 — `AtlasStore.shared` remains the lifecycle singleton
and `AuthService.signOut` still resets it. It is decision 1 applied honestly: a
seam defaulted to `.shared` that no test can construct is not a seam, and the
`AtlasAuthoring` protocol had been carved for exactly that purpose.

## Amendment — 2026-08-11 (AI 自製圖鑑 review)

The 2026-08-03 amendment was applied to `AtlasStore` and not to the module
behind it. `AtlasCaptureQueue` still had a `private init`, reached
`AtlasStore.shared` at four call sites and `FileManager` at five, and had zero
tests — while owning the confirm checkpoint, the one rule standing between a
resumed job and a duplicate 自製圖鑑 card. It is now constructed over
`AtlasCardGenerating` + `CaptureJobJournal` + `AtlasMutationRefreshing`, all
defaulted to the live adapters; `AtlasCaptureQueue.shared` remains the
lifecycle singleton and `AuthService.signOut` still resets it (decision 4).

Two notes for whoever applies this next:

1. **The rule generalises past the store.** When a seam is unsealed, unseal the
   modules that consume it in the same pass — an injected dependency that is
   dropped at the next handoff (here, `AtlasCaptureVM` injected its store and
   then enqueued onto `AtlasCaptureQueue.shared`) buys only the illusion of one.

2. **Fire-and-forget is an injection problem, not just a style one.** A seam
   reaches only as far as a test can await. `AtlasCaptureQueue.enqueue` now
   returns its `Task` and the queue exposes `settle()`; `AtlasCaptureVM`'s
   `requestRecognize` became `async` with the View owning the `Task`. Without
   that, the fakes were constructible and still could not be asserted on —
   which is how `FakeAtlasAuthoring` came to stub `uploadImage` / `recognize` /
   `confirm` with `NotImplemented` for as long as it did.
