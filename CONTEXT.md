# Tuji — domain & architecture glossary

Shared vocabulary for architecture reviews (`/improve-codebase-architecture`) and
domain modeling. Names for the good seams. Keep terms sharp; add lazily as they crystallize.

## Domain — the atlas (圖鑑)

- **自製圖鑑 (custom atlas)** — a user's own captured items. Created via the capture
  pipeline (photo → AI 識別 → 校正 → confirm). Capacity is quota-gated per tier.
- **生成佇列 (`AtlasCaptureQueue`)** — the durable tail of a capture: confirm →
  createCards → enrich → one reconciling read, run after the sheet closes so the user
  never waits. Jobs are journalled, so an app kill mid-flight resumes on launch. The
  load-bearing rule is the **confirm checkpoint**: confirm is a plain INSERT server-side
  and *not* idempotent, so the itemId it returns is written to the journal before the
  (idempotent) tail runs, and a resumed job that finds one skips confirm. Everything it
  reaches is an init parameter — `AtlasCardGenerating` (the four-method 生成卡片 seam
  carved off `AtlasStore`), `CaptureJobJournal` (the on-disk half), `AtlasMutationRefreshing`.
  It had a `private init` and four `AtlasStore.shared` reach-ins, so the checkpoint rule —
  the only thing between a resumed run and a duplicate card — was verified by nothing.
- **拍照進度 (`CaptureProgress`)** — where one capture sits, in the single vocabulary
  every screen reads: generating / enriching / ready / failed, plus the label and the
  determinate fraction. A third status vocabulary used to exist beside `AtlasImageStatus`
  and `AtlasReviewStatus` — the queue's own `Stage` — and nothing related them, so the
  卡片 grid said 「生成中」 about a photo 圖鑑管理 was calling 「已上傳」. **The in-flight
  job wins over the server row**, because a job still running knows something the row it
  has not written yet cannot. `AtlasShelfRow.inFlight` is where the two meet.
- **`CaptureFailure`** — why a capture stopped, in the only two kinds a screen must tell
  apart: `.atCapacity` (another attempt fails the same way — no 重試 offered) and
  `.transient`. The queue's `catch` used to flatten every error into one untyped failure,
  so a spent quota wore a retry's costume; the paywall route the VM builds for a 402
  during 識別 had no counterpart after enqueue.
- **`AtlasCapacityReadout`** — 自製圖鑑 room as the capture flow must ask it: the server's
  usage snapshot **plus the captures 生成佇列 has not finished**. Two things consume a
  slot and the gate counted one, so at capacity − 1 two quick captures both passed and
  the second died in the queue. `AtlasQuotas` stays the pure mirror of the server's
  arithmetic (lib/atlas/entitlement.ts); this is the reading built on it. Slots held by
  the queue say 「正在生成」 rather than 「刪除一些」 — waiting is what actually works.
- **校正欄位 (`CaptureCorrectionFields`)** — which second field the correction form asks
  for (`chineseName` / `gloss` / `hidden`), over the {UILanguage × TargetLanguage} grid.
  `needsGloss` — whether a cached candidate is missing the meaning that field would show,
  and so worth one repair call — is *derived from* the field rather than stated beside it.
  The two were written separately, as exact complements (`monolingual` in a View computed
  property, `needsSeparateGloss` in the VM), and one of them was unreachable from a test.
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
- **刪除合集的警告 (`CollectionDeleteWarning`)** — what deleting a 合集 costs, in the only
  three kinds the warning must tell apart: `cancelsReview` (in review — the submission is
  withdrawn before anyone sees it), `takesDownFromPublic` (live on 物見 — it goes for
  everyone, immediately) and `privateOnly` (nothing outside the account changes). Three
  *different promises*, and it is the last sentence an author reads before an irreversible
  button — so it is a decision, not copy, and it lived as a `private func` on a `View`.
  已收回 (`withdrawn`) is `privateOnly`: warning about a takedown that already happened
  misdescribes what the button does. Original 圖鑑 cards are never affected, whichever it is.
- **取消公開 (withdraw)** — the author's own way to pull a public item back. It exists
  because the alternative — deleting the card — destroys **every saver's review progress**,
  not just the author's own history. Withdrawal is reversible and carries no penalty, which
  is why it is not a moderation takedown and must never be presented as one.
