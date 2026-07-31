# Tuji — domain & architecture glossary

Shared vocabulary for architecture reviews (`/improve-codebase-architecture`) and
domain modeling. Names for the good seams. Keep terms sharp; add lazily as they crystallize.

## Domain — the atlas (圖鑑)

- **自製圖鑑 (custom atlas)** — a user's own captured items. Created via the capture
  pipeline (photo → AI 識別 → 校正 → confirm). Capacity is quota-gated per tier.
- **公開圖鑑 (public atlas)** — items a user has submitted and that passed the
  moderation gate, visible to everyone. A *submission* is not a publish: the server
  gate may auto-publish, queue for a human, or reject (`AtlasPublishResponse.moderation`).
- **合集 (collection)** — an author's **named, curated set** of their own approved
  public items, scoped to one learning language. Browsed in 公開圖鑑, authored in 我的合集.
  Members can only be the author's already-approved public items (server-enforced).
  Publishing a collection re-runs the text gate on its title + 簡介.
- **Author profile** — a public page for one author: identity + their public items +
  cumulative save count (the altruistic signal).
- **Saving (收藏)** — the *consumption* path. Saving a public item does **not** consume
  the user's 自製圖鑑 capacity.
- **learning direction / target language** — the 合集 and 公開圖鑑 feeds auto-scope to the
  user's current learning language (日文 learners see 日文 collections). No manual switch.

## Architecture — seams & conventions

- **LiveAtlasRepository** — the concrete atlas HTTP client (in `AtlasRepository.swift`).
  There is **no** umbrella `AtlasRepository` protocol any more — it was a 25-method
  god-protocol with one real consumer, retired once the role seams below covered the
  need. The struct's surface reaches callers through focused role protocols (each
  conformed via a free `extension LiveAtlasRepository: Role {}`). **No screen binds to
  the concrete type any more** — the only members behind no seam are `publicFeed` and
  `deleteCollection`, which have no caller (ADR-0001 lazy-narrowing).
- **Role seams** — narrow protocols, one per consumer, so each consumer (and its test
  fake) depends only on the slice it uses.
  - **AtlasAuthoring** — 10-method authoring/sync pipeline used by `AtlasStore`
    (sync/upload/recognize/confirm/createCards/deleteImage/enrich/detail/entitlement/publish).
  - **CollectionEditing** — 5-method seam for the collection-edit screen
    (`collectionEdit`, `updateCollection`, `add/removeCollectionItem`, `publishCollection`).
  - **CollectionsBrowsing** — 1-method public-shelf seam used by
    `PublicAtlasBrowsingModel` (`publicCollections`).
  - **CollectionBookmarking** — private saved-shelf reads plus collection bookmark
    state/mutations; `PublicAtlasBrowsingModel` depends on it only for `savedCollections`.
  - **CollectionDetailReading** — 1-method seam for the collection detail (`collection(slug:)`).
  - **AuthorReading** — 1-method seam for the author profile (`author(username:)`).
  - **PublicItemsReading** — 1-method seam (`publicItems`) for `WordCommunityAtlasSection`
    (injected into the view; the trivial fetch stays there, no VM).
  - **AtlasItemConsuming** — save/unsave/report for one public item, used by `AtlasPublicDetailVM`.
  - **CollectionManaging** — myCollections/createCollection/collectionCandidates, one method
    each for `MyCollectionsVM`, `AtlasCollectionCreateSheet`, `AtlasCollectionItemPicker`.
- **Screen view model convention** — non-trivial screen logic (fetch / paginate / save /
  publish / form + async state) lives in an `@Observable @MainActor` view model,
  `@State`-owned by the View and injected with a narrow repository role via a default arg.
  The View is presentation-only; analytics stays in the View (VMs don't reach
  `AnalyticsService`). Exemplar: `AtlasCaptureVM` (+ `AtlasCaptureVMTests`). The community
  screens (合集 / 公開圖鑑) are on this pattern: `CollectionEditVM`,
  `PublicAtlasBrowsingModel`, `CollectionDetailVM`, `AuthorProfileVM`, `MyCollectionsVM`,
  `AtlasPublicDetailVM`. `PublicAtlasBrowsingModel` owns both the public and saved
  shelves, their refresh/authentication policy, and bookmark reconciliation; the View
  translates environment state into explicit model inputs. `CollectionDetailVM` exposes
  one `open(context:)` workflow for detail → owner → bookmark state → optional auto-save;
  confirmed bookmark mutations return a plain `BookmarkChange` for the View to broadcast,
  without refetching the detail. A
  screen whose only logic is a single fetch keeps the seam injected into the View instead
  (`WordCommunityAtlasSection`, `AtlasCollectionCreateSheet`, `AtlasCollectionItemPicker`) —
  ADR-0001 lazy-narrowing.
