# Tuji — domain & architecture glossary

Shared vocabulary for architecture reviews (`/improve-codebase-architecture`) and
domain modeling. Names for the good seams. Keep terms sharp; add lazily as they crystallize.

## Domain — the atlas (圖鑑)

- **自製圖鑑 (custom atlas)** — a user's own captured items. Created via the capture
  pipeline (photo → AI 識別 → 校正 → confirm). Capacity is quota-gated per tier.
- **一次拍照有四個身分**，而使用者只看得到一個。`image`（`user_atlas_images` 的那一列
  ——書架列的是它，刪除刪的也是它）→ `item`（東西本身：配額數的是它、mastery 的 key 是
  `atlas:<itemId>`、公開的也是它）→ `AtlasCard` ×2（`image_recall` 與 `flashcard`，
  學習佇列抓的單位，所以一個自製字會出現兩次，`StudyQueueStore` 按 `word.id` 去重）→
  `word`（`atlas:<itemId>`，其他畫面看到的樣子）。**使用者讀到的「卡片」是整個東西**，
  `AtlasCard` 只活在程式碼與 wire 上——物見 / `community` 那條規則的同一形狀。刪除的確認
  框曾經在一句話裡用了兩個意思：標題「刪除這張卡片？」說的是整個東西，內文「圖片與它
  生成的卡片」說的是那兩張題目，而後者是前者的組成部分。
  _Avoid_：在任何給人看的句子裡用「卡片」指那兩張題目。
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
  the same rule (and coalesces the duplicate refresh that returning from 編輯合集 fires),
  and so is `PublicAtlasBrowsingModel.ShelfState.showsPlaceholder` — 物見's two shelves
  used to answer it in the *View*, three lines apart, and the explore half had no
  rows-present guard at all. It is the half that reloads most: a pending 物見 refresh
  (what publishing a 合集 sets) arrives as `pendingForce`, not `forceReload`, so a full
  shelf blanked to 「載入中…」 on the way back.
- **公開圖鑑 (public atlas)** — items that entered review with a collection and passed
  the moderation gate, visible to everyone. The app has no separate per-item submission
  action; publishing a collection submits its private members as one batch.
- **可見性是二值。** 私有或公開，中間只有審核閘門，沒有第三種。資料庫不是這樣長的——
  `visibility` 有 `'friends'`，`user_friendships` 與 `atlas_item_grants` 兩張表也都在
  ——但那兩張表在整份應用程式碼裡沒有任何一個 INSERT，也沒有一行把 `visibility` 寫成
  `'friends'`，所以「朋友圖鑑」對每一個人、在任何時候都保證是空的。讀路徑已經移除，
  資料表留著（migration 是 append-only）。理由記在
  [ADR-0012](docs/adr/0012-visibility-is-binary.md)：第三種可見性會讓人在**沒有經過審核
  閘門**的情況下看到別人的照片，而那是公開側唯一的一條界線。
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
- **收進容量 (saved capacity)** — 收進圖鑑吃的那份額度：`savedItemsLimit`（Free 1000 /
  Pro 5000），數的是 `atlas_saves`。與自製圖鑑格數是**兩份預算、兩張表**，因為讓收藏
  別人的照片吃掉免費版的創作格，等於拿掉免費版最值得留下來的東西。它是**防濫用的欄杆，
  不是賣點**：觸頂不可升級，所以文案不得推 Pro，介面也**不常駐顯示剩餘**——天天提醒還剩
  幾格，會讓人以為那是要省的東西。在 wire 上它是 429 `save_limit`（帶 `limit` /
  `usage`），跟「操作過於頻繁」同一個狀態碼卻是相反的建議（等待永遠沒用，移除才有用），
  所以客戶端讀 body 的 `error` 分流成 `APIError.atCapacity`，而那句話是 App 自己的：
  伺服器那句只有繁體中文，還把它叫做「學習項目」——產品其他地方都沒用過的第五個名字。
  改狀態碼不是出路：已上線的 client 會把 409 讀成「伺服器出了點問題」。
  `AtlasEntitlement` 刻意**沒有** decode 這兩個數字——在有畫面真的要問「還剩幾個」之前，
  那會是又一組沒有讀者的欄位（`AtlasSyncResponse` 的教訓）。
