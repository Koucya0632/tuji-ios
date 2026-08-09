# Tuji — domain & architecture glossary

Shared vocabulary for architecture reviews (`/improve-codebase-architecture`) and
domain modeling. Names for the good seams. Keep terms sharp; add lazily as they crystallize.

## Domain — the atlas (圖鑑)

- **自製圖鑑 (custom atlas)** — a user's own captured items. Created via the capture
  pipeline (photo → AI 識別 → 校正 → confirm). Capacity is quota-gated per tier.
- **Pipeline status (`AtlasImageStatus`)** — where an uploaded capture sits in card
  generation: uploaded / processing / needs_review / confirmed / cards_ready / failed /
  deleted. Distinct from the **review status** (`AtlasReviewStatus`), which is about the
  public moderation gate. `confirmed` and `cards_ready` imply a confirmed item exists;
  a row in one of those states with no joined item is a *sync* gap, not an unfinished
  capture — the two must never be conflated (未完成 used to sit next to 已完成).
- **Shelf** — what 圖鑑管理's 卡片 tab shows: the account's captures joined to their
  confirmed items, scoped to the current learning direction. Its state is one of
  loading / loaded / failed / hiddenElsewhere / empty; `failed` and `empty` are
  deliberately different, because a failed sync claiming 「還沒有卡片」 reads as data loss.
  **Loaded wins**: once rows are on screen a reload must not swap them for a spinner —
  the answer you already have beats the one you are re-fetching. `MyCollectionsVM` is on
  the same rule (and coalesces the duplicate refresh that returning from 編輯合集 fires).
- **公開圖鑑 (public atlas)** — items that entered review with a collection and passed
  the moderation gate, visible to everyone. The app has no separate per-item submission
  action; publishing a collection submits its private members as one batch.
- **物見 (the UI name for the public half)** — what the third tab is called on screen,
  and the only name for this area a user ever sees: the tab, the author-side publish and
  withdraw copy, and the saved-cards theme all say 物見. 公開圖鑑 and `community` are the
  *domain and code* names for the same thing and stay that way. This split is deliberate:
  `"community"` is a wire value (the category id on the server and on stored user rows),
  so renaming the identifiers could only ever be half done, and a half-renamed codebase
  reads worse than a consistently old-named one. Anything a user reads says 物見;
  anything a compiler or the database reads says `community`.
- **合集 (collection)** — an author's **named, curated set** of their own confirmed
  atlas items, scoped to one learning language. Browsed in 公開圖鑑, authored in 我的合集.
  Approved, pending, and private members can be added; rejected, taken-down, unfinished,
  and deleted items cannot. Publishing submits unpublished members with the collection,
  and the set becomes public only after every member and the collection content pass review.
  Its square avatar
  photo is public and separate from the legacy member-derived cover/background image,
  which new screens do not render. The derived safe color is only the avatar's loading
  and legacy fallback.
- **Author profile** — a public page for every registered account: identity + their
  public items + cumulative save count (the altruistic signal). It exists independently
  of published work and is created as soon as registration completes, so an account with
  zero public items still has an Author profile. No separate publication or consent state
  activates the page. It is addressable by exact UID or an existing link but is not listed
  in author search, recommendations, or a public directory. Registration creates it with
  the UID and default black cat avatar; a public nickname is a later Profile edit.
- **Author identity** — the public identity rendered on an Author profile and its bylines.
  A nickname is optional. Its display name is the trimmed nickname when one exists,
  otherwise the immutable UID.
  The UID remains separately visible and an email address is never a public fallback. Its
  avatar is either the author's chosen photo or the single default black cat avatar. A
  nickname is public text and must pass the same moderation policy whenever it is set.
- **Profile edit** — one requested change set for the public nickname, bio, and avatar.
  An accepted edit becomes visible as one Author identity change; a rejected edit leaves
  the previous Author profile intact rather than exposing a partial change. Acceptance is
  determined by the authoritative public profile, not by derived session mirrors or cleanup.