- **Streak (連勝)** — accumulated study days. It belongs to *accumulation*, alongside
  mastery and completion — not to "what to do now" — even though its product purpose is to
  pull the user back today. The distinction matters because the visual system assigns one
  colour per meaning.
- **完成度 (`CompletionReadout`)** — how far through the selected 學習主題 the account is:
  seen / total, plus the clamped ratio and the percentage rendered from it. The
  denominator is **always scoped to the selection** — server count when there is one,
  else the locally known dictionary *within the same selection*. Falling back to the
  whole dictionary is the bug this module was built around: it fires not only for guests
  (who never have server rows) but whenever the picked themes hold no published cards, so
  自定義 + 物見 read 「已學 0 / 共 480 字」, a denominator describing a selection nobody
  made. Three states the two screens used to answer differently: a **guest**'s progress is
  the local learned set, not the empty server rows; **no themes picked** reads 0 / 0 to
  match the 選擇主題 empty state rather than widening to every category; and `seen > total`
  is reachable (seen counts studied words, total counts *published* cards, so a 取消公開
  leaves the difference), which is why the ratio clamps and the percentage is derived from
  it rather than computed beside it. One module answers 首頁's 主題進度 and 我's 完成度 card.
  `CompletionReadout.ratio(seen:total:)` is the only seen/total ratio in the app — there
  were five copies and two skipped the clamp.
  **The reading is one too.** `CompletionReadout.Inputs.init(viewer:settings:progress:words:cache:)`
  is the single mapping from the stores to the eight facts; it was hand-written three
  times (首頁 assembling `TodayDecisions.Inputs`, `TodayDecisions` copying eight of its
  eleven fields across again, 我 assembling its own), two of them inside `View` bodies
  where nothing could check the two screens asked the same question — and once they did
  not. `TodayDecisions.Inputs` now *composes* it (`completion` + the three fields that are
  genuinely 首頁's: `dailyGoal` / `stats` / `progressLoaded`). **The stores are parameters,
  not properties**: reading them inside the View's body evaluation is what registers the
  `@Observable` dependency, so a module that fetched them itself would read the same
  numbers and silently stop the screen from updating. Two of the five are seams —
  `StudySelectionReading` (the 學習主題 selection + `settingsLoaded`, which travel together
  because the selection is the scope every number is measured against) and
  `GuestProgressReading` (one integer, because `LocalCache.init` is private and `.shared`
  is the only instance that can exist).
- **learning direction / target language** — the 合集 and 公開圖鑑 feeds auto-scope to the
  user's current learning language (日文 learners see 日文 collections). No manual switch.
- **當前圖鑑語言 (`\.targetLanguage`)** — the session's target language as a *screen* sees
  it: one environment value, supplied once at `TujiApp` from `SettingsStore`. Four 圖鑑
  screens each used to derive it themselves and by four different mechanisms — pushed into
  a model on `onAppear`, recomputed per render, baked into a `.task(id:)` string — and the
  derivation was written out ten times. `AtlasShelfModel` still takes it as an explicit
  input rather than reaching for the store, but the input is now optional: a `@State` model
  is built before SwiftUI can hand it the environment, and it used to answer `.ja` in that
  gap, filtering an 英文 learner's own cards against the language they are not learning.
- **A word's language is a total question** (`language(in:)` on `LanguageTagged`) — the
  server tag wins, else a kana `reading` marks it Japanese, else 當前圖鑑語言 decides. The
  raw half stays visible as `taggedLanguage` for the payload-level tests and for
  `PronunciationButton`, whose subject may be a sentence rather than a word. It was
  formerly `wordLanguage: TargetLanguage?` with the fallback documented as the caller's
  job: 11 of 13 callers never did it, so an untagged word — commonest source: a
  just-captured 自製圖鑑 card — read as English in the font, the wrapping, the MCQ
  distractor pool, and the ruby/IPA choice.
- **拼字題目 (`SpellSubject`)** — what the 拼字 stage asks for: `.reading` (a kana reading
  distinct from the term — 排出這個字的讀音) or `.term` (拼出這個字). Deliberately *not* the
  language question, which it was masquerading as: ねこ is Japanese and its 振假名 is
  itself, so the stage quizzes the 詞形. The two agree on most words and part company on
  exactly the words that make 振假名 subtle.
- **補充 (enrichment)** — the AI pass that fills a captured item's 釋義, 助記, 詞源 and the
  per-language gloss. One pass is three to four paid model calls, not one. Its states live in
  `backfill_status`: `pending` → `filled`, or `failed` (this attempt broke — try again) → after
  `ATLAS_ENRICH_MAX_ATTEMPTS`, `skipped` (**we have given up on this one**). That second line —
  transient versus terminal — is the same one iOS already draws in `CaptureFailure`; the server
  had `skipped` declared in its schema CHECK and never wrote it, so `failed` carried both
  meanings and the retry decision had no memory. **Whether this item should cost money is one
  question with one answer: `shouldEnrichAtlasItem` (`lib/atlas/enrich-policy.ts`, kept clear of
  the AI SDK so a route handler or a test can ask it).** It was written out three times, twice on
  a paying path, and one of those spellings (`backfill_status !== 'filled'`) was true forever
  once an item failed, so a reliably-failing item re-ran the whole paid pass on every 詳情 open.
  A `skipped` item degrades to name-and-image, which is a shape the product already accepts.
  Raising `ATLAS_ENRICH_VERSION` revives `skipped` and zeroes the count — `skipped` means
  「用這一版配方試不出來」, so a new recipe earns a fresh round. See docs/adr/0011.

## Domain — 日文詞條

- **振假名 (reading)** — how a Japanese headword is read, written as furigana: kanji are
  spelled out in hiragana and anything already kana is copied exactly as it appears, so
  バスマット reads バスマット and シャンプー keeps its ー. A headword written entirely in
  kana is therefore **its own** reading, which is why printing one under itself says
  nothing. It is not a transcription and not a romanisation.
- **切分 (reading segments)** — which kana belong to which characters of the headword: a
  list of ranges, each with the kana read over it. Per-character is simply the case where
  a range is one character long; 熟字訓 like 時計 cannot be divided at all and take one
  range across both characters, so "one range, one ruby" is the shape and 逐字 is an
  outcome, not a guarantee. Derived from the 振假名 against a dictionary and never a
  substitute for it — the 拼字 stage still quizzes the whole string.
  _Avoid_: furigana (ambiguous — it names the 振假名 as often as the split).
- **`TujiHeadword` / `TujiReadingLine`** — the one home for how a headword is presented:
  ruby vs line vs nothing, the single 26pt size, whether the word may wrap, and the
  phonetic line's face (IPA is Latin and belongs in the mono face; kana does not). Takes
  the `Headworded` word, not three values derived from it — five screens used to assemble
  `display:`/`word:`/`language:`, then unpack `HeadwordDisplay` again and re-decide the
  language for the line's font. Where the line *sits* is still each screen's call (beside
  the part of speech, or a row of its own), which is why `TujiReadingLine` is separate and
  keeps an `ink` parameter — that one tracks placement, not language. The 圖鑑 grid
  (`WordTile`) stays outside both, by [ADR-0006](docs/adr/0006-furigana-segmentation.md):
  ruby at 18pt lands under the CJK floor.

## Domain — 例句標註

- **詞塊 (`GlossSpan`)** — 一個可讀句子裡的一個單位，以及掛在它上面的東西：這個詞**在這句話裡**
  的意思、原形、詞性、日文讀音，命中目錄詞時再加一個 `wordId`。刻意不是「一個詞」——
  `look forward to` 是一塊，因為對學習者它是一個單位，而把中間那個 `to` 單獨翻成「到」不是
  沒用而是錯的。片語邊界要看得懂整句才判得出來，這正是[ADR-0009](docs/adr/0009-example-sentence-annotation.md)
  把切分放在伺服器、而不是交給裝置上免費的 `NLTagger` 的第二個理由（第一個是：原形查出來
  之後沒有字典可以查——Tuji 的字典是 480 個有圖片的策展詞頭，`quickly` 永遠不會有詞條）。
- **有釋義 = 可點。** 不存在 `isTappable`。虛詞與標點就是沒有釋義的詞塊，而**這件事跟介面
  語言無關**：某個詞塊缺 ja 釋義時退回 zh-Hant，不是變成不可點——否則同一句話在日文介面會
  少掉一半可以點的字，而使用者只會當成 bug。
- **例句標註 (`SentenceAnnotation`)** — 一句話的那一串詞塊，**全覆蓋**：每個字元都落在某一
  塊裡，串起來必須一字不差地重寫出原句。跟 **切分 (reading segments)** 是同一條不變量，理由
  也同一條——可驗的部分要驗。因此客戶端**從不對字串做索引**（它逐塊接成 `AttributedString`），
  兩邊也就不需要對「一個字元是什麼」達成共識（JS 數 UTF-16、Swift 的 `Character` 是 grapheme
  cluster、Postgres 數 code point，三者在組合字上會分家）。串不回原句就整句作廢、退回純文字：
  那是這個功能唯一的失敗模式，而它剛好等於功能上線前的樣子。
- **以句子為鍵，不是以列為鍵。** 標註是那個字串的性質，所以 `sentence_spans` 的主鍵是
  (語言, 句子, 序號)，例句與**譯義**（`targetDefinition`）共用同一張表：同一句話標一次，
  在哪裡出現都通。中文釋義那行刻意不標——對中文讀者標中文教不到東西，而 ja/en 介面根本不會
  渲染那一行。句子被改寫時舊標註自然對不上而退回純文字，**沒有比標錯好**。
- **詞塊不連回當前頁面。** 例句與譯義都會提到自己的詞頭（例句正是為了示範它），所以最好點的
  那一塊會讓「看完整詳情」把同一頁再推一次。伺服器端的 `unlinkSelfReference` 拔掉那個
  `wordId`——**塊還是可點的，只是少一顆按鈕**，因為可點與否從來只看有沒有釋義。
- **原形 (`baseForm`)** — `running` 的 `run`。**不叫 `lemma`**：這個 codebase 裡 `lemma` 已經
  是自製圖鑑 item 的詞頭（`atlas_items.lemma`、confirm API 的必填欄位、`AtlasItemRow.lemma`），
  同一個字在同一份程式碼裡有兩個意思，是下一個人一定會踩的坑。
  _Avoid_: lemma（已被佔用）、詞根（那是 etymology 的事）。

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

## Navigation

- **NavRoute + the destination table** (`tujiNavDestinations`) — the single place that
  decides *what a route means*. It always claimed to be, and for a long time it was not:
  21 of the app's 37 pushes bypassed it and constructed their own screen, so the same
  destination arrived 2–4 different ways with divergent arguments. That cost two shipped
  bugs — 檢舉/封鎖 offered on your own profile (an `isSelf: Bool = false` default two call
  sites inherited), and a `saved:` tile opening a different screen on tap than on
  long-press. Routes carry preview models where a destination needs one; a defaulted
  answer to "is this me" is not allowed, so `isSelf` has no default.
- **TabNavigator** — the tab shell's navigation state (four `NavigationPath`s, selected
  tab, per-tab `atRoot`, the pending 圖鑑 source filter) and the one way to push. It lives
  in the environment because the paths *being private to `MainTabsView`* is precisely why
  screens bypassed the table: a screen with no path to append to had no way to push a
  route. `push(_:)` targets the selected tab; `push(_:on:)` names one.