- **刪除一張卡片的三種承諾 (`AtlasItemDeleteWarning`)** — 與 `CollectionDeleteWarning`
  同形（`privateOnly` / `cancelsReview` / `takesDownFromPublic`），理由也是同一條：那是
  作者按下不可逆按鈕前讀到的最後一句話。差別在於**這個刪除會刪到別人帳號裡的東西**：
  `deleteAtlasImageCascade` 是硬刪除，連帶帶走 `atlas_public_items` 與每一個收藏者的列，
  也就是他們建立在這張卡片上的複習進度。**取消公開存在的唯一理由就是不必走這條路**，
  所以它跟警告出現在同一個 sheet 裡，而不是留在另一個畫面等人自己找到。沒有確認 item 的
  列是 `privateOnly`——還沒確認的拍照哪裡都沒去過。批次刪除取所選之中**最重**的那一種
  承諾（混一張公開的進去，卻承諾「帳號外什麼都不會變」，是對唯一要緊的那一列說謊）。
  收藏人數刻意不說：作者側從來沒拿到過 per-item 的 `saveCount`，為了一句話加一條回傳，
  會讓警告依賴一個可能沒到的數字。
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
  **iOS 端刻意沒有第四套狀態。** `backfill_status` 從不上 wire：`skipped` 在畫面上就是
  「只有名字和照片」，而那是一種**完整**的卡片，不是壞掉的卡片。已經有三套狀態詞彙
  （`AtlasImageStatus` / `AtlasReviewStatus` / `CaptureProgress`）互相對得起來，第四套
  要付的代價遠大於它能多說的那句話。

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
- **卡片指著那個詞。** 點下去升起的是一張浮在該詞塊旁邊、尖角對準它的卡片，而那個詞在句子裡
  同時上一道黃色螢光筆。這件事一度是做不到的：整句交給 SwiftUI 的文字引擎（一個
  `AttributedString`、每個詞塊一個 link）換來斷行、Dynamic Type 與禁則，代價是 link 不回報
  它落在哪裡。`Text.Layout`（iOS 18 的 `TextRenderer`）回報得了，**而且不必把排版拿回來**
  ——見 [ADR-0013](docs/adr/0013-the-gloss-card-points-at-the-word.md)。兩個實作上的坑值得
  記在這裡：自訂 `AttributedStringKey` 設在字串上**活不到** `Text.Layout`（run 回來是沒有
  標記的，在裝置上驗過），所以被選中的詞塊要用 `Text` 串接單獨切出來、掛
  `Text.customAttribute`；而 renderer **只在該句握有選取時**掛上去——那一刻遮罩已經蓋住句子，
  所以就算它動到 link 的命中測試也傷不到任何東西。切出來的那一塊**不能重新編號**，否則它
  後面每一個 link 都會開錯的詞。
- **量不到錨點就退回底部，而且不畫尖角。** 跟「串不回原句就退回純文字」是同一條精神：這個
  功能的失敗模式永遠等於它的上一個版本，而不是一個指著錯的詞的尖角。上下都塞不下（大字級 ×
  小螢幕）也走同一條路。擺放的算術在 `GlossCalloutPlacement`（純函式，有測試，跟
  `ReviewRevealLayout` 同一個形狀），外框與尖角是同一條 `Path`（`GlossCalloutShape`，本專案
  第一個 `Shape`——所以 `Space` 現在是 `nonisolated`，`Shape.path(in:)` 不在主執行緒上）。
- **音標比 `wordId` 嚴。** 詞塊上的 `pronunciation` 是目錄自己的 `word_terms.pronunciation`
  （英文是 IPA、日文是假名的複本），伺服器 join 上去，客戶端不重新推導任何事。閘門不是
  「有沒有 `wordId`」而是**「這一塊拼得跟詞頭一模一樣嗎」**：`wordId` 是載入腳本拿**原形**
  比對出來的，所以 `documents` 連到 `document`、`next corner` 連到 `corner`，照印就會在
  `documents` 底下印 `/ˈdɑː.kjə.mənt/`——不是沒用，是教錯。實測 1,765 個連得到目錄的英文
  詞塊裡有 132 個是這種。剩下 1,633 個有音標（約五分之一的可點詞塊），其餘沒有那一行——
  跟它們同樣沒有書籤鍵、沒有「看完整詳情」是同一條規則。**而被擋掉的那些剛好就是原形那行
  有東西的那些**，所以讀者不是少了資訊，是拿到正確的那一則。
  卡片上那一行走的是 `HeadwordDisplay`（`GlossSpan` 也是 `Headworded`），不是第四份
  `if let pronunciation`——那正是那個 enum 當初被抽出來的原因。
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

## Study — the session's modules