- **The four keeping actions.** The code has told these apart from the start
  (`favorite` / `bookmark` / `save` / `learn`, four endpoints, no overlap); the *UI* still
  calls all four 「收藏」, which is why the word means four things on screen. The names
  below are the resolved vocabulary — adopt them as the UI is rewritten, and never widen
  one to cover another. They differ along two axes: *what object* (a word or a collection)
  and *what intent* (keep it, or learn it). The distinction is load-bearing, because only
  the learning half changes what the user is asked to review tomorrow.
  - **書籤 (bookmark a word)** — "I want to look at this word again." A dictionary word,
    device-local truth, never reaches the study queue. Guests have it too.
  - **收藏 (save a collection)** — "I want this collection." It is *not* merely a marker:
    it unlocks browsing every member and counts toward the author's cumulative save count
    (the altruistic signal on their Author profile). It creates no cards.
  - **收進圖鑑 (take a public item into your atlas)** — "I want to learn this word." The
    *consumption* path: it creates study cards and changes tomorrow's review queue.
    It does **not** consume the user's 自製圖鑑 capacity — that quota only counts what
    the user photographed.
  - **全部收進圖鑑 (take a whole collection in)** — the same act, in bulk, over a
    collection already 收藏'd. Available only once unlocked.
- **取消公開 (withdraw)** — the author's own way to pull a public item back. It exists
  because the alternative — deleting the card — destroys **every saver's review progress**,
  not just the author's own history. Withdrawal is reversible and carries no penalty, which
  is why it is not a moderation takedown and must never be presented as one.
- **Streak (連勝)** — accumulated study days. It belongs to *accumulation*, alongside
  mastery and completion — not to "what to do now" — even though its product purpose is to
  pull the user back today. The distinction matters because the visual system assigns one
  colour per meaning.
- **learning direction / target language** — the 合集 and 公開圖鑑 feeds auto-scope to the
  user's current learning language (日文 learners see 日文 collections). No manual switch.

## Domain — 方案與權限 (plan & entitlement)

- **訂閱 (subscription)** — an auto-renewable App Store purchase. Apple owns its whole
  lifecycle: renewal, cancellation and **refund all arrive as notifications and downgrade
  the user automatically**, so there is no such thing as manually cancelling someone's
  subscription and no operator action should ever claim to. It belongs to an Apple ID, not
  to a Tuji account, which is why binding it to an account is a decision (ADR-0005) rather
  than a fact.
- **贈與 (grant)** — Pro given by an operator: a comp, apology credit, reviewer access.
  Independent of any 訂閱, carries a mandatory reason, and is append-only — revoking marks
  a grant dead rather than erasing it, because "why was this person Pro last March" has to
  stay answerable. Revoking a 贈與 never cancels a 訂閱.
- **生效權限 (effective entitlement)** — the union of 訂閱 and 贈與: Pro if *either* is
  live, and the later expiry wins. This is the only thing that gates a feature. The two
  sources are never merged into one stored value — merging them is what used to let a
  compensation shorten a subscriber's real expiry, and let Apple's next renewal erase the
  compensation (ADR-0004). Everything user-facing reads 生效權限; anything asking "is this
  person a *customer*" must read 訂閱 specifically, because a comped account is not revenue.
- **權限異動紀錄 (entitlement ledger)** — the append-only history of 生效權限 transitions.
  Both source tables are mutated in place, so this is the only history that exists, and it
  cannot be backfilled. It answers questions about *our* users; App Store Connect remains
  the authority on money (revenue, refunds, churn) and is not duplicated here.