- **TabShellDecisions** — the three shell policies as pure functions: what a pending deep
  link does, whether the tab bar shows, whether the pager may swipe. Two of them exist
  because they were wrong once — the swipe guard read `NavigationPath.count`, which sees
  only value pushes, so a `navigationDestination(item:)` push left the pager live on top
  of a pushed screen; and a guest's auto-save collection intent must be *held* through the
  sign-in root swap rather than consumed.
- **`atRoot`, not `NavigationPath.count`** — the one signal for "is something on top of
  this tab". The count only counts value-based pushes, and the two answers disagreed.

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
  - **AtlasCardGenerating** — the 4-method 生成卡片 tail used by 生成佇列
    (confirm / generateCards / enrich / reconcile), conformed by `AtlasStore`. Narrower
    than `AtlasAuthoring` on purpose: the queue discards the card list `createCards`
    returns and always reconciles `.full`, so neither the return value nor the scope
    belongs on the seam.
  - **CaptureJobJournal** — 生成佇列's on-disk half (save / remove / restore / removeAll),
    with `FileCaptureJobJournal` over Application Support. Split out because the confirm
    checkpoint is the pipeline's load-bearing rule and it lived behind a hard-coded path.
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
- **取像 (`ImageIntake`)** — the shared "get a photo in" flow (source → PhotosPicker/camera
  → 350 ms cover beat → crop → encode → deliver → park-and-retry), applied by the
  `.imageIntake(_:title:)` modifier. **Three** adapters: 合集, 個人資料 and 拍照新增 differ
  only in `ImageIntakeEncoding` (1600/0.82, 1200/0.86, 1600/0.78), which cropper they
  present, and what "deliver" means. It carries one error line — the screens used to run
  two parallel error channels, and 合集 rendered `CollectionEditVM.errorMessage` (defined
  as "a failed publish wins") as an upload error. `ImageIntakeDelivery.rejected(String?)`
  lets a screen supply its own reason, because a server's description of a failed upload
  beats the module's generic line.
  It was `AvatarPicker`, and it covered two of its three callers: 拍照新增 hand-wrote the
  same seven steps — with the 350 ms beat in the *view* rather than the model, and
  park-and-retry under a second name (`lastUploadData`) — because the module was named
  after avatars and 拍照新增 is not one. **A module named after one of its callers does not
  get found by the next one.**
  Two croppers stay two implementations behind one entry (`ImageIntakeCrop`): `AvatarCropView`
  is a fixed square with pan-and-zoom, `ImageCropView` is four corner handles at any aspect —
  拍照新增 boxes a subject for AI 辨識 and squaring that would crop the thing being
  identified. Everything on either side of them is shared. A screen with its own source
  affordances calls `pick(_:)` instead of `begin()`: 拍照新增's source panel carries the
  remaining-allowance line and the capacity warning, which a list of chooser rows cannot.