- **CommunityFeedRefresh** — an `@Observable` injected at the app root (`TujiApp`) that
  signals a just-published item/collection went live, so 公開圖鑑 bypasses its URLCache on
  its next appearance. Producers (publish flows) call `markNeedsReload()`; the feed
  `consume()`s it once. Replaces the former `AtlasFeedRefreshCenter` global singleton — the
  cross-view coupling is now an explicit environment dependency, not a hidden global.
- **CommunityLearningRefreshing** — one injected policy for a confirmed community-item
  save/unsave or collection batch-learn: invalidate `StudyQueueStore`, then await the
  best-effort `WordsStore.reload()`. The stateless live adapter is the only place that
  references those existing singletons; mutation success never depends on refresh success.

## Study — the SRS write path

- **DurableAnswerWriter** (`DurableAnswerWriting` seam) — the one home for the durable
  "retry a few times, then park in `StudyAnswerOutbox`" policy. `submitAnswer` is
  non-throwing and returns a `StudyWriteOutcome` — `.synced(StudyAnswerResponse)` (server
  accepted; mastery/milestone inside) or `.parked` (retries exhausted, parked for replay).
  Both study coordinators depend on it: `ReviewFlowCoordinator` folds the `.synced`
  mastery delta into its summary and bumps `unsyncedCount` on `.parked`; `NewFlowCoordinator`
  ignores the body and bumps `parkedCount`. Both surface the shared `UnsyncedAnswersNotice`.
- **LiveStudyRepository is now a pure network adapter** — one raw `submitAnswer(throws) ->
  response`, no retries, no outbox. Retrying/parking lives in `DurableAnswerWriter`; the
  outbox replay is the only other caller of the raw method (and must NOT re-park). This
  broke the former `StudyRepository ↔ StudyAnswerOutbox` cycle before it could block
  injection.

## Study — flow decisions live in the coordinators, not the views

- **Tile spell-check is a coordinator decision.** `NewFlowCoordinator` owns the tile
  selection model — `tilePicked`, `pickTile(_:for:)` (auto-checks when the board fills),
  `unpickTile(atSlot:)`, and the pure `tilesMatch(_:for:)` (assemble → compare against the
  target). `TilesView` reads `tilePicked` and forwards taps; only the flat-index-to-row
  *layout* stays in the view. The coordinator resets `tilePicked` on a correct advance /
  wrong requeue.
- **`StudyOptionRow` / `StudyOptionStyle`** — one shared MCQ option row + its
  right/wrong/answer/dim reveal logic (`StudyOptionStyle.forOption`), used by both
  `IdentifyView` (選字) and `ReviewFlowView` (複習). Replaced the two near-identical private
  `OptStyle` / `OptionStyle` copies.
- **StudyQueueProviding** — 1-method seam (`fetch(mode:)`) over `StudyQueueStore`, injected
  into `ReviewFlowCoordinator`. `fetchAnotherRound()` uses it for 再來一輪 so the view no
  longer reaches `StudyQueueStore.shared`; the view still spins up a fresh coordinator (a
  clean full reset beats resetting ~20 fields in place).
- **SessionRefresh** — the one home for "what a finished session refreshes, and when":
  `drain → invalidate → reload`, plus the conditional second drain for the last word's
  write. Behind `RefreshableStore { invalidate(); reload() async }` (conformed by
  Mastery/Progress/StudyStats), an `invalidateQueue` closure, and `PendingWriteDraining`
  (both coordinators). `NewDoneView` and `CompleteView` both call it — review **gains** the
  drain guard it previously lacked (its reload used to race the last answer's write). Both
  coordinators now track `pendingWriteRemaining` / `hasPendingWrites`.

## Dependency injection

- **Convention & singletons: see [ADR-0001](docs/adr/0001-di-and-singletons.md).** Inject
  dependencies as an `init`/`@Environment` seam defaulted to `.shared` (migration bridge);
  construct at the root only when a real second adapter exists. Prefer a narrow read seam
  over the whole store. Carve a role seam when a consumer's slice diverges; split a fat
  repository protocol only when a test needs the narrower slice (`BillingRepository` stays
  whole). Cross-cutting lifecycle glue (`AuthService`→`AtlasStore` reset, `NetworkMonitor`→
  outbox replay) deliberately stays `.shared`.
- **Read seams (settings/stats slices).** Modules that used to reach `SettingsStore.shared`
  / `StudyStatsStore.shared` inside their methods now inject a narrow read seam instead, so
  they're hermetically testable:
  - **LanguageContext** — `{ uiLang, learningDirection }`, conformed by `SettingsStore`.
    Injected into `LiveStudyRepository` (queue lang) and `LiveAtlasRepository`
    (upload/recognize/confirm lang + learning). Read live at call time (an in-app switch
    must take effect on the next request).
  - **StudyQueueInputs** — `{ learningDirection, dailyGoal, studyCategories, due }`, the
    slice `StudyQueueStore` folds into its queue params + cache signature. `LiveStudyQueueInputs`
    is the live adapter over settings + stats; `StudyQueueStore.init` is now injectable so a
    test can assert a direction switch busts a warm entry.