- **`EffectiveEntitlementReading`** — the iOS read seam for 生效權限, and the only place a
  screen may ask "is this account Pro". Its rule is a pure `resolve(serverPlan:devicePurchase:)`
  mirroring the server's: the server snapshot wins **in both directions whenever it exists**,
  and the device-local `StoreKitService.isPro` stands in only while it is `nil`. That flag is
  *purchase* state — a transaction on this Apple ID and device — so it reads false for a 贈與
  and true for a subscription since re-bound elsewhere; treating it as 生效權限 is what made
  設定 offer 「升級」 to accounts that already had Pro. `StoreKitService` keeps it for the
  paywall's own purchase/restore flow and nothing else.

## Architecture — seams & conventions

- **LiveAtlasRepository** — the concrete atlas HTTP client (in `AtlasRepository.swift`).
  There is **no** umbrella `AtlasRepository` protocol any more — it was a god-protocol
  with one real consumer, retired once the role seams below covered the need. The struct
  has since grown to 38 methods, which is the point: the seams below carve it, nothing
  re-declares it whole. Its surface reaches callers through focused role protocols (each
  conformed via a free `extension LiveAtlasRepository: Role {}`). **No screen binds to
  the concrete type any more** — the only member behind no seam is `publicFeed`, which
  has no caller (ADR-0001 lazy-narrowing).
- **Role seams** — narrow protocols, one per consumer, so each consumer (and its test
  fake) depends only on the slice it uses.
  - **AtlasAuthoring** — 10-method authoring/sync pipeline used by `AtlasStore`
    (sync/upload/recognize/confirm/createCards/deleteImage/enrich/detail/entitlement/withdraw).
  - **CollectionEditing** — 7-method seam for the collection-edit screen
    (`collectionEdit`, `updateCollection`, `updateCollectionAvatar`,
    `add/removeCollectionItem`, `publishCollection`, `withdrawCollection`).
  - **CollectionsBrowsing** — 1-method public-shelf seam used by
    `PublicAtlasBrowsingModel` (`publicCollections`).
  - **CollectionBookmarking** — private saved-shelf reads plus collection bookmark
    state/mutations; `PublicAtlasBrowsingModel` depends on it only for `savedCollections`.
  - **CollectionDetailReading** — 1-method seam for the collection detail (`collection(slug:)`).
  - **AuthorReading** — 1-method seam for the author profile (`author(handle:forceReload:)`).
  - **PublicItemsReading** — 1-method seam (`publicItems`) for `WordCommunityAtlasSection`
    (injected into the view; the trivial fetch stays there, no VM).
  - **AtlasItemConsuming** — save/unsave/report for one public item, used by `AtlasPublicDetailVM`.
  - **CollectionManaging** — myCollections/createCollection/deleteCollection/
    collectionCandidates, used by `MyCollectionsVM`, `CollectionCreateModel` and
    `CollectionCandidatesModel`.
- **AtlasStore is substitutable.** Its `init(repository: AtlasAuthoring)` is *not*
  private — the `AtlasAuthoring` seam only pays for itself if a test can stand a store
  up over a fake, and while `init` was private `AtlasStore.shared` was the only instance
  that could exist, so the seam bought nothing and the store had no tests. Production
  still goes through `.shared` (ADR-0001). The store owns `itemsByImageId` (the join the
  manage screen does per row) and keeps no card/card-state/mastery arrays — nothing read
  them. `sync(_:)` takes an explicit **`AtlasSyncScope`** (`.incremental` / `.full`);
  `since: nil` used to fall through to the stored cursor, so callers that asked for a
  full reconcile silently got an incremental one.
- **AtlasShelfModel** — the 圖鑑管理 卡片 screen's model: the image→item join, the
  learning-direction filter, `hiddenCount`, the `AtlasShelfState`, the selection set
  (reconciled against visible rows when the direction changes), the batch delete, and
  取消公開. The three View structs that used to hold this each kept their own
  `@State AtlasStore.shared` and re-derived the same values.