- **Screen view model convention** — non-trivial screen logic (fetch / paginate / save /
  publish / form + async state) lives in an `@Observable @MainActor` view model,
  `@State`-owned by the View and injected with a narrow repository role via a default arg.
  The View is presentation-only; analytics stays in the View (VMs don't reach
  `AnalyticsService`). Exemplar: `AtlasCaptureVM` (+ `AtlasCaptureVMTests`).
  **A destructive write belongs to the model, not to the `View` that hosts the button.**
  Its in-flight flag, its error, its re-entrancy guard, the *decision* behind its warning
  copy, and the mutation-refresh fan-out all live on the VM; the View hands over the
  environment's feed signal and renders the sentence. `SettingsVM` (刪除帳號 / 清除進度) and
  `MyCollectionsVM` (刪除合集) are both on this. The VM method is **non-throwing** — the
  failure has one destination, and a `throws` every caller must remember to catch into the
  same property is a rule stated at the call site instead of in the module — and it takes
  the *row*, not its id, because `wasPublic` is a property of the row rather than something
  the caller re-derives.
  **`SearchVM`** is the read-seam case: it injected `CatalogRepository` but reached
  `WordsStore.shared` at three call sites and `LocalCache.shared` at a fourth from inside
  its methods, so all seven of its tests went to the two `static` ranking functions and
  **not one constructed a `SearchVM`**. The debounce, the cancel, the stale-answer guard
  (written twice — once per branch), "keep local results, only surface the error when there
  is nothing to show" and "only a query that found something is remembered" were verified
  by nothing. Now `LocalDictionaryReading` + `RecentSearchWriting` + an injected `sleep`,
  with `settle()` so a test can await the debounced task (*a seam reaches only as far as a
  test can await* — ADR-0001 amendment). It also moved out of `SearchView.swift`: **a
  module named after one of its callers does not get found by the next one.**
  **A view model's async work is `async`, and the View owns the `Task`.** Every atlas
  model follows this and `AtlasCaptureVM` was the one that did not: `requestRecognize`
  was synchronous and spawned a `Task {}` it dropped, so the rule protecting the user's
  paid AI allowance (each mode recognises at most once; an incomplete cache gets exactly
  one repair) could not be awaited and so was never tested — while `submit()` was `async`
  and awaited nothing. Work that must outlive the screen goes to a module that owns it
  (生成佇列), not to an unstructured task inside a `@State` object SwiftUI is about to
  throw away. The community
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
- **兩條社群訊號是兩條。** `CommunityFeedRefresh`（一次性旗標，撐過畫面生滅，讀了就沒）
  與 `CollectionBookmarkStore`（帶值的廣播，送給掛著的畫面，`revision` 讓重複的同一個
  變更也再觸發）在 `AtlasPublicFeedView` 裡相隔三行、用兩種寫法讀。看起來像沒收乾淨，
  不是——合併會逼消費端二選一，而兩個方向都是把複雜度推給消費者。理由記在
  [ADR-0010](docs/adr/0010-two-community-signals.md)。
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
- **LearningDirectionRefreshing** — one policy home for what a 學習語言 switch drops and
  re-fetches: catalog + study queue + the three learning stores, invalidated before
  anything is re-read. Producers name a `LearningDirectionChangeOrigin`
  (`userPicked` / `serverDisagreed`) rather than a list of stores; the origin exists
  because one consequence genuinely differs — `serverDisagreed` runs inside launch, where
  `LaunchCoordinator` owns the catalog load, so the module drops the catalog without
  refetching it. **`SettingsStore` is the only place that notices**: it detects the change
  in all three of its write paths (`setLearningDirection`, `performLoad`,
  `adoptPersisted`), so no screen states the consequences. Four hand-written fan-outs
  disagreed before this — the first-run picker dropped only the catalog, leaving the
  previous direction's mastery, progress and streak on screen, and two of the four lived
  in `View` bodies where no test could reach them. The fourth refresh module, beside
  `AtlasMutationRefresh` (authoring), `CommunityLearningRefresh` (consumption) and
  `SessionRefresh` (study).
  **Dropping and re-reading is only half of it**: the re-read has to say which direction it
  is for. `/api/users/progress`, `/api/users/mastery`, `/api/study/stats` and
  `/api/study/queue` derive their answer from a direction, and the settings POST that would
  tell the server is debounced 400ms behind — so a re-fetch issued here always beat it and
  came back scoped to the language the user had just left, which the stores then held for
  their 30s freshness window. Every direction-scoped request now carries `?learning=`, and
  the server takes the request at its word (the rule `?lang=` already had). A request that
  states nothing still falls back to stored settings, for installs that predate this.