- **一題 (`ReviewQuestion`)** — one presentation of one card: what it asks (`kind` /
  `example` / `imageOptions` / `ready`), what the user has done to it (`phase` /
  `picked` / `wrongPicks` / `hinted` / `sentenceRevealed` / `replayCount`), and what
  that adds up to (`suggested` / `rated` / `settled` / `payload(rating:…)`). It was 32
  stored properties on `ReviewFlowCoordinator`, and `advance()` was a **16-assignment
  reset** of them with three assertions behind it — so adding a question kind meant
  adding state and remembering to clear it in a list nothing checked, which is how 聽句's
  six fields came to sit beside 複習's cursor. **The reset is now a construction**:
  `advance()` builds the next one and every field is at its start value because the
  value is new. A value type with no beats, locks, audio or writes in it — the shape
  `StudyLadder` already has. The coordinator keeps what outlives a card (queue cursor,
  `retriedIds`, the session's 聽句 opt-out, the primed haptics, `AnswerBeat`, the writer)
  and everything with a latency: **this decides, the coordinator performs**, which is
  what lets the whole answering path run synchronously in a test.
  - **答案只量一次 (`measuredElapsed`)** — the reading taken when the answer lands.
    `resolve` refused to time an answer given before the clip ended while `applyRating`
    recomputed it unconditionally 138 lines later, so the *suggestion* said nothing was
    measured and the row written to SRS claimed a duration including the download, the
    clip, the 600 ms reveal beat and the user's deliberation over three rating buttons.
    Unmeasured now sends `nil` (`responseMs` was always `Int?`).
  - **`settled`** — whether nothing will ask this word again, so the progress bar may
    count it. One rule for three `passedCount += 1` sites under three conditions: a
    re-test settles on resolve (it never requeues and is never rated), everything else
    when a rating lands and only if it was right. `counted` keeps one rule from becoming
    two counters; the *timing* of the count is deliberately unchanged.
  - **沒有句子就不是聽句題** — `present` demotes to `.pickWord` itself rather than
    trusting the caller's eligibility arithmetic to have ruled the combination out.
- **`ReviewChoice`** — the option the user landed on: `id` (the catalogue word id, when
  the option had one) + `label`. **A label is not an identity.** 選字's four options are
  labels and `DistractorPool` guarantees they are distinct; 聽句's two pictures carry
  ids, and two catalogue words *can* print the same string. `pickImage` said exactly
  that in a doc comment and then handed on `option.word` alone, so
  `ReviewImageChoices.border` drew 「你點了這個」 by comparing text — the comparison the
  comment four lines above rules out. `reportedSelection` stays a `String`: that is copy
  for 報錯, not identity.
  `StudyOptionState.forPicture(optionId:answerId:pickedId:revealed:)` is the picture
  half of the verdict, sharing `verdict(isAnswer:isPicked:)` with `forOption`. Only the
  *decision* is shared — a photograph has no invert channel, so `.right` and `.answer`
  land on one colour there and the mapping stays the card's.
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
- **選錯一個選項不是作答，是把它排除掉。** 複習的看圖選字，錯的那一下只把該選項標上紅框、
  停掉它的點擊，題目留在原地讓人繼續選；只有**落地的那一次**才走 `resolve`。承重的是
  `pick()` 交給 `resolve` 的 `correct:` 是**「有沒有一次就中」**（`ok && wrongPicks.isEmpty`），
  不是「這一下對不對」——`resolve` 下游全部只讀 `wasCorrect` / `hinted` / `suggested` /
  `retriedIds`，沒有一處數過點擊次數，所以「評分不變」是靠這一行把事實講對達成的，不是靠在評分
  裡加分支。**聽句刻意不在這條路上**：兩張圖排除掉一張就等於拿到答案，和它不自動評級是同一個
  50%（ADR-0014），所以 `pickImage` 仍然第一次點擊就結算。連帶兩件事：`.wrong` 的紅色從左側
  邊條改成整圈框，因為它現在會出現在**旁邊沒有正確答案反白**的時刻，一條側線讀不出「不是這
  個」（學新字的答錯跟著改，「答錯了」在全 App 只該有一種標記）；以及 `picked` 從此只由落地的
  那一次設定，所以 報錯 改讀 `reportedSelection`，否則題目還開著時送出的報告會把使用者已經試
  過的東西整個丟掉。
- **揭示表晚一拍升起，因為它蓋住的正是答案本身。** 揭示表本來和選項在同一個 frame 出現，
  於是墨塊與框——畫面上唯一在講「剛剛發生了什麼」的兩個東西——一幀都沒被看到就被 modal 蓋掉，
  等於要使用者為一個他沒看到的答案評分。現在 `resolve` 立刻定案（`phase`、`wasCorrect`、
  `suggested`、鎖住選項都不變），只有 `revealMode` 隔 `revealDelay`（600ms）才設。這一拍走
  `AnswerBeat` 而不是裸 `Task`，理由就是那個模組存在的理由：**先離開**時它必須取消，否則會在
  使用者已經離開的畫面上升起一張表。比自動前進的 700ms 短一點是刻意的——那一拍在結束一題，
  這一拍是在通往「還要動手」的路上。`rate()` 本來就守著 `revealMode == .rate`，所以這 600ms
  裡點不到評分鍵，不需要另一道鎖。
  **代價落在測試上**：`revealMode` 從此不可能和 `pick()` 同一輪被觀察到，所以每個看揭示表或
  對它評分的測試都要先 `awaitReveal`。那個 helper 用 `#require` 而不只是輪詢：`waitUntil`
  逾時是**安靜返回**的，所以在一條自動評級（根本不升表）的路徑上等它，會燒完 60 秒然後照樣
  綠——這個坑當場踩過一次，三個聽句測試各慢了 60 秒。
- **選錯的那一列會晃一下。** 框是**狀態**（這一輪它都在），晃動是**事件**。狀態自己出現很容
  易沒被看見，尤其在複習：整個畫面只有被點的那一列變了，題目其他部分原封不動地繼續。晃動掛
  在「進入 `.wrong`」這個轉換上，所以答案落地時，先前被排除掉的那幾列**不會跟著再晃**——把舊
  的錯誤重播一次，看起來會像它們剛剛才被點錯。**它必須用 keyframe 不能用
  `phaseAnimator`**：後者是「動到某一相位，然後等下一個相位被排程」，那個空檔正好落在動作已經
  停住的地方——也就是最遠點。實測（60fps 錄影）那一版**一個畫格就彈到 −7.3pt，然後在那裡停了
  約 95ms**，另一側也一樣，讀起來是「先橫移過去停住，然後才抖」，而不是抖一下。keyframe 是單
  一條時間軸、每個畫格取樣一次，0 → −7.3pt 花 29ms，中間沒有一格是靜止的，整體 195ms。
  投擲段用 `LinearKeyframe` 而不是 `CubicKeyframe`：cubic 是穿過那些值而不是落在上面，旁邊有
  一個往反方向拉的鄰居時它會把角磨掉——全 cubic 版實測第一下只到 −3.3pt（目標 −7），變成先弱
  後強，跟阻尼剛好相反。`Shake` 刻意**不進 `Motion`**：那個尺度是
  全 App 的三段時長，這只是一個元件的錯誤回饋，在那裡加第四個值等於邀請下一個人用「晃動速
  度」去 animate 別的東西。它仍然只用系統那一條 `easeOut`，而且起點與終點都是 0，不越過靜止位
  置。
- **底色講「哪個是答案」，框講「你點了哪個」。** 選項列上這兩個訊號是各自獨立的：反白成墨塊
  ＝正確答案，3pt 框＝使用者的那一下。所以答對是**兩個都有**（墨塊 + 積累色框）、答錯只有紅
  框、`.answer`（是答案但他沒點）**刻意沒有框**——在他沒點過的那一列畫一個框，等於宣稱一次不
  存在的點擊。答對用 `tujiAccumulation` 而不是新增一個綠色：紙與墨只有六種意義而其中沒有綠，
  **而聽句的兩張圖片本來就用這個顏色畫答對的框**。對比度四條邊都過 3:1（霧藍對墨塊 3.60、對
  紙 4.72）。聽句那邊的規則**不跟著改，而且不是漏掉**：照片沒有「反白」這個通道，所以它的積累
  色框只能拿去講「哪個是答案」，同一個顏色在那裡承擔的是另一件事。
- **`StudyOptionRow` / `StudyOptionStyle`** — one shared MCQ option row + its
  right/wrong/answer/dim reveal logic (`StudyOptionStyle.forOption`), used by both
  `IdentifyView` (選字) and `ReviewFlowView` (複習). Replaced the two near-identical private
  `OptStyle` / `OptionStyle` copies.
- **聽句 (`hearSentence`)** — 複習的第二個題型：題目是那個字的例句**模糊**加上它的音檔，答
  案是兩張圖片二選一。不是新的 `StudyMode`——`模式` 已經被 `new` / `review` 佔走而且是
  `?mode=` 的 wire value；這是**題型**，也就是 `activity`，wire value 用早就在 CHECK 約束
  裡的 `"listening"`（零 migration）。Swift 那一側是
  `ReviewQuestionKind { pickWord, hearSentence }`，case 名刻意不跟 wire value 同名：`mcq`
  講的是題目形式、`listening` 講的是感官通道，同一個列舉裡混兩種命名軸，下一個加題型的人不
  知道該挑哪一軸。句子的音檔存在 `word_example_media`、**不在 `word_media`**——理由與那個無
  聲的壞法見 [ADR-0015](docs/adr/0015-sentence-audio-is-not-word-media.md)。 _Avoid_：在任
  何句子裡用「模式」指這個東西。
- **聽句永遠不自動評級。** `pick()` 的自動路徑寫著它的前提是「建議值毫無疑義」，而
  **二選一的猜對率是 50%**：一次擲硬幣猜中、兩秒內按下去，在 MCQ 那條路上會自動寫入「熟
  練」而使用者連評分畫面都沒看到。一次五五開的正確不是毫無疑義，它就是同一個 `pick()` 裡另
  一個分支說的「使用者自己的判斷帶有訊號」，所以聽句一律出揭示表
  （[ADR-0014](docs/adr/0014-listening-changes-the-rating-preconditions.md)）。代價是每題
  多一次點擊，這是二選一換來的，不是額外的。
- **聽句的提示只花得起一半的錢。** 眼睛圖案解模糊走的是同一個 `hinted`、同一份答錯評分表
  `[重來, 困難]`（`availableRatings` 一個字都不用改），理由是解模糊之後這題已經不是聽力題
  而是「讀句子選圖」，句子裡就印著那個字。但
  [ADR-0007](docs/adr/0007-review-hint-costs-a-downgrade.md) 的提示花的是**兩樣**東西——評
  分表，加上關掉自動評級——而第二樣在聽句裡本來就是關的。所以
  **`study_logs.metadata.hinted` 跨題型比較不是同一把尺**。眼睛也**從頭就顯示**，這和 MCQ
  刻意隱形的提示（`ReviewHeroCard`：the affordance is deliberately invisible，卡 8 秒才長
  出一行）方向相反：那 8 秒是用來補償入口看不見的，這裡沒有要補償的東西。
- **答完之後模糊自動消失，而且目標詞上一道螢光筆。** 解模糊在作答階段要付 `hinted`，答完之
  後不用——`hinted` 只由 `revealSentence()` 設定，而它 `guard phase == .answer`。答案已經給
  了，句子從那一刻起就是教材，跟揭示表上的答案同一個身分。螢光筆的位置是
  **在裝置上用字串比對算的，不是用 spans**——這一條和 `mentionedWordIds` 的理由剛好相反，所
  以是量過才決定的：對現行語料，字串比對 en 939/952、ja 945/952，而 span 的 `word_id` 只有
  en 838/952、ja 894/952（span 只在原形解析成功、且那句有標註時才帶 id，而有一批現行例句根
  本沒有 span 列）。**用伺服器要多一次部署，命中率還更低。** 比對規則有兩個非做不可的地
  方：拉丁字要求詞邊界，否則 `cup` 會在 `cupboard` 裡亮起來；但**日文不能套這條**，假名漢
  字都是 letter，要求非 letter 鄰居等於拒絕每一個日文句子。以及吃掉 `s`/`es` 複數字尾——語
  料裡有十句用複數指涉那個詞（`curtains`、`traffic cones`、`monitors`），只標單數會少一個
  字母、看起來像畫錯而不像決定；字尾**只吃 `s`/`es`，不吃「任意結尾字母」**，寬鬆版會把
  `grate` 撐成 `grater`。剩下約 1% 的句子根本沒寫出那個詞（`scanner` 對「Scan both
  sides」、`ベッド` 對「夜11時に寝ます」），那些不標：**沒有螢光筆比標錯地方安靜。**
- **哪一句由熟練度決定；分階就是全部的變化。** 主詞條的例句是**成對**授權的
  （`lib/main-word-example-pairs.ts`：`cefrLevel: "A2"` / `"B1"`，
  `validateMainWordExampleCoverage` 兩個方向都檢查），而線上資料是乾淨的全覆蓋：
  `word_examples` 共 952 列、476 個字，
  **每個字剛好一句 A2 一句 B1，`cefr_level` 零缺漏**——難度階不是發明出來的，是已經寫好而
  **全 App 沒有一行讀過**的欄位。門檻沿用 `computeSuggestion` 已經在用的 50，不新增第二個
  沒人知道為什麼是那個數字的常數。
  **因為每個字只有兩句，「同一階內輪播」永遠不會觸發，所以不要寫它**——一條打不到的規則沒有
  人驗得了。（`data/example-spans.json` 裡 `bag` / `basil` / `basket` 各三句是**授權檔**的
  內容，含被取代的舊句，不是資料表。）**熟練度上升本身就是變化的來源**：句子換掉的那一刻正
  好是那個字變熟的那一刻。**這個不變量是被守著的，不是剛好乾淨的。**
  `validateMainWordExampleCoverage` 只比對 pair 與 published 兩個集合，但同一個交易接著跑
  `classifyMainWordExamplePair`，而 `isTargetExamplePair` 要求 `current.length === 2` 且兩
  句的 `cefrLevel` 都對得上，對不上就是 conflict、`main-word-example-pair-apply.ts` 直接
  throw。整條掛在 `migrate.ts:2667`，**每次正式部署都跑**——少一個 `cefr_level` 或多出第三
  句，deploy 就停。所以不要再補第四份檢查。（2026-09-03 順手刪掉 4 個 `archived` 的字留下
  的 6 列孤兒例句，其中 2 列沒有 `cefr_level`；那批在守衛的射程外，因為它只看
  published。）
- **干擾圖片不能是句子裡的另一個詞。** 例句是刻意同時提到兩個目錄詞的——「The air
  conditioner is in the bedroom.」——而
  **en 有 46%、ja 有 47% 的例句提到兩個以上不同的目錄名詞**。抽到那一個，兩張圖就都是對
  的，使用者聽得完全正確然後被 SRS 記一次答錯。伺服器本來就知道是哪些（`wordId` 是它從
  span 的原形解析的，它甚至有 `unlinkSelfReference` 專門拿掉「這個字自己」那一個），所以佇
  列隨例句附一份 `mentionedWordIds`；**送的是那一點而不是整份 spans**，便宜兩個數量級。干
  擾項本身仍由 client 從 `WordsStore`（整本字典常駐）抽，因為重考要換得掉——伺服器發佇列時
  還不知道誰會答錯。另外兩條排除規則：`imageKind` 必須相同（去背圖配生活照，用看的就知道是
  哪張，這條同時擋掉抽到自製卡），以及不從當前佇列抽（等一下自己也要考的字，先讓他看過那張
  圖是白給的提示）。
- **聽句的碼表從音檔播完才起算，但重播不歸零。** `advance()` 每題設 `startedAt = .now`，而
  `computeSuggestion` 的 3 秒 / 7 秒門檻是為「圖片出現 → 作答」校準的。音檔會往那個碼表裡
  混進三樣跟提取速度無關的東西：第一次播放的下載延遲、句子本身的長度（聽完前答不了，而
  A2/B1 兩階不同長）、以及重播。不扣掉的話每一次聽句作答都會超過 7 秒，
  **建議值永遠是困難**——把使用者往下拉間隔的方向推，對象是他聽得懂的字。扣掉前兩樣之後，剩
  下的重播時間指向的方向是對的：聽三遍才答得出來的字，建議困難是正確的，不是被污染；從
  **最後一次**播完起算才是壞的，那等於把碼表歸零、獎勵猶豫。重播次數與 `audioFailed` 記進
  `study_logs.metadata`，理由同 `hinted`：append-only，沒記下來就補不回來。這條規則要求
  `SpeechService` 發布播放狀態（`@Observable`，不是為這一個呼叫者加的 `onFinish` 閉包），
  順手補掉 `PronunciationButton` header 裡記著的洞。整條見
  [ADR-0014](docs/adr/0014-listening-changes-the-rating-preconditions.md)。擋路的**不是**
  `NSObject`（那沒問題），是 `lazy`：`@Observable` 把每一個儲存屬性改寫成計算屬性，而
  `lazy` 不能用在計算屬性上——`SpeechService` 的 `synth`（41 行）與 `cacheDir`（55 行）各要
  補一個 `@ObservationIgnored`。已實際編譯驗證。
- **對 VoiceOver 要重現的是模糊的「效果」，不是模糊這個「視覺」。** 模糊是畫面上的東西，
  VoiceOver 會直接把整句唸出來——那是**免費解模糊**：拿到答案而沒有經過眼睛那顆鍵，所以
  `hinted` 是 false、評分表照樣是 `[困難, 穩定, 熟練]`，那批人的 SRS 資料靜悄悄地跟其他人
  不是同一種東西。所以句子那一塊 `.accessibilityHidden(true)`，區域標籤說得出「這裡有東西
  而且遮著」，眼睛是 `.accessibilityActions` 裡一顆真的按鈕、按了付同一份 `hinted`——形狀直
  接照抄 `ReviewHeroCard`：翻面前 VoiceOver 拿不到釋義，要拿就得觸發那個動作，而那個動作走
  的是 `flip()`。**但兩張圖片的標籤照常唸出那個詞。** 遮句子遮的是「不用聽就能讀到答案」的
  捷徑；圖片的內容不是捷徑，它就是選項本身。只唸「選項一 / 選項二」的結果是全盲使用者在猜
  硬幣，而 SRS 照樣記帳。代價是這條路徑上聽句實際變成「聽句子選詞」——題目仍是聲音、仍在考
  聽力，只是答案的載體從圖片換成文字。也因此**不能**用「VoiceOver 開著就不出聽句」來閃過：
  聽句很可能是全 App 對盲用使用者最友善的題型，而且 `UIAccessibility.isVoiceOverRunning`
  可以在場次中途被切換。
- **離線時聽句要讓位給 MCQ，因為它的退路對它有毒。** `SpeechService.play` 抓不到 clip 就退
  回 `AVSpeechSynthesizer`，而那正是預生成句子音檔的唯一理由——日文漢字讀音由 iOS 猜、無處
  可改。它還特別難抓：它不是「失敗」，它會**成功地**唸出可能是錯的東西，所以 `audioFailed`
  標記碰不到它。所以資格閘門多一條「音檔此刻播得出來」（`NetworkMonitor.isConnected` ＋
  `SpeechService` 那個私有快取查詢暴露成 `hasCachedClip(for:)`），不合格就出 MCQ——fallback
  早就在，成本是零。連帶：**題型在那張卡成為 `current` 的當下才決定**，不是場次開始時一次
  分配完，因為網路會在中途斷；Q10 的間隔規則（連續兩張不得都是聽句）在逐張決定下照樣成立，
  它本來就只看前一張。**學新字和詳情頁的離線合成不用跟著改**：那兩處句子攤在眼前、聲音是配
  菜，唸錯是瑕疵；這裡句子是遮住的、聲音就是題目——同一個退路在兩種承重狀況下該有兩種待遇
  （[ADR-0014](docs/adr/0014-listening-changes-the-rating-preconditions.md)）。
- **「這輪不做聽句題」是「我現在聽不了」，不是「這題太難」。** 聽句是全 App 唯一一個沒有聲
  音就作不了答的題型——沒帶耳機、在車上、旁邊有人——那跟難度無關，所以它沒有評分代價：切成選
  字不揭露任何東西，它換的是問題本身。按下去**連眼前這張卡一起換掉**，因為人是「答不了這一
  張」才按的，留著等於逼他答一題他剛說了聽不見的題；碼表跟著重來（現在是另一個問題了），音
  訊跟著停（理由和離開時一樣）。`replayCount` / `audioFailed` 不必清，`applyRating` 只在
  `kind == .hearSentence` 時才讀它們。
- **它確實部分復活了 Q10 否決 D 的理由**，這點要寫下來而不是裝作沒有：一個關得掉的難題型，
  會被最需要它的人關掉，於是「聽力答對率」變成只反映沒關的人。差別在於範圍——設定裡的開關會
  **無聲地**偏移往後所有資料，這顆鍵只影響這一場，而且使用者每一場都要重新按。
  **session 範圍是刻意的**，也和按鈕上的字（這輪）一致：`再來一輪` 會建一個全新的
  coordinator，所以下一輪重新問，不會默默繼承上一場對著另一個情境做的決定。
- **兩個旗標都寫進 `study_logs.metadata`，而且不只寫在聽句的列上。** `listeningOptedOut`
  跟著**每一種** activity 走——關掉之後這一場其餘的卡都以選字作答，而那些列若和「從來沒遇過
  聽句題」的場次分不出來，聚合出來的聽力答對率就是在一群自我選擇過的人身上算的。
  `convertedFromListening` 只標**使用者放棄的那一張**：它的 `activity` 誠實地寫著 `mcq`
  （那確實是他答的那一題），所以這是那個事實唯一活得下來的地方。兩個都是缺席而不是寫
  `false`——一般場次的選字列不該對一個它沒遇過的功能發表意見。
- **題型定下來之前，畫面上不准有答案。** `kind` 的預設值是 `.pickWord`，而選字的英雄卡片
  **就是答案本身的圖片**——所以在 `prepareQuestion` 回來之前照預設值渲染，會把答案閃給一張
  結果是聽句的卡片看。倒過來預設成 `.hearSentence` 也不行：那時還沒有句子可畫。誠實的第三
  個狀態是「還沒決定」（`questionReady`），未決定時畫骨架。骨架**必須是真的 view**：body
  渲染成空的話 `.task` 永遠不跑，於是題型永遠不會被決定、骨架變成永久的（`.task` 需要一個
  真的畫得出來的 view，這個 repo 已經踩過一次）。骨架也刻意對兩種題型長得一樣——一個已經長
  得像聽句的骨架，等於用比較小的音量把它要防的那件事講出來。
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
- **看完整詳情 — 提示面上的第二次點擊。** 翻面那一**面**仍然只有釋義，上面那條規則沒有變；
  變的是那一面現在有一個明說的出口，點下去用 `WordDetailSheet` 從下方升起完整詳情——單字
  本體、讀音、字詞資料、例句都在裡面。**代價刻意不變**：能按到這顆鍵的人已經翻過面，該題
  早就套上答錯的評分表、自動評級也早就關了，再疊一層懲罰只會把人逼回亂猜（ADR-0007 那句
  「這顆鍵必須輕到值得按」）。順帶記下一件本來就成立的事：英雄卡片右下角的
  `PronunciationButton` 在作答階段一直都在，按下去唸的就是答案——「讀音不准出現在提示面」
  從來只是**畫面**上的規則，不是資訊上的封鎖。
  兩條讓它不出事的限制：按鈕只在 `phase == .answer` 出現（揭示表 rest detent 開著
  `presentationBackgroundInteraction`，這一面在它底下仍然可點，留著就會在評分鍵上面再疊一
  張 sheet——而那張 sheet 往上拉本來就是同一份詳情）；以及提示面要 `.allowsHitTesting(up)`，
  因為兩面是用 opacity 疊的，透明度 0 的 Button 照樣吃點擊。
- **例句的 詞塊 要有人接。** `InteractiveSentenceText` 讀 `\.glossSelection`，沒有 host
  就整句退回純文字——「有連結但沒人接」比沒有這個功能更像壞掉。認識、圖鑑詳情、學新字的
  peek sheet 一直都有 `.glossCard()`，**複習的揭示表沒有**：同一句例句在剛答錯的那一刻是
  死的，而那正是最需要點開看的時候。現在揭示表與 `WordDetailSheet` 都有 host。
  位置有講究：host 要放在 sheet 的**根**、而且在畫標題列的 shell **外面**——`.glossCard()`
  的遮罩是它所依附那層的 overlay，掛在 `TujiSheetShell` 的 content 裡會停在標題列下面，
  讓 ✕ 在一張 modal 卡片底下還是亮的、還能按。這件事現在**由 `.tujiSheet(…)` 自己做**
  （掛在 shell 外面），所以 sheet 那條路由結構保證，`ReviewHeroCard` 手寫
  `TujiSheetShell { … }.glossCard()` 的理由消失了，已經收回去用便利函式。
  **同一個洞後來在物見的詳情頁又出現一次**（`AtlasPublicDetailView`，`AtlasSavedItemDetailView`
  也是走它）。那頁最容易被當成不適用：自製圖鑑的內容本來就沒有例句。但當一張照片的詞頭剛好
  也是目錄詞時，`/api/atlas/public/{slug}` 會把那個目錄詞的例句連同標註一起掛上去——所以那
  一頁一直有可點的資料、沒有人接。教訓寫在 `AtlasPublicItemSpansTests`：**這條線在那之前
  連一個從 JSON 解出 `GlossSpan` 的測試都沒有。**它是全 App 第一個同時有系統導覽列與
  `.glossCard()` 的畫面；遮罩會蓋過導覽列（它 `ignoresSafeArea`），但返回鍵仍然可按——按下去
  整頁連卡片一起 pop，所以刻意不處理。
  **第三次由 CI 擋下**：`scripts/check-gloss-host.py`（跟 `check-localization.py` 同一個 job）
  要求任何渲染例句的檔案都得有 `.glossCard()`，否則要列進腳本裡的 `HOSTED_BY_CALLER` 並寫
  下理由。它會剝掉註解才比對——四個談到 `.glossCard()` 的檔案裡有三個只是在散文裡提到它，
  照原文 grep 會讓每一個「寫下了規則但沒有遵守」的畫面過關。
- **唸出來這件事 (`SpokenWord` / `SpeechPlaying`)** — 「這個字現在該播哪一段聲音」與
  「播，並在播完時告訴我」是兩個問題，各有一個模組。
  - **`SpokenWord`** — 要唸什麼（`text` / `language`），以及去哪裡找它的錄音
    （`clips` 呼叫端手上有的，否則 `wordId` 問目錄）。`StudyQueueWord` **沒有**
    `audioUrls`（佇列 payload 刻意精簡），所以每個學習畫面都得往目錄側身去拿——那個
    `words.find(id:)?.audioUrls` 被寫了八次，而同一張卡片上相隔 28 行的兩個答案不一樣：
    `RecognizeView.autoPlay` 會退回預抓的 detail，它底下那顆喇叭鍵不會。優先順序現在只
    寫一次：呼叫端手上有的贏。`WordClipReading` 是那條讀取 seam（`CatalogueClips` 是實
    作）。**詞塊刻意不帶 `wordId`**：`wordId` 是用原形對出來的，所以 `documents` 連到的
    是 `document` 的錄音——跟音標那條規則同一個理由。
  - **`SpeechPlaying`**（`SpeechPlayback`）— 原本叫 `ListeningAudio`、住在 `Core/Study`，
    而且只有一個呼叫者。裡面沒有一行是聽句專屬的，**module 不該用它唯一的呼叫者命名**。
    它與 `SpeechService.playback` 的不對稱是刻意的：`PronunciationButton` 要的是**狀態**
    （播放時底色轉瞳黃），聽句要的是**事件**（await 到播完），照任一邊的形狀去設計服務，
    就是讓另一邊用不到它的做法。
  - **底色轉瞳黃是按 request id 判斷的**，不是全域旗標：service 是單例，複習的英雄卡上
    就有一顆會唸出答案的喇叭鍵，全域旗標會讓一顆的 clip 點亮另一顆。這個洞從
    `PronunciationButton` 上線起就記在它的檔頭裡，聽句那批工作讓它成立了、
    `SpeechService` 的檔頭也宣告補上了——但沒有。
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
    `user` parameter threaded to 我/`tujiNavDestinations`, and reading the environment
    beside it would create a second source rather than remove one. It was threaded to 今天
    too, and 今天 never read it — the parameter was referenced nowhere in `TodayView`'s
    body, every identity question there going through this seam. Removed.
    `EditProfileView.sessionUser` also stays — it is the *edit form's* current values, so
    the nickname must arrive raw, where `displayName` would hand back the UID and the form
    would offer to save that as a nickname.
  - **ViewerRelationship** — `.guest` / `.mine` / `.theirs`, derived from `isGuest` +
    `owns(handle:)`. The seam answered "is this handle mine"; every consumer needed
    "what may I do about this person's work" and recombined the two primitives itself —
    物見詳情 spelled it `!isGuest && !owns` for 檢舉/封鎖 and `owns` alone for the
    「你的分享」 pill three hundred lines later, and 作者主頁 kept a pair
    (`isOwnProfile` / `canModerate`) whose third consumer went around both. **That cost a
    live bug**: the nav bar branched on the route's `isSelf` alone, and every byline in
    the app pushes `isSelf: false`, so reaching your own profile through one matched
    neither arm and drew **no control at all**. A signed-in viewer is now always exactly
    one of `.mine`/`.theirs`, which is what a `switch` can rely on. `isSelf` stays and
    still has no default — it is the *route's* claim ("the caller opened this as my
    page", which is also what makes the fetch bypass its caches), a different signal from
    the UID compare; the union is stated once.
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