- **AtlasMutationRefresh** — one policy home for what a 圖鑑管理 mutation refreshes.
  Producers name what the user did (`AtlasMutation`: itemsDeleted / captureCompleted /
  itemWithdrawn / collectionPublished / collectionWithdrawn / collectionDeleted /
  collectionAvatarChanged); the module decides the consequences via two predicates —
  `changesOwnAtlas` (words + progress + stats reload, then `refreshEntitlement`) and
  `invalidatesPublicFeed`. `LiveAtlasMutationRefresher(feed:)` takes `CommunityFeedRefresh`
  because that signal is a root-constructed environment value a model cannot reach; the
  View supplies it and names nothing else. The authoring-side counterpart to
  `CommunityLearningRefreshing` (consumption) and `SessionRefresh` (study).
- **AvatarPicker** — the shared 頭像 flow (source dialog → PhotosPicker/camera → crop →
  encode → deliver → retry), applied by the `.avatarPicker(_:title:)` modifier. Two
  adapters justify the seam: 合集 and 個人資料 differ only in `AvatarEncoding` (1600/0.82
  vs 1200/0.86), the crop mask, and what "deliver" means. It carries one error line —
  the two screens used to run two parallel error channels, and 合集 rendered
  `CollectionEditVM.errorMessage` (defined as "a failed publish wins") as an upload error.
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
  without refetching the detail. The 圖鑑管理 screens are on the pattern too
  (`AtlasShelfModel`, `CollectionCreateModel`, `CollectionCandidatesModel`). A
  screen whose only logic is a single fetch still keeps the seam injected into the View
  instead (`WordCommunityAtlasSection`) — ADR-0001 lazy-narrowing. `AtlasCollectionCreateSheet`
  and `AtlasCollectionItemPicker` used to qualify and no longer do: see
  [ADR-0001](docs/adr/0001-di-and-singletons.md) → amendment.
- **CommunityFeedRefresh** — an `@Observable` injected at the app root (`TujiApp`) that
  signals a just-published item/collection went live, so 公開圖鑑 bypasses its URLCache on
  its next appearance. Producers (publish flows) call `markNeedsReload()`; the feed
  `consume()`s it once. Replaces the former `AtlasFeedRefreshCenter` global singleton — the
  cross-view coupling is now an explicit environment dependency, not a hidden global.
- **MyCollectionsCache** — an app-lifetime, account-scoped home for the 我的合集 rows. A
  screen view model is `@State` on a View that SwiftUI throws away on pop, so a
  view-scoped list meant every return to 圖鑑管理 started from an empty list and a
  spinner, re-answering a question answered seconds ago — 圖鑑卡片 never did, because it
  reads `AtlasStore`. The rule the two share: **state whose lifetime is the account
  belongs to the account, not to the screen that happens to show it.** `reset()` runs on
  sign-out beside `AtlasStore.reset()`, or the next account inherits the rows.
- **CollectionIdentityStore** — an app-root `@Observable` overlay for the last accepted
  collection avatar URL and fallback color. `CollectionIdentityTile` resolves the latest
  uploaded photo → server photo → derived/stable color fallback, so list, saved shelf,
  author profile and detail update immediately. It never reads the separate legacy cover.
- **CommunityLearningRefreshing** — one injected policy for a confirmed community-item
  save/unsave or collection batch-learn: invalidate `StudyQueueStore`, then await the
  best-effort `WordsStore.reload()`. The stateless live adapter is the only place that
  references those existing singletons; mutation success never depends on refresh success.
- **Cache identity ≠ fetch authorisation** (`URL.signedStorageObjectID`). 自製圖鑑 lives in
  a private Supabase bucket, so every API response signs a fresh URL: same object, new
  `token=`. Nuke keys both cache tiers on the URL, so the 500 MB DataCache never scored a
  hit on a user's own captures. The signature authorises the fetch; it does not identify
  the picture — so `TujiImagePipeline` keys on everything *but* the signature, and leaves
  Nuke's default key alone for anything that isn't a signed storage URL.

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