- **CatalogWarming / 觀眾 (`CatalogAudience`)** — what a launch loads, and for whom.
  `warm(for:)` over `.guest` / `.signedIn(userID:)`, with `LiveCatalogWarmer` the only
  place that knows the catalog is `SettingsStore` + `WordsStore` + `CategoriesStore`.
  `LaunchCoordinator` is deep in *sequencing* (the splash beat, the catalog generation
  handover, cancelling superseded work, `appOpen` once) and all of that is tested — but its
  interface was **eight closures** whose bodies lived in `TujiApp.init`, and two of them
  were the same eight lines twice, differing only in the two fields `CatalogContext`'s
  precondition exists to relate (`userID` / `includePersonalization`). So "what a launch
  loads" was an anonymous closure in an `@main` struct: not searchable by name, not
  callable from a test. **Settings are loaded first and alone for a signed-in audience**,
  because the context is *derived* from them — loading them alongside would race the
  request against its own parameters; a guest has none to wait for, which is the whole
  reason the two paths differ. Switching audience is a new generation but not a new
  download: `reusePublic` keeps the public 480 and fetches only the personalized overlay.
  `CatalogContext.current()` stays as-is — six modules read the catalog through the no-arg
  `loadIfNeeded()`/`reload()` it backs, and retiring it is a separate change.
