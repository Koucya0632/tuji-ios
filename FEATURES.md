# Tuji iOS 功能邏輯總覽

本文件描述 Tuji iOS App 內所有功能的邏輯與規則,並標註對應的原始碼位置。
後端 API 位於同層的 `../tuji-web`(Next.js);iOS 端只負責呈現與客戶端規則,伺服器是所有資料的最終權威。

---

## 目錄

1. [App 架構與啟動](#1-app-架構與啟動)
2. [導航與 Deep Link](#2-導航與-deep-link)
3. [帳號與登入](#3-帳號與登入)
4. [Onboarding(首次使用流程)](#4-onboarding首次使用流程)
5. [主頁(Today)](#5-主頁today)
6. [學習系統(Study)](#6-學習系統study)
7. [熟練度與進度](#7-熟練度與進度)
8. [圖鑑與單字瀏覽](#8-圖鑑與單字瀏覽)
9. [搜尋](#9-搜尋)
10. [收藏](#10-收藏)
11. [自製圖鑑(Atlas 拍照新增)](#11-自製圖鑑atlas-拍照新增)
12. [Tuji Pro 訂閱](#12-tuji-pro-訂閱)
13. [設定](#13-設定)
14. [基礎設施](#14-基礎設施)

---

## 1. App 架構與啟動

### 進入點 — `Tuji/TujiApp.swift`

- `@main TujiApp` 在 `init()` 先安裝自訂 Nuke 圖片管線(`TujiImagePipeline.install()`),必須在任何 `LazyImage` 渲染前完成。
- 以 `@State` 建立所有單例 store,並注入 SwiftUI environment:`AuthService`、`PushNotificationService`、`OnboardingState`、`LocalCache`、`WordsStore`、`CategoriesStore`、`SettingsStore`、`ProgressStore`、`MasteryStore`、`StudyStatsStore`、`StudyFocus`、`DeepLinkCoordinator`。
- 啟動時的 `.task`:載入字典 + 分類 + 設定、刷新推播授權、重播離線答題 outbox(`StudyAnswerOutbox.replay()`);App 回到前景(`scenePhase == .active`)時再重播一次。
- `.onOpenURL` 先交給 GoogleSignIn 處理 OAuth callback,再嘗試解析成 `TujiDeepLink`。
- environment locale 由 `settings.uiLang` 決定(僅 `zh-Hant` / `zh-Hans`,未知值 fallback 到 zh-Hant)。

### 架構模式

- **單例 @Observable store**(`Core/*`)持有所有共享狀態;View 透過 `@Environment` 讀取。
- **Repository 協定**(`Core/Repositories/*`)包裝 API 呼叫,便於單元測試注入。
- **Coordinator**(學習流程)是純狀態機,View 只負責渲染。
- 專案預設 MainActor isolation;需要跨 actor 的型別(Codable payload、純值 enum)標 `nonisolated`。

### 頂層狀態切換 — `Tuji/Navigation/RootView.swift`

```
App 啟動
  ├─ AuthService.checking          → SplashView
  ├─ .signedOut
  │    ├─ 未選學習方向              → LearningDirectionOnboardingView
  │    ├─ !introDone               → OnboardingFlow(3 頁行銷介紹)
  │    └─ introDone                → WelcomeView(登入/註冊/訪客)
  ├─ .guest                        → 內容就緒前 SplashView,之後 MainTabsView(user: nil)
  └─ .signedIn(user)
       ├─ 未選學習方向              → LearningDirectionOnboardingView
       ├─ !setupDone(user.id)      → SetupView(選主題 + 每日目標)
       ├─ !contentReady            → SplashView
       └─ 全部就緒                  → MainTabsView(user:)
```

- `contentReady = words.loaded && categories.loaded`:「載入完成」包含失敗(失敗也放行,讓主頁自己顯示重試),避免卡死在 Splash。
- Splash 有最短顯示時間(850ms,`reduceMotion` 時跳過),與 `auth.restoreSession()` 並行。

---

## 2. 導航與 Deep Link

### 四大分頁 — `Tuji/Navigation/MainTabsView.swift`, `MainTab.swift`

- 分頁:主頁(today)/ 圖鑑(cards)/ 進度(progress)/ 我的(me)。
- 自訂浮動膠囊 tab bar(非 SwiftUI TabView);每個分頁擁有獨立 `NavigationStack`,互不干擾。
- 分頁以水平 paging ScrollView 呈現,可左右滑動切換;但學習中(`StudyFocus.active`)或當前分頁已 push 詳情(path depth > 0)時停用滑動,避免與返回手勢衝突。
- `StudyFocus.active` 時隱藏 tab bar,釋放垂直空間。

### 路由 — `Tuji/Navigation/NavRoute.swift`, `TujiNavRoutes.swift`

`NavRoute` enum 集中定義所有可 push 的目的地(cards / today / search / favorites / settings / atlasManage / studyCategories / studyLanding(mode) / wordDetail(id) / categoryDetail(id));每個 NavigationStack 掛 `tujiNavDestinations(user:)` 統一解析。

### Deep Link — `Tuji/Navigation/DeepLink.swift`, `DeepLinkCoordinator.swift`

- 同時接受 `tuji://…` scheme 與 `https://tuji.app/…` universal link,解析成 `(tab, route)`。
- 支援:`today`、`cards`、`favorites`、`settings`、`search?q=`、`word/{id}`、`category/{id}`、`study?mode=new|review`。
- `DeepLinkCoordinator` 暫存 pending link(啟動期間 link 可能先於 tab shell 掛載到達);`MainTabsView` 在 `onAppear` / `onChange` 消費:先切分頁,下一個 runloop 再 push route。Deep link 優先權高於功能導覽(會先跳過 tour)。

### 首次功能導覽 — `Tuji/Features/Tour/FeatureTour.swift`, `FeatureTourOverlay.swift`

- 各 View 以 `.tourAnchor(_:)` 標註高亮目標(hero、CTA、每日目標、連勝、tab bar、拍照鈕),經 PreferenceKey 匯集到 `MainTabsView` 渲染遮罩。
- 步驟依訪客/登入身分不同(訪客沒有 CTA 對,fallback 到整張 hero 卡,文案也不承諾無法做的動作)。
- 進入條件:`!tourDone` 且無學習中、無 pending deep link;結束(完成或跳過)寫入 `tourDone`(裝置層級)。完成後切回主頁分頁。

---

## 3. 帳號與登入

### 狀態機 — `Tuji/Core/Auth/AuthService.swift`

- 狀態:`.checking → .signedOut / .signedIn`;`.signedOut ⇄ .guest`(訪客模式)。
- **Email**:`signUp`(可能回 `pendingEmailConfirmation`,確認信 redirect 到 `TUJI_BASE_URL/auth/confirmed`)、`signIn`。
- **Apple**:`AppleSignInBridge` 取得 idToken + nonce → Supabase `signInWithIdToken`。Apple 只在「第一次授權」提供姓名,若使用者暱稱為空就立刻存成 nickname(`captureAppleNameIfNeeded`)。
- **Google**:`GoogleSignInBridge` 原生流程取 idToken → Supabase(Supabase 專案需開 Skip nonce checks,SDK 不支援 nonce)。使用者取消不顯示錯誤。
- **登出**:先(並行)刪除裝置推播 token,再 Supabase signOut + 清 Google 快取。
- 錯誤訊息經 `friendly()` 轉成中文(密碼錯誤、Email 已註冊、rate limit…)。

### 訪客模式

- `.guest` 可瀏覽圖鑑/收藏(僅本機 LocalCache),不能學習(SRS 綁帳號)。
- 從訪客按「登入/註冊」→ `exitGuestMode()` 回 Welcome,並記 `cameFromGuest` 讓 Welcome 顯示關閉鈕(可退回訪客),避免誤觸變死路。

### 登入時本機資料上行

`syncLocalCacheToServer()`:登入/註冊成功後,把訪客期間累積的收藏 + 已學 id 上傳 `/api/users/sync`(union 語義,永不丟資料)。失敗僅記 log。

### Session / Token

`validAccessToken()` 給 `APIClient` 用;supabase-swift 讀 session 時自動 refresh。

---

## 4. Onboarding(首次使用流程)

### 狀態 — `Tuji/Core/Onboarding/OnboardingState.swift`(UserDefaults 持久化)

| Flag | 範圍 | 意義 |
|---|---|---|
| `learningDirection` | 裝置 | 學習方向(zh-en / zh-ja),未選時強制先選 |
| `introDone` | 裝置 | 3 頁行銷介紹看過 |
| `tourDone` | 裝置 | 功能導覽完成 |
| `setupDone.<uuid>` | 每帳號 | Setup 選題完成 |

### 學習方向選擇 — `OnboardingFlow.swift` 內 `LearningDirectionOnboardingView`

選英文/日文圖鑑;未登入 `persist: false`(只寫 UserDefaults),登入中會 POST 設定。選完 invalidate + reload 字典與分類。

### 行銷介紹 — `OnboardingFlow`

3 頁(用圖學語言 / 每天 3 分鐘 SRS / 連勝與圖鑑),可跳過;完成寫 `introDone`。

### 首次設定 — `Tuji/Features/Onboarding/SetupView.swift`

- 每個新帳號一次:選學習主題(預設勾 kitchen / bathroom / living-room,若資料集沒有則取前三個)+ 每日目標(5/10/20 題)。
- 主題必須至少選一個才能送出;寫入的是 canonical kebab-case id(後端會過濾非法值)。
- 儲存成功後:`settingsStore.adoptPersisted()` 立即生效 → `markSetupDone` → 並塞一個 `.study(mode: .new)` deep link,讓 CTA「開始今天的 N 題」直接進入學新字,而不是丟在主頁。

---

## 5. 主頁(Today)

檔案:`Tuji/Features/Today/TodayView.swift`

### 資料載入

- `TodayVM.load()` 並行抓 `/api/users/me` + `ProgressStore.loadIfStale()` + `StudyStatsStore.loadIfStale()`(共享 store,30 秒 TTL,分頁互切不重打)。
- 訪客不打網路,只讀 LocalCache + WordsStore 呈現降級版 hero。
- 載入完成後**預抓學習佇列**(`prefetchStudyQueues`):只 prefetch 未被停用的 CTA 對應 mode,讓按下 復習/學新字 時跳過 spinner。

### 問候與副標

- 依時段顯示 早安/午安/晚安 + 暱稱(nickname → username → email local part → 探險者)。
- 副標優先序:訪客文案 → 未選主題提示 → stats 未載入時中性句(避免亂下結論)→ 有到期字(`今天有 N 個字要復習`)→ 每日目標達成 → 今天已學 N 個 → 還沒學新字 → 主題字都學完。

### Hero 卡

- **今日目標進度條**:`todayNew / dailyGoal`(只計新字,復習不算);達成顯示「達成」徽章 + 吉祥物切換 cheer 姿勢。
- **主題進度條**:所選主題的 `seen / total`(伺服器數字;訪客 fallback 本機 learned 數;未選主題顯示 0/0)。
- **CTA 按鈕**:
  - `復習` disabled 條件:訪客或 `due == 0`。
  - `學新字` disabled 原因(`NewBlockReason`):未選主題(noThemes)/ 所選主題無卡片(noCards)/ 主題新字學完(allLearned)/ 復習積壓把新字額度壓到 0(reviewBacklog)。
  - 每個灰掉的按鈕都有一行說明(不留無聲死按鈕);另有「因為還有 N 個字要複習,今天新字先調整為 M 個」的額度調降提示。
- **訪客版 hero**:兩顆學習鈕換成「建立帳號,開始學習」。

### 主題格

- 登入:只顯示使用者選的主題(且有字);訪客:前 4 個有字的分類。
- 完成標章:`全精通`(主題內每個字都達精通 ≥80,紫色皇冠)優先於 `完成`(seen == total,青色勾)。
- 未選主題時顯示「選擇主題」引導卡。

---

## 6. 學習系統(Study)

### 6.1 每日額度 — `Tuji/Core/Study/StudyQuotas.swift`

新字額度隨復習積壓遞減(與後端 `lib/scheduling.ts` 一致):

| 到期數 due | 新字額度 |
|---|---|
| ≤ 20 | goal(每日目標) |
| 21–50 | goal × 0.75 |
| 51–100 | goal × 0.5 |
| > 100 | 0 |

### 6.2 佇列快取 — `Tuji/Core/Study/StudyQueueStore.swift`

- 每個 mode 一份 prefetch 快取,TTL 90 秒;簽章(mode|limit|new|categories|due)不符即失效。
- 參數規則:`new` mode 用 `computeNewLimit`,分類 = 使用者所選主題;`review` mode `limit = min(due, 30)`,不帶分類(復習跨全部已學字)。
- 自製圖鑑一個 item 可能帶兩張卡(image_recall + flashcard),以 `word.id` 去重,同字一場只出一次(保留第一筆,伺服器把進行中復習排在前)。
- `take()` 消費式讀取(命中即清除);學習結束時 `invalidate()` 全清。

### 6.3 啟動器 — `Tuji/Features/Study/StudyLauncherView.swift`

從主頁 CTA 或 `tuji://study` 進入 → 先讀 warm queue,miss 才 live fetch → 空佇列或錯誤時 prompt(再試一次 / 稍後再說並退回)→ 有佇列即 push 對應流程。使用者從流程離開時 launcher 也自動 dismiss(不會卡在 spinner)。

### 6.4 學新字流程(NewFlow)— `NewFlowCoordinator.swift`

**交錯任務佇列**,不是三個阻塞階段。每個字走 認識 → 選字 → 拼字,其他字的任務穿插其間,讓測驗是從短期記憶提取而不是回聲。

- **初始排程**:`rec(wᵢ)@3i, id(wᵢ)@3i+4, spell(wᵢ)@3i+8` 排序 — 每字的階段間隔約 2–3 個其他任務。單一 tile 的字**不排拼字**(一格拼圖是送分題)。
- **開場預覽**:session 先顯示今天要學的字清單(pre-teach),按「開始學習」才進入任務;`NewFlowTeachLoader` 逐字預抓完整詳情(定義+例句),供認識卡教學用(自製字直接用內嵌 detail,miss 就渲染純卡,絕不擋流程)。
- **認識(RecognizeView)**:教學卡(圖 + 自動發音 + 中文 + 定義/例句),自評三鈕:第一次見=重來 / 有點印象=困難 / 已經認識=穩定。**已認識走快速路徑**:跳過該字的選字(仍要過拼字把關)。評分先暫存(pendingRatings),不立即寫 SRS。
- **選字(IdentifyView)**:看圖+中文選正確單字(MCQ)。答對 500ms 後前進;答錯凍結、顯示 WordPeek 講解、任務 requeue 到 3 格之後,且**每次重試換一組選項排列**(attempt 折入 seed)。首次作答延遲記為 responseMs(重試不計時)。
- **拼字塊(TilesView)**:只給圖+中文(不給字),把打散的 tile 拼回。棋盤規則見 `NewFlowTasks.swift`:每個空白 token 一列(空白不是 tile)、小假名(ゃゅょ等)黏到前一 mora、日文以 `reading`(假名)出題、總 tile 上限 10(超過就 re-chunk);scramble 依 (item, attempt) 決定性生成,且保證不會直接排成答案。答完自動判定,錯誤同樣 peek + requeue + 換 scramble。
- **階梯保護 `normalizeHead()`**:requeue 後若拼字跑到自己字的選字前面,把拼字往後推(先選字後拼字的順序永遠成立)。
- **SRS 寫入 `commitLearned()`**:字清完最後一關才 POST 一次 `/api/study/answer`。實際送出的評分會被測驗表現降級:錯 1 次降一級(`downgraded`),錯 ≥2 次直接送 `重來`;附上首次選字延遲。今日目標只計「完整走完」的字。
- **combo**:連續答對 ≥3 吉祥物切 cheer;答錯歸零。
- 進度條分母 = 排定階段總數(requeue 不膨脹分母,只會前進)。

### 6.5 復習流程(ReviewFlow)— `ReviewFlowCoordinator.swift`

每題:`answer`(4 選 1 MCQ)→ 三種路徑:

| 情境 | 行為 |
|---|---|
| 快答對(建議評分 ≠ 困難) | **自動套用建議評分**,閃現膠囊(700ms)直接下一題,不彈 sheet |
| 慢答對 | Reveal sheet,手動選 困難/穩定/熟練 |
| 答錯 | Reveal sheet,只有 重來/困難(困難=「按錯了其實記得」;更高評分會讓漏掉的字跳過重學) |

- **建議評分 `computeSuggestion`**:答錯=重來;<3 秒且熟練度 ≥50 → 熟練,否則穩定;3–7 秒 → 穩定;>7 秒 → 困難。(低熟練度的字快答只算正常回想,不給長間隔跳升。)
- **答錯 requeue**:第一次答錯的字 append 到佇列尾端,session 內再測一次;**retest 絕不寫第二次 SRS**(第一次的 重來 已重排;retest 答對閃過、答錯只給「下一題」純講解)。每字最多 requeue 一次。
- 每次字離開畫面 `presentedCounts+1` 折入選項 seed,re-test 一定重新洗牌。
- **樂觀寫入 `persist()`**:UI 立即前進,背景重試 3 次(退避 400ms×n);全部失敗 → 存入持久 `StudyAnswerOutbox` 並累加 `unsyncedCount`。回應中的 mastery before/after 合併進 `masteryByWord`(同字二測保留最早 before、最新 after);伺服器帶 `milestone` 就記錄。
- 進度條以「不同字完成數」計,reveal 中加 0.5 半步。
- 結束前 `drainPendingWrites`(上限 800ms)讓完成頁的變化資料儘量齊全。

### 6.6 MCQ 選項公平性 — `StudyChoiceFallback.swift`

`studyChoices(for:pool:variant:)` 是唯一入口:

1. 先用伺服器給的 choices(同分類、難度佳),但**剔除不公平干擾項**:與答案共用中文釋義(pan / frying pan 都是平底鍋)、token 互為子集(knife / kitchen knife)、CJK 互為子字串(時計 / 腕時計)。
2. 不足 3 個干擾項時從本機字典補:先同語言,再放寬到全部。
3. 洗牌用 `SeededRNG`(SplitMix64)+ FNV-1a 穩定 hash:同一張卡跨 re-render、跨 App 重啟順序都不變;`variant`(答錯次數)改變 seed 讓重試重洗。

### 6.7 離線與同步保證

- **`StudyAnswerOutbox`**(`Core/Study/StudyAnswerOutbox.swift`):寫入失敗的答題持久化到 Application Support JSON,App 啟動/回前景時依序重播;第一筆失敗即中止本輪(同一個網路後面也會失敗)。後端容忍重複答題。
- **`drainPendingWrites`**(`StudyWriteDrain.swift`):把「所有 in-flight 寫入完成」與 timeout 賽跑,先到先贏;沒趕上的寫入照常在背景跑完並經 @Observable 合流。完成頁 reload 前先 drain,避免 reload 跑贏寫入、剛學的字顯示過期狀態。
- `submitAnswerBestEffort`(`StudyRepository.swift`):重試 3 次(400ms 指數退避)後進 outbox。

### 6.8 完成畫面

- **CompleteView**(復習後):吉祥物 + 復習字數 + 連勝膠囊 + 未同步提示(unsyncedCount > 0)+ 每字熟練度變化列表(before→after、升級箭頭、答錯過標記)。`refresh()` 會 invalidate + reload progress/stats/mastery 並清掉 prefetch 佇列;刷新後若仍有到期字,主 CTA 變「再來一輪(還有 N 字)」直接串下一輪。復習**不計入**每日目標。
- **NewDoneView**(學新字後):先 `drainPendingWrites`(上限 2 秒)再 reload mastery/stats/progress(最後一字的寫入最容易沒趕上,會二次 drain + reload);列出本次學的字與錯誤次數徽章。
- **MilestoneView**:伺服器在答題回應附 `milestone: { streak }` 時顯示連勝里程碑慶祝(30/100/365 天;iOS 已接線,伺服器尚未發送)。

### 6.9 報錯 — `StudyReportSheet.swift`, `Core/Models/StudyReport.swift`

兩個流程的工具列都有「報錯」:擷取當前題目快照(word、選項、顯示中的拼字、mode、phase、已選答案、uiLang、App 版本)→ 選問題類型 + 描述 → POST `/api/study/reports`。

### 6.10 學習專注模式 — `Core/Study/StudyFocus.swift`

引用計數(非 bool)的「學習中」旗標:Launcher → Flow → Complete 換頁瞬間不會歸零導致 tab bar 閃現。搜尋頁與單字詳情頁也借用它隱藏 tab bar。

---

## 7. 熟練度與進度

### 7.1 五級熟練度 — `Tuji/Core/Study/MasteryLevel.swift`

由伺服器 0–100 分數在**客戶端獨立推導**(忽略伺服器的 level 物件;web 是另一套 4 級):

| 級別 | 分數 | 顏色 |
|---|---|---|
| 未學 | 無紀錄 / 0 | 灰 |
| 知道 | 1–34 | 珊瑚 |
| 熟悉 | 35–59 | 黃 |
| 熟練 | 60–79 | 青 |
| 精通 | 80–100 | 綠 |

圖鑑格徽章只有精通用綠色,其餘一律中性灰(`tileBadgeColor`);詳情頁用全彩。

### 7.2 資料 store

| Store | 來源 | 快取策略 | 用途 |
|---|---|---|---|
| `MasteryStore` | GET `/api/users/mastery` | loadIfNeeded 一次;學習後 invalidate+reload | wordId→分數 與 wordId→下次復習時間;圖鑑徽章/倒數 |
| `ProgressStore` | GET `/api/users/progress` | 30s TTL loadIfStale | 連勝、42 格熱力圖、每分類 seen/total |
| `StudyStatsStore` | GET `/api/study/stats` | 30s TTL(鏡像伺服器 revalidate) | due/new/todayNew,主頁 CTA 與佇列參數。**全域抓取**(不帶分類):復習跨全部已學字 |

- `ReviewSchedule`(`Core/Study/ReviewSchedule.swift`):圖鑑格的「下次復習」倒數文案(復習期 / N 分鐘後 / N 天後 / 約 N 週後…),移植後端 `humanizeInterval`;並提供容忍小數秒的 ISO8601 解析(全域 decoder 的 `.iso8601` 不吃 `.SSS`,所以時間欄位以 String 解再手動 parse)。

### 7.3 進度分頁 — `Tuji/Features/Progress/ProgressTabView.swift`

- 圖鑑完成度(所選主題 seen/total 百分比)、目前/最長連勝、最近 6 週熱力圖(0 / 1–4 / 5–12 / >12 四檔深淺)、每分類明細(依所選主題過濾,空選=全部)。
- 訪客顯示登入提示空狀態。
- **清除學習進度**放在 設定 → 帳號(不在進度頁,破壞性操作不該離統計一步之遙):DELETE `/api/users/progress` 後同時 `cache.clearLearned()`(sync 是 union-only,不清本機會在下次登入把已清除的 id 復活)+ invalidate/reload progress 與 stats。收藏、設定、自製圖鑑不受影響。

---

## 8. 圖鑑與單字瀏覽

### 資料來源

- **`WordsStore`**(`Core/Words/WordsStore.swift`):啟動抓一次 GET `/api/words`(帶 uiLang + learningDirection),接著抓 `/api/users/custom-words`(自製字,id 為 `atlas:<uuid>`,內嵌完整 detail)合併 — 以 id last-wins,再按 分類→字母 排序。全 App 共讀這份記憶體字典。
- **`CategoriesStore`**:GET `/api/categories`(本地化分類名)。

### 圖鑑列表 — `Features/Cards/CardsListView.swift`

2 欄格 + 分類 chip 過濾 + 分頁載入(每頁 60);頂部相機鈕開自製圖鑑拍照流程,`AtlasCaptureProgressStrip` 顯示製作中的卡。點格開 WordPeek(輕量預覽),從 peek 再進完整詳情。

### 分類頁 — `Features/Category/CategoryView.swift`

插畫 hero(中英名 + 說明)+ 該分類全部單字的 2 欄格。

### 單字詳情 — `Features/Word/WordDetailView.swift`

- 進入後是**水平分頁 TabView**:可左右滑到圖鑑順序的前後字,不用退回格子。
- 每頁按需抓 GET `/api/words/{id}` 完整資料;各區塊(定義/例句/搭配詞/詞形/字源)有資料才渲染。
- 全螢幕模式:進入時 `StudyFocus.enter()` 隱藏 tab bar。

### WordPeek — `Features/WordPeek/WordPeekSheet.swift`

底部輕量預覽 sheet,兩種模式:
- 一般(圖鑑/收藏):hero + 單字 + 收藏 + 發音,CTA「看完整詳情」→ dismiss 後 push 詳情。
- 學習答錯(`showDetailOnExpand: true`):CTA「下一題」;上拉到 .large 內嵌展開完整詳情,不離開流程。

### 發音 — `Core/Speech/SpeechService.swift`, `Components/PronunciationButton.swift`

- 優先播伺服器預生成音檔(`audioUrls`,依 locale),下載後存 Caches 磁碟快取(重播即時、離線可用);失敗 fallback 到 `AVSpeechSynthesizer` 裝置合成。
- 語音選擇 `Voice.preferred`:字自己的語言優先(JA 字在英文 session 也念日文),否則跟學習方向;英文再依 口音設定 選 en-US / en-GB。
- audio session 用 `.playback + .duckOthers`:靜音鍵下仍出聲,背景音樂暫時壓低、播完恢復。快速連點會先停掉前一段。

---

## 9. 搜尋

檔案:`Features/Search/SearchView.swift`

- **本地優先**:每個 keystroke 直接對記憶體字典做即時排名過濾(exact > prefix > 中文 prefix > contains > 中文 contains > 假名 > 音標;同 rank 短字優先)— 離線可用、零延遲。
- 同時發 250ms debounce 的 GET `/api/search` 補足本地看不到的結果(同義詞、別名、模糊),回來後與本地結果合併去重(本地排前)。過期回應(query 已變)直接丟棄。
- 伺服器搜尋失敗且本地已有結果 → 不顯示錯誤。
- 空輸入顯示最近搜尋(LocalCache,上限 10 筆,LRU);有結果的查詢才寫入歷史。
- 結果高亮命中子字串;進入搜尋頁自動 focus 並隱藏 tab bar。

---

## 10. 收藏

- **來源**:`LocalCache.favoriteIds`(UserDefaults)是唯一事實來源;訪客純本機,登入者由 `FavoriteButton` 樂觀更新本機後 fire-and-forget POST `/api/users/favorites`,登入時再由 sync 統一 union。
- **`Features/Favorites/FavoritesView.swift`**:favoriteIds × WordsStore 直接渲染,不打 GET;分類 chip 只顯示有收藏的分類;排序 A→Z / Z→A / 依主題;點格開 WordPeek,長按 contextMenu 移除收藏。

### LocalCache — `Core/Cache/LocalCache.swift`

- 持有:favorites、learned(**按語言分開** `tuji.cache.learned.en/.ja`,舊單一 key 自動遷移進 en)、recentSearches、匿名 sessionId。
- `mergeFromServer` / `syncSnapshot` 皆 union 語義;`clearLearned` 只在清除學習進度時呼叫。

---

## 11. 自製圖鑑(Atlas 拍照新增)

### 流程總覽

```
拍照/選相簿 → 裁切(ImageCropView) → 下採樣(≤1600px JPEG)
  → 上傳 /api/atlas/images(辨識在同一請求內完成,candidates 隨上傳回來)
  → 校正表單(候選 chip / 手動修改 lemma + 中文)
  → [可選] AI 識別(primary)/ 高精度(escalate, Pro 限定) 重跑
  → 確認並生成卡片 → 交給背景佇列:confirm → createCards → enrich → sync
```

### View Model — `Features/Atlas/AtlasCaptureVM.swift`

- 擁有整條管線狀態;「放棄重來」= 直接換一顆新 VM。
- **每個辨識 mode 最多跑一次**,結果快取(`candidatesByMode`),再點同 mode 免費重顯示(重跑幾乎不變、只燒額度);失敗/空結果不算 final,可重試。
- 候選自動套用規則:排 rank 後優先取 fine 級;`apply(overwrite:)` — 使用者點 chip 才覆蓋欄位,自動套用只填空欄(不覆蓋手動輸入)。
- 402(額度用盡)→ 開 Paywall 而非顯示錯誤;失敗的上傳保留原始 bytes 可原地重試。
- 放棄時 best-effort 刪除已上傳影像(未確認的照片不留在帳號)。

### 額度 — `Core/Atlas/AtlasQuotas.swift`, `AtlasStore.entitlement`

- 鏡像伺服器 `lib/atlas/entitlement.ts`;**entitlement 未知時一律放行**(伺服器才是權威,UI 保持寬鬆)。
- 規則:自製圖鑑格數上限(Free 少 / Pro 300)、普通 AI 每月軟上限(Free 30 / Pro 500)、高精度 Pro 限定(Free 上限 0,Free 點高精度直接進 Paywall,不浪費一次必 402 的呼叫)。
- 滿格時擋拍照並顯示對應文案(Pro:刪一些;Free:升級或刪一些)。

### 背景佇列 — `Core/Atlas/AtlasCaptureQueue.swift`

- 確認後的重尾(confirm → createCards → enrich → 一次對帳 sync)在 @MainActor 單例佇列跑,sheet 立即關閉;圖鑑頁顯示「製作中」占位卡(`AtlasCaptureProgressStrip`)。
- **弱網韌性**:job 持久化到 Application Support;App 被殺後啟動時恢復續跑。confirm 是**非冪等** INSERT — 成功後 checkpoint `itemId`,恢復時跳過 confirm 只重跑(冪等的)createCards 之後。
- enrich(定義/同義詞/詞形/字源)best-effort,失敗不影響卡片(詳情頁開啟時會 lazy enrich)。
- 完成後 `reload()`(絕不 `invalidate()` — 那會清 `loaded` 把整個 App 彈回 Splash)刷新 WordsStore(新卡要出現在圖鑑格)+ ProgressStore + StudyStatsStore,並以 OSSignposter 打點各階段耗時。
- 失敗的 job 保留占位卡供手動 retry(從 checkpoint 續跑)或移除。

### 資料同步 — `Core/Atlas/AtlasStore.swift`

`/api/atlas/sync` 增量同步(since = 上次 serverTime),merge 進 images/items/cards/cardStates/mastery,過濾已刪除;每次 sync 後刷新 entitlement。MeView 掛載時就 warm 這個 store。

### 管理頁 — `Features/Atlas/AtlasManageView.swift`

列表式查+刪(建立只在拍照流程;編輯待後端 PATCH):以 image 為 key join item 顯示;支援單刪與多選批刪;刪 image 級聯刪 item + cards。注意 `TujiPrompt` 會先把 backing state 設 nil 再跑 action,所以待刪目標要先抓 local copy。

### 學習整合

自製字進統一學習流程(`/api/users/custom-words` → WordsStore,queue 內按 word.id 去重);mastery 在伺服器端獨立 namespace(`user_atlas_item_mastery`),由 `/api/users/mastery` 合併以 `atlas:<itemId>` 回傳。

---

## 12. Tuji Pro 訂閱

### StoreKit 2 — `Core/Billing/StoreKitService.swift`

- 產品:`app.tuji.pro.monthly` / `app.tuji.pro.yearly`(自動續訂)。
- **伺服器是 entitlement 權威**:每筆已驗證交易(首購/背景續訂/恢復)都把 JWS 轉送 POST `/api/billing/verify`,伺服器寫 `user_entitlements` 並回 tier;iOS 的 `isPro` 只驅動 paywall UI,配額判斷一律讀 `AtlasStore.entitlement`。
- 單例常駐監聽 `Transaction.updates`(背景續訂、退款、Ask-to-Buy);驗證後同步伺服器並 `finish()`。
- `restore()` = `AppStore.sync()` + 重新枚舉 currentEntitlements 全部上報。
- 同步成功後刷新 atlas entitlement,配額 UI 立即更新。

### Paywall — `Features/Paywall/PaywallView.swift`

- 入口:Me 頁 Pro 卡、設定、拍照流程的滿格橫幅與 AI 402、Free 點高精度。
- 權益文案:格數 300 / AI 每月 500 / 高精度每月 30 / 優先支援。
- 處理「載入成功但商品是空陣列」的情況(loadingProducts 旗標 + 重新載入鈕),不會無限轉圈。
- 購買成功或恢復後為 Pro 即自動 dismiss。

---

## 13. 設定

檔案:`Features/Settings/SettingsView.swift`, `Core/Settings/SettingsStore.swift`

### 即時套用模型

- 沒有儲存鈕:控制項直接改 `SettingsStore.current`(`update(_:)` / `binding(_:)`),記憶體立即生效,**400ms debounce** 合併連續修改成一次 POST `/api/users/settings`。
- `uiLang` 變更:靜態 UI 隨 environment locale 即時切換;分類名與單字中文是伺服器端本地化,所以再 reload categories + words(不 invalidate — 資料集相同,只是繁簡差異,舊字留在畫面直到新資料到,不閃空白)。
- `uiLang` 同時鏡射到 UserDefaults(`tuji.ui.lang`)供 nonisolated 的 `tujiLocalized()` 讀取 — 這是把 zh-Hant 原文 key 查到使用者所選語言的 helper(直接找對應 .lproj bundle;`String(localized:locale:)` 的 locale 參數不會切換字表)。

### 設定項目

| 區塊 | 項目 | 邏輯 |
|---|---|---|
| 學習 | 學習語言 | 切換 zh-en / zh-ja:invalidate + reload words/categories/progress/mastery/stats;兩種語言進度分開保留;訪客只寫本機 |
| 學習 | 每日目標題數 | 影響新字額度(§6.1) |
| 學習 | 學習主題 | 影響學新字出題範圍與主題進度統計 |
| 學習 | 中文釋義 | showZh 開關,各列表/學習畫面條件渲染中文 |
| 顯示 | 語言 | 繁體/简体(uiLang) |
| 顯示 | 發音口音 | 美式/英式(僅 zh-en 顯示) |
| 帳號 | 編輯個人資料 | nickname/avatar → POST `/api/users/profile`,`AuthService.applyProfile` 樂觀更新 session |
| 帳號 | 登出 | 確認 prompt → `auth.signOut()` |
| 危險 | 清除學習進度 | 二段確認,見 §7.3 |
| 危險 | 刪除帳號 | **兩層確認** prompt → DELETE `/api/users/delete-account` → 自動登出 |

### 啟動時的學習方向 seed

`SettingsStore.init` 從 UserDefaults 讀持久化的 learningDirection 先填 `current`,讓 splash 後面的字典預載抓對語言(否則 zh-ja 使用者每次冷啟都會先抓英文字);伺服器 `load()` 回來若方向不同,會全面 invalidate + reload。

---

## 14. 基礎設施

### HTTP — `Core/Networking/APIClient.swift`, `Endpoint.swift`, `APIError.swift`

- 型別化 client:所有 endpoint 集中在 `Endpoint` enum(路徑、query、cache policy、timeout、是否公開)。
- 受保護請求自動帶 `AuthService.validAccessToken()` 的 Bearer;**401 重試一次**(supabase-swift 讀 session 時已順帶 refresh)。公開端點(words/word/categories/search/events)跳過 auth。
- Base URL 從 Info.plist `TUJI_BASE_URL` 讀,缺失 fallback 到 prod。
- URLSession 帶磁碟 URLCache(16MB/128MB):公開 GET 依伺服器 Cache-Control/ETag 快取、重啟仍有效;使用者/寫入端點一律 `reloadIgnoringLocalCacheData`。
- Timeout:一般 15 秒;AI 端點(上傳辨識/enrich/detail)60 秒。
- `upload()` 手工組 multipart;`fireAndForget()` 給 analytics 用(掉了就掉)。
- JSON:`JSONCoder+Tuji` 的 decoder 做 snake_case→camelCase 與 `.iso8601`;Postgres NUMERIC 會序列化成字串的欄位用 `decodeFlexibleDouble` 容忍兩種型別。

### 圖片

- **`TujiImagePipeline`**(Nuke):100MB 記憶體 + 500MB 磁碟 DataCache(關掉 URLCache 避免重複快取);Supabase Storage 的圖有一年 max-age + ETag。
- **`ImageDownscale`**:拍照上傳前用 ImageIO thumbnail(不整張解碼)縮到 ≤1600px JPEG(後端存 1600px、辨識只看 1024px,傳原圖是浪費)。
- **`ImageCrop` / `ImageCropView`**:上傳前的手動裁切。

### 推播 — `Core/Push/PushNotificationService.swift`, `PushAppDelegate.swift`

- 授權流程保留給未來提醒設定 UI:`requestAuthorization()` → 允許則註冊 APNs → delegate 收 token → POST `/api/users/push-token`(帶穩定的 per-install deviceId)。
- 登出時 `unregister()` 刪除該裝置 token,舊帳號不再收通知。
- 通知點擊經 deep link 管線路由。

### 本地化

- 原文 key 為 zh-Hant,字表在 `Resources/i18n/Localizable.xcstrings`(uiLang 只有 zh-Hant / zh-Hans)。
- SwiftUI 內用 `LocalizedStringKey` 走 environment locale;String 型別的參數/模型層字串一律經 `tujiLocalized()`(否則不會跟隨 uiLang 切換)。

### 診斷

- `Core/Diagnostics/CrashReporting.swift`:Firebase Crashlytics(詳見 `CRASH_REPORTING.md`)。
- 全 App 用 OSLog(subsystem `app.tuji.ios`)分 category 記錄;Atlas 佇列另有 OSSignposter 打點。
- DEBUG 限定:Me 頁「除錯工具」的 Bearer smoke test(GET `/api/test_smoke/whoami`),release 編譯排除。

### 測試 — `TujiTests/`

單元測試覆蓋核心純邏輯:兩個學習 coordinator 的狀態機、SRS outbox、額度計算(Study + Atlas)、復習排程解析、搜尋排名、WordsStore 合併、AtlasCaptureVM、主頁提示文案。