- **AccumulationLoading** — the **reader's** counterpart to those four: what a screen needs
  *warm* before its numbers are true, where they name what a write *invalidates*. An
  `AccumulationSurface` (`todayHero` / `progressSections` / `themeIndex`) answers `needs(isGuest:)`
  with a set of `AccumulationStore` roles; `AccumulationWarmer` warms them and the
  `.warmsAccumulation(_:isGuest:then:)` modifier is the screen-side seam (`then` exists for
  首頁, whose study-queue prefetch must follow settings + stats). It exists because three
  screens hand-wrote the same fan-out and one got it wrong: `CategoryIndexView` rendered the
  完成 badge from `ProgressStore` and never loaded it, so on a cold open of 主題 the badge was
  missing from every theme and appeared only if another screen had warmed the store first —
  intermittent rather than broken, because 全精通 reads mastery, which *was* loaded.
  **Settings is warmed first and alone**: it is the only one of the six with consequences for
  the others (it is where a 學習語言 disagreement is noticed, which invalidates the learning
  stores), so warming progress alongside it would race a load against its own invalidation.
  The rest are awaited **in sequence, deliberately** — `any WarmableStore` is a non-Sendable
  existential and sending one into a child task passes Debug and fails the Swift 6 WMO build,
  the trap already documented on `MeVM.load`. Every store is TTL- or once-guarded, so after
  the first appearance the whole sequence is a no-op.
- **Staleness is per-store and not uniform.** `ProgressStore` / `StudyStatsStore` use
  `loadIfStale(ttl: 30)` because their numbers move on their own (`due` crosses midnight, the
  streak turns over). `MasteryStore` uses `loadIfNeeded` — no TTL — because a score only
  changes when *this* user answers something, and every path that does already invalidates it
  through `SessionRefresh`. The cost: another device's session shows up only after a relaunch
  or a pull-to-refresh, and 我 has no pull.
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

## Study — the session's three modules

- **`StudySessionWrites`** — what a session does with an answer *after* the writer
  returns: track the task so the completion screen can drain it, fold the mastery
  delta, keep the milestone, count the parks. Both flows hold one. They used to hold
  a copy each: `hasPendingWrites` was byte-identical, `drainPendingWrites` was the
  same one-line delegation twice (each carrying the same comment about the module
  qualification that stops it recursing into itself), and the parked count had two
  names — `parkedCount` / `unsyncedCount` — while rendering through one view. The
  duplication hid an asymmetry: only 複習 read the `.synced` body, so **a streak
  milestone crossed by a `new_recognize` write was dropped and unrecoverable**, and
  學新字 had no milestone screen to show it on. The seam is the `DurableAnswerWriting`
  the module is built over; mastery is keyed by *word* while the payload carries a
  *card* id, so the caller states the word rather than the module deriving it.
- **`StudyLadder`** — the 學新字 task queue as list algebra: the interleave, the
  requeue, the 已認識 fast path, the normalize-head rule that keeps a 拼字 from
  surfacing before its word cleared 選字, and the progress readout. A value type
  with no beats, locks, writes or latency capture in it. It was already a module
  and had no interface: living inside `NewFlowCoordinator` beside six other
  responsibilities, the only way to exercise it was through `resolveRecognize` /
  `resolveIdentify` / `resolveTiles` — three internal methods written for the tests
  that **the app never calls**, entered from 11 test call sites. *The interface is
  the test surface*: tests that must enter where the app doesn't are telling you
  the module is the wrong shape.
- **`DistractorPool`** — whether a label may stand beside the answer, as a returned
  `DistractorFairness` (`sameTerm` / `tokenSubset` / `cjkSubstring` / `sharedGloss`
  / `fair`) rather than a private `Bool`. The four rules are the reason the module
  exists and not one was pinned: they lived in file-private functions with no test
  file, assertable only through a seeded shuffle, *by absence* — an assertion that
  passes just as well when the shuffle happened to fill the slot otherwise. Its
  `studyChoices` entry point is unchanged; what moved is that the verdict is now a
  value. `StudyChoiceList` is the matching view seam — 選字 and 複習 each carried
  their own copy of the same 18-line option list and the same four-argument
  assembly.
- **A finished session refreshes, whichever screen celebrates it.**
  `.refreshesFinishedSession(draining:)` hangs off the *finish*, not off
  `CompleteView` / `NewDoneView` — where it used to live, so a session that crossed a
  milestone showed `MilestoneView` and refreshed nothing: the streak it had just
  celebrated stayed stale and the study queue was never dropped. The three home
  stores and the queue invalidation are read inside the modifier; assembling them
  was the duplication that survived deduping the sequence itself.
- **`TileBoard` owns how a tile board is made.** `spellSubject` / `of(_:)` /
  `units(for:attempt:)` used to hang off `NewFlowCoordinator` as a `nonisolated
  static` extension purely to borrow its name, and `TilesView` had to `typealias
  SpellBoard = NewFlowCoordinator.SpellBoard` to get back out. **A module named
  after one of its callers does not get found by the next one** — the same lesson
  `ImageIntake` learned from `AvatarPicker`.

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
- **求救提示 (hint flip)** — the face 複習's hero turns over to: the gloss, and **only** the
  gloss. `reading` and `pronunciation` are both on the payload and neither may appear there —
  a kana headword's 振假名 is itself and an IPA line is the word read aloud, so either one
  turns the hint into a skip. Asking for it is the user reporting they could not retrieve the
  word, so it is **sticky within the presentation** (flipping back does not un-see it) and it
  makes the item take the **wrong-answer rating table** `[重來, 困難]`, correct or not; only
  the *suggestion* still tracks correctness ([ADR-0007](docs/adr/0007-review-hint-costs-a-downgrade.md)).
  Three things it deliberately does **not** touch: the requeue rule (still "did they pick the
  wrong option" — 重來 on a hinted *correct* answer reschedules but does not re-ask this round),
  a retest (which writes no SRS at all, so there is nothing for the hint to cost), and `showZh`
  — that switch governs the *always-on* gloss 學新字 prints on the picture, and a deliberate
  tap is not that. It is also the one rule in `pick()` that is stated nowhere in `pick()`:
  capping the suggestion at 困難 is what switches the auto-rate path off, because that path
  requires a suggestion other than 困難.
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
  - **ViewerIdentity** — `{ isGuest, uid, owns(handle:), displayName(fallback:) }`, conformed
    by `AuthService`. Who is looking, and is this theirs. Answered fourteen times before
    this, in **four** mechanisms that did not agree: `user == nil` (今天, 我), `if case
    .signedIn` (設定, 圖鑑, 主題, 我的進度), `uid.caseInsensitiveCompare(handle)` (物見 ×2,
    作者主頁), and three copies of nickname → UID → email-local. Not academic: `MeView` used
    the first and hosted `MeProgressSections`, which used the second, and **both feed
    `CompletionReadout.Inputs.isGuest`** — the flag that decides whether 完成度 counts the
    local learned set or the server rows. They agreed only because `RootView` maps `.guest`
    to `user: nil` by hand. The consuming half of the seam already existed and was tested
    (`CompletionReadout.Inputs`, `TodayDecisions.Inputs` both take `isGuest`); what was
    missing was a producer. `fallback` is the caller's because it is that screen's copy —
    今天 greets 「探險者」 and 我 titles the row 「Tuji 探險者」. **The rules live on
    `AuthState`, not on `AuthService`**: the service has a private init and a stored
    Supabase client that traps without Info.plist keys, so nothing could stand one up —
    the same reason `AuthSession` was split out of it. `CollectionDetailVM.matchesOwner`
    stays where it is on purpose: it can only answer *after* the fetch it does itself.
    **`authorRef` is the fifth member, added later and for the reason the seam exists.**
    The first four covered the consumers of the day, and the next three went *around* them:
    物見, 作者主頁 and 編輯個人資料 each needed the viewer as an **Author identity**, got
    `uid` + `displayName` from the seam, and pattern-matched `auth.state` again for the one
    field it did not answer (`avatar`) — which is how 「沒有頭像就用黑貓」 came to be spelled
    in a `View` body. A seam is worth what it answers for the *next* consumer. Two other
    misses went with it: `shouldPersist` (`!isGuest`) was five hand-written lines in both
    the first-run picker and 設定's, and `FavoriteButton` guarded on `.signedIn` directly.
    `MainTabsView.user == nil` is deliberately **left**: that view is built on an explicit
    `user` parameter threaded to 今天/我/`tujiNavDestinations`, and reading the environment
    beside it would create a second source rather than remove one.
    `EditProfileView.sessionUser` also stays — it is the *edit form's* current values, so
    the nickname must arrive raw, where `displayName` would hand back the UID and the form
    would offer to save that as a nickname.
  - **LanguageContext** — `{ uiLang, learningDirection }`, conformed by `SettingsStore`.
    Injected into `LiveStudyRepository` (queue lang), `LiveAtlasRepository`
    (upload/recognize/confirm lang + learning) and `LiveCatalogRepository` (search only —
    the other calls carry a `CatalogContext` the caller already assembled). Read live at
    call time (an in-app switch must take effect on the next request). **A direction-scoped
    endpoint carries the direction in its URL even when the server would infer it**:
    `/api/search` is `.publicCached`, so its URL *is* its cache key, and with only `q` on it
    both directions shared one entry.
  - **StudyQueueInputs** — `{ learningDirection, dailyGoal, studyCategories, due }`, the
    slice `StudyQueueStore` folds into its queue params + cache signature. `LiveStudyQueueInputs`
    is the live adapter over settings + stats; `StudyQueueStore.init` is now injectable so a
    test can assert a direction switch busts a warm entry.
