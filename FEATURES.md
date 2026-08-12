# Tuji iOS 功能邏輯總覽

更新日期：2026-08-12

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
12. [物見(公開圖鑑與合集)](#12-物見公開圖鑑與合集)
13. [我的(Me)](#13-我的me)
14. [Tuji Pro 訂閱](#14-tuji-pro-訂閱)
15. [設定](#15-設定)
16. [基礎設施](#16-基礎設施)

---

## 1. App 架構與啟動

### 進入點 — `Tuji/TujiApp.swift`

- `@main TujiApp` 在 `init()` 先安裝自訂 Nuke 圖片管線(`TujiImagePipeline.install()`),必須在任何 `LazyImage` 渲染前完成。
- 建立共享狀態並注入 SwiftUI environment,分三類:
  - **單例 store**:`AuthService`、`PushNotificationService`、`OnboardingState`、`LocalCache`、`WordsStore`、`CategoriesStore`、`SettingsStore`、`ProgressStore`、`MasteryStore`、`StudyStatsStore`、`StudyFocus`、`DeepLinkCoordinator`、`NetworkMonitor`。
  - **啟動協調器**:`LaunchCoordinator` 由 App root own,統一處理 600ms 品牌門檻、身份解析、catalog readiness、背景 profile hydration / outbox replay 與一次性 `app_open`。
  - **root 建構的公開側協調物件**(不是單例,由這裡 own):`CommunityFeedRefresh`(剛公開的內容要繞過 URLCache)、`CollectionBookmarkStore`(合集收藏狀態)、`CollectionIdentityStore`(剛換的合集頭像要跨畫面立即生效)。
- 啟動時並行開始:600ms 品牌動畫門檻、session resolution、依本機 mirror 的匿名 words/categories preload,以及非阻塞的推播授權刷新。只有 signed-in session 確立後才讀 server settings、補 personalized catalog、刷新 profile 與重播離線答題 outbox(`StudyAnswerOutbox.replay()`);App 回到前景且仍為 signed-in 時再重播一次。
- `.onOpenURL` 先交給 GoogleSignIn 處理 OAuth callback,再嘗試解析成 `TujiDeepLink`。
- environment locale 由 `settings.current.uiLanguage.locale` 決定,支援四種介面語言,見 §16 本地化。

### 架構模式

- **單例 @Observable store**(`Core/*`)持有所有共享狀態;View 透過 `@Environment` 讀取。
- **Repository 協定**(`Core/Repositories/*`)包裝 API 呼叫,便於單元測試注入。
- **Coordinator**(學習流程)是純狀態機,View 只負責渲染。
- 專案預設 MainActor isolation;需要跨 actor 的型別(Codable payload、純值 enum)標 `nonisolated`。

### 頂層狀態切換 — `Tuji/Navigation/RootView.swift`

```
App 啟動
  ├─ LaunchCoordinator 未過 600ms  → SplashView
  ├─ AuthService.checking          → SplashView
  ├─ .signedOut
  │    ├─ 未選學習方向              → LearningDirectionOnboardingView
  │    ├─ !introDone               → OnboardingFlow(3 頁行銷介紹)
  │    └─ introDone                → WelcomeView(登入/註冊/訪客)
  ├─ .guest                        → catalog 嘗試完成前 SplashView,之後 MainTabsView(user: nil)
  └─ .signedIn(user)
       ├─ 未選學習方向              → LearningDirectionOnboardingView
       ├─ !setupDone(user.id)      → SetupView(選主題 + 每日目標)
       ├─ personalized catalog 未完成 → SplashView
       └─ 全部就緒                  → MainTabsView(user:)
```

- 原生 `UILaunchScreen` 使用 `LaunchLockupPeekStart`(232×230pt)與 `tujiPaper #FBF7EF`;它是 SwiftUI `TujiBrandLockup` 探頭動畫的精確起始幀,因此系統最後一幀到 App 第一幀不跳動。SwiftUI 接手後開啟洞口並讓黑貓探頭,且最少顯示 600ms;Reduce Motion 直接顯示最終品牌鎖定並移除離場 opacity,但不跳過時間門檻。
- 登出、onboarding 與首次 setup 只等待身份和 600ms;guest / setup 已完成的 signed-in 主介面才等待對應 catalog 的最終載入嘗試。成功或失敗都解除 gate,錯誤與離線提示進入目的頁後再呈現。
- `LaunchCoordinator.start()` 可重入但整個 process 只執行一次;RootView 只渲染一個頂層 destination,不再有底層 Splash 加 overlay Splash 的雙重轉場。
- 啟動 catalog 以 immutable `CatalogContext`(介面語言、學習方向、帳號、是否 personalized)識別 single-flight。相同 context 共用請求;context 改變時舊結果可完成但不得覆寫目前畫面。

---

## 2. 導航與 Deep Link

### 四大分頁 — `Tuji/Navigation/MainTabsView.swift`, `MainTab.swift`

- 分頁:今天(today)/ 圖鑑(cards)/ **物見(community)** / 我(me)。語意軸線是 時間 → 內容 → 他人 → 自己。
- **物見** 是 UI 名字;程式碼與領域詞彙仍叫 `community` / 公開圖鑑(`"community"` 是分類 id 這個 wire value,改不動),見 CONTEXT.md。
- 自訂浮動膠囊 tab bar(非 SwiftUI TabView);每個分頁擁有獨立 `NavigationStack`,互不干擾。
- 分頁以水平 paging ScrollView 呈現,可左右滑動切換;但學習中(`StudyFocus.active`)或當前分頁已 push 詳情(path depth > 0)時停用滑動,避免與返回手勢衝突。
- **tab bar 何時消失**:學習中一律隱藏;另外 我 與 物見 兩個分頁,只要離開分頁根畫面就隱藏 —— 這兩個分頁是入口集散地,從它們開出去的畫面獨佔視窗直到使用者返回。判斷依據是**分頁根畫面自己的可見性**(`meAtRoot` / `communityAtRoot`),不是 `NavigationPath` 深度:設定頁的 picker 是 view-based link、物見的合集卡片是 `navigationDestination(item:)`(要帶 preview model,沒有 route value 能表達),兩者都不會讓 path 變深。

### 路由 — `Tuji/Navigation/NavRoute.swift`, `TujiNavRoutes.swift`

`NavRoute` enum 集中定義所有可 push 的目的地;每個 NavigationStack 掛 `tujiNavDestinations(user:)` 統一解析。

| 群組 | case |
|---|---|
| 基本 | `cards` / `today` / `search(query:)` / `favorites` / `settings` |
| 學習 | `studyCategories` / `studyLanding(mode:)` / `wordDetail(id:)` / `categoryDetail(id:)` |
| 自製圖鑑 | `atlasManage`(開在 圖鑑卡片)/ `atlasMyCollections`(開在 合集,deep link 相容用)/ `atlasCollectionEdit(id:)` |
| 物見 | `atlasPublic` / `atlasCollectionDetail(slug:autoSave:)` / `authorProfile(handle:isSelf:)` |

- `authorProfile` 的 `isSelf` 只多加一個編輯入口,其餘完全相同 —— 這頁的價值就在於它就是別人看到的那一頁(§12)。
- `atlasCollectionDetail` 的 `autoSave` 只用來續接訪客被登入打斷的收藏動作。

### Deep Link — `Tuji/Navigation/DeepLink.swift`, `DeepLinkCoordinator.swift`

- 同時接受 `tuji://…` scheme 與 `https://tuji.app/…` universal link,解析成 `(tab, route)`。
- 支援:`today`、`cards`、`favorites`、`settings`、`search?q=`、`word/{id}`、`category/{id}`、`study?mode=new|review`、`collection/{slug}`(落在 物見 分頁)。
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
- **Apple**:`AppleSignInBridge` 取得 idToken + nonce → Supabase `signInWithIdToken`。Apple 提供的姓名不會自動成為公開暱稱；暱稱只能在登入後由使用者於「編輯個人資料」主動送出並通過審核。
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

### 身分模型 — UID / 暱稱 / 簽名 / 頭像

註冊完成即建立一份公開身分,四個欄位權責分明(`Core/Models/UserMe.swift`):

| 欄位 | 誰決定 | 可改 | 公開 |
|---|---|---|---|
| **UID**(`username`) | 系統指派,格式 `TJ` + 8 位數字 | **否** | 是,作者主頁的路由 handle |
| **暱稱**(`nickname`) | 使用者自己打 | 是 | 是,需過內容審核 |
| **簽名**(`bio`) | 使用者自己打 | 是 | 是,需過內容審核 |
| **頭像**(`avatar`) | 使用者上傳照片,或預設黑貓 | 是 | 是 |

- **顯示名 = 暱稱;沒有暱稱就是 UID。** UID 一律另外可見,**email 永遠不會成為 fallback**。
- **Apple 提供的姓名不會被寫進任何欄位。** 早期 `username` 預設為 email local part、`nickname` 被 Apple 全名靜默 seed,所以曾經有一道「公開作者身分」同意閘門。UID 改為機器指派且不可改之後,App 不再持有使用者沒有主動輸入的名字,同意閘門與改名冷卻都已退役(2026-07-30)。
- 修改走單一畫面 設定 → 編輯個人資料(§15),一次 multipart POST。UID 有兩個家:`profiles`(權威)與 session 的 `user_metadata`(鏡像);編輯後以伺服器回傳的權威身分為準,再鏡射回 session。

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
- 儲存成功後:`settingsStore.adoptPersisted()` 立即生效 → Setup 保持在原畫面等待該語言／方向的 catalog 最終載入嘗試 → `markSetupDone` → **直接落回主頁**。中途不會第二次顯示 Splash,主頁再交給功能導覽帶路;CTA 因此叫「完成設定」,不承諾一場它不會開的 session。
  - 這裡曾經塞一個 `.study(mode: .new)` deep link 直接推進學新字,結果是**首次登入永遠看不到功能導覽** —— `startTourIfNeeded()` 只要 `StudyFocus` 被 `StudyLauncherView` 持有就直接 bail。導覽本來就是新使用者最需要的那一次,所以讓路給它。

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
- **求救提示**:點 hero 翻面只顯示中文釋義,不顯示 reading / pronunciation。提示在本次呈現中是 sticky(翻回去也算用過),並把可選 rating 限制成答錯表 `[重來,困難]`;正確與否仍決定 suggestion 和是否 requeue。寫入時帶 `hinted: true`,後端保存到 `study_logs.metadata`。
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
- **`DurableAnswerWriter`**(`Core/Study/DurableAnswerWriter.swift`):唯一的「短暫重試後停放到 outbox」政策;raw `LiveStudyRepository` 只做一次會 throw 的 network call,重播 outbox 時不會再把同一筆重新停放。
- **`StudySessionWrites`**(`Core/Study/StudySessionWrites.swift`):兩個 coordinator 共用的 session 寫入追蹤,合併 mastery/milestone、計 parked 數,並提供 `drainPendingWrites`。完成頁把 in-flight 寫入與 timeout 賽跑;沒趕上的寫入照常在背景完成。
- **`SessionRefresh`**(`Core/Study/SessionRefresh.swift`):完成時統一執行 drain → invalidate queue/stores → reload,避免最後一題寫入輸給完成頁刷新。

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

### 7.3 我的進度區塊 — `Tuji/Features/Me/MeProgressSections.swift`

- 進度不再是主分頁,完整搬到「我」:圖鑑完成度(所選主題 seen/total 百分比)、目前/最長連勝、最近 6 週熱力圖(0 / 1–4 / 5–12 / >12 四檔深淺)、每分類明細(依所選主題過濾,空選=全部)。
- 訪客顯示登入提示空狀態。
- **清除學習進度**放在 設定 → 帳號(不在進度頁,破壞性操作不該離統計一步之遙):DELETE `/api/users/progress` 後同時 `cache.clearLearned()`(sync 是 union-only,不清本機會在下次登入把已清除的 id 復活)+ invalidate/reload progress 與 stats。收藏、設定、自製圖鑑不受影響。

---

## 8. 圖鑑與單字瀏覽

### 資料來源

- **`WordsStore`**(`Core/Words/WordsStore.swift`):依 `CatalogContext` single-flight 載入 GET `/api/words`(帶 uiLang + learningDirection);登入後 custom / saved 與 public 並行,但固定按 public → custom → saved 做 id last-wins 合併,最後按 分類→字母 排序。相同語言與方向的匿名 preload 可由 personalized context 重用 public source。全 App 共讀目前 context 的記憶體字典。
  1. `/api/users/custom-words` — 自己拍的自製字,id 為 `atlas:<uuid>`,內嵌完整 detail。
  2. `/api/users/saved-words` — 從物見收藏來的字(§12)。
  兩者都是 best-effort:任一支失敗只記 log,公開字典照常呈現。
- **`CategoriesStore`**:依 context single-flight 載入 GET `/api/categories`(本地化分類名);相同介面語言可跨 anonymous / personalized context 重用來源,舊 context 晚到時不發布。

### 圖鑑列表 — `Features/Cards/CardsListView.swift`

2 欄格 + 分類 chip 過濾 + 分頁載入(每頁 60);頂部相機鈕開自製圖鑑拍照流程,`AtlasCaptureQueueTiles` 在格頭顯示生成中的卡。點格開 WordPeek(輕量預覽),從 peek 再進完整詳情。

分類 chip 只列出實際有字的分類,但 `custom`(自製圖鑑)與 `community`(物見)兩個主題**恆常顯示** —— 它們是使用者自己創作與收藏的去處,即使目前是空的,格子也要看得到自己收藏了什麼。

### 分類頁 — `Features/Category/CategoryView.swift`

插畫 hero(中英名 + 說明)+ 該分類全部單字的 2 欄格。

### 單字詳情 — `Features/Word/WordDetailView.swift`

- 進入後是**水平分頁 TabView**:可左右滑到圖鑑順序的前後字,不用退回格子。
- 每頁按需抓 GET `/api/words/{id}` 完整資料;各區塊(定義/例句/搭配詞/詞形/字源)有資料才渲染。
- 全螢幕模式:進入時 `StudyFocus.enter()` 隱藏 tab bar。
- **「大家的圖鑑」**(`WordCommunityAtlasSection`):同一個字別人拍的公開照片,GET `/api/atlas/public/by-lemma`。公開內容注入使用者本來就會來的頁面,而不是另開一個沒人逛的 feed。**沒有內容(或還在載入)時完全不渲染** —— 一個沒有公開照片的字,長得必須跟這個區塊不存在時一模一樣:沒有空狀態、沒有 placeholder、沒有版面位移。

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

> 「收藏」在 App 裡有兩個意思,不要混淆:**本章**是把字典裡的字加進「我的收藏」(純本機事實來源);**§12** 的收藏是把別人公開的圖鑑項目或合集收進自己的學習內容(伺服器事實來源,會影響 `WordsStore` 與學習佇列)。

- **來源**:`LocalCache.favoriteIds`(UserDefaults)是唯一事實來源;訪客純本機,登入者由 `FavoriteButton` 樂觀更新本機後 fire-and-forget POST `/api/users/favorites`,登入時再由 sync 統一 union。
- **圖鑑的收藏來源**:`CardsSource.bookmarks` 以 `favoriteIds × WordsStore` 直接渲染,不打 GET;`CardsListView` 與所有字共用分頁、排序、WordPeek 與列操作。`tuji://favorites` 保留舊連結語意,但現在是切到圖鑑的收藏 filter,不再 push 獨立 Favorites 畫面。

### LocalCache — `Core/Cache/LocalCache.swift`

- 持有:favorites、learned(**按語言分開** `tuji.cache.learned.en/.ja`,舊單一 key 自動遷移進 en)、recentSearches、匿名 sessionId。
- `mergeFromServer` / `syncSnapshot` 皆 union 語義;`clearLearned` 只在清除學習進度時呼叫。

---

## 11. 自製圖鑑(Atlas 拍照新增)

### 流程總覽

```
拍照/選相簿 → 裁切 → 編碼(≤1600px / 0.78 JPEG)   ← 全在 ImageIntake
  → 上傳 /api/atlas/images(辨識在同一請求內完成,candidates 隨上傳回來)
  → 校正表單(候選 chip / 手動修改 lemma + 中文)
  → [可選] AI 識別(primary)/ 高精度(escalate, Pro 限定) 重跑
  → 確認並生成卡片 → 交給生成佇列:confirm → createCards → enrich → 對帳
```

### 取像 — `Components/ImageIntake.swift`

拍照新增與兩個頭像畫面共用同一條「把照片弄進來」的流程(來源 → 相機/相簿 → 350ms 轉場空拍 → 裁切 → 編碼 → 遞交 → 停放重試),差別只有編碼設定、用哪個裁切器、以及「遞交」是什麼。拍照新增用 `.freeform`(四角把手、任意比例 —— 要框的是待辨識的主體,壓成正方形會把它切掉),並自己畫來源面板(`pick(_:)` 而非 `begin()`),因為剩餘額度與滿格警告都在那塊面板上。詳見 CONTEXT.md。

### View Model — `Features/Atlas/AtlasCaptureVM.swift`

- 擁有管線狀態;「放棄重來」= 直接換一顆新 VM。取像與停放重試不在這裡(見上)。
- **每個辨識 mode 最多跑一次**,結果快取(`candidatesByMode`),再點同 mode 免費重顯示(重跑幾乎不變、只燒額度);失敗/空結果不算 final,可重試。舊快取缺 UI 語言 gloss 時**每個 mode 只修一次**,修不出來就不再花錢。
- 候選自動套用規則:排 rank 後優先取 fine 級;`apply(overwrite:)` — 使用者點 chip 才覆蓋欄位,自動套用只填空欄(不覆蓋手動輸入)。
- 402(額度用盡)→ 開 Paywall 而非顯示錯誤;429 留在訊息列(暫時性的,送去 Paywall 是謊)。
- 放棄時 best-effort 刪除已上傳影像(未確認的照片不留在帳號)。
- 校正表單的第二個欄位問哪一題,由 `CaptureCorrectionFields` 一張表回答(見 CONTEXT.md)。

### 額度 — `Core/Atlas/AtlasQuotas.swift`, `AtlasCapacityReadout`

- 鏡像伺服器 `lib/atlas/entitlement.ts`;**entitlement 未知時一律放行**(伺服器才是權威,UI 保持寬鬆)。
- 規則:自製圖鑑格數上限(Free 少 / Pro 300)、普通 AI 每月軟上限(Free 30 / Pro 500)、高精度 Pro 限定(Free 上限 0,Free 點高精度直接進 Paywall,不浪費一次必 402 的呼叫)。
- **格數要連生成佇列裡的一起算**:伺服器快照數的是已 confirm 的 item,數不到還在生成的那幾張。只讀快照的閘門在「剩一格」時會放兩張進來,第二張到 confirm 才 402。佇列佔住的格子說「正在生成」,不說「刪除一些」—— 這時候該做的是等。

### 生成佇列 — `Core/Atlas/AtlasCaptureQueue.swift`

- 確認後的重尾(confirm → createCards → enrich → 一次對帳)在 @MainActor 單例佇列跑,sheet 立即關閉;圖鑑格頭顯示「生成中」占位格(`AtlasCaptureQueueTiles`)。
- **弱網韌性**:job 經 `CaptureJobJournal` 持久化到 Application Support;App 被殺後啟動時恢復續跑。confirm 是**非冪等** INSERT — 成功後 checkpoint `itemId`,恢復時跳過 confirm 只重跑(冪等的)createCards 之後。有 checkpoint 的 job 從 50% 續跑,不從頭重報。
- enrich(定義/同義詞/詞形/字源)best-effort,失敗不影響卡片(詳情頁開啟時會 lazy enrich)。
- 完成後 `reload()`(絕不 `invalidate()` — 那會清 `loaded` 把整個 App 彈回 Splash)刷新 WordsStore(新卡要出現在圖鑑格)+ ProgressStore + StudyStatsStore,並以 OSSignposter 打點各階段耗時。
- **失敗分兩種**(`CaptureFailure`):`.transient` 留占位格供手動 retry(從 checkpoint 續跑);`.atCapacity`(402)不給 retry —— 再按一次也只會一樣失敗,出路是刪卡或升級。
- 依賴全部從 init 進來(`AtlasCardGenerating` / `CaptureJobJournal` / `AtlasMutationRefreshing`),測試用 `enqueue` 回傳的 Task 或 `settle()` 等它跑完。

### 資料同步 — `Core/Atlas/AtlasStore.swift`

`/api/atlas/sync` 增量同步(since = 上次 serverTime),merge 進 images/items/cards/cardStates/mastery,過濾已刪除;每次 sync 後刷新 entitlement。MeView 掛載時就 warm 這個 store。

### 管理頁 — `Features/Atlas/AtlasManageView.swift`

「圖鑑管理」是一個分頁式入口,一個 segmented picker 切兩個 pane:

- **圖鑑卡片** — 列表式查 + 刪(建立只在拍照流程;編輯待後端 PATCH)。
- **合集** — 見 §12 的作者端。第二個 pane 直到第一次被切到才掛載。

卡片 pane 的所有決策集中在 **`AtlasShelfModel`**(`AtlasShelfModel.swift`):image→item 的 join、學習方向過濾、`hiddenCount`、選取集合、批次刪除、取消公開。View 只負責渲染。

- **`AtlasShelfState` 五態**:`loading` / `loaded` / `failed` / `hiddenElsewhere(count:)` / `empty`。`failed` 與 `empty` 刻意分開 —— 同步失敗卻宣稱「還沒有卡片」,對一個確實擁有卡片的人來說讀起來就是資料遺失。`hiddenElsewhere` 是「這個學習方向沒有,但另一個方向有 N 張」。
- **切換學習方向時會重新對帳選取集合**,否則會留下已經不在畫面上的選取列。
- 每列的標題:有確認後的 lemma 就用它,否則用 pipeline 狀態推導的佔位標題 —— 標題永遠不會和旁邊的狀態自相矛盾。
- 刪 image 級聯刪 item + cards。注意 `TujiPrompt` 會先把 backing state 設 nil 再跑 action,所以待刪目標要先抓 local copy。

### 兩種狀態,不要混為一談

- **Pipeline status**(`AtlasImageStatus`):卡片生成走到哪 — uploaded / processing / needs_review / confirmed / cards_ready / failed / deleted。
- **Review status**(`AtlasReviewStatus`,§12):公開審核閘門走到哪。

`confirmed` 與 `cards_ready` 蘊含「已存在一個確認過的 item」;處於這兩態卻 join 不到 item 的列是**同步落差**,不是未完成的拍照 —— 兩者一旦混淆,「未完成」就會出現在「已完成」旁邊。

第三種曾經也存在:生成佇列自己的 `Stage`。同一張照片在圖鑑格是「生成中」、在圖鑑管理是「已上傳」,而且沒有任何規則把兩者對起來。現在只有一份 **`CaptureProgress`**,兩個畫面都讀它,**在跑的 job 蓋過伺服器那一列**(還在跑的 job 知道的事,那一列還沒寫下來)。`AtlasShelfRow.inFlight` 是兩者交會的地方。

### 變更後刷新什麼 — `Core/Atlas/AtlasMutationRefresh.swift`

生產端只說使用者做了什麼(`AtlasMutation`:itemsDeleted / captureCompleted / itemWithdrawn / collectionPublished / collectionWithdrawn / collectionDeleted / collectionAvatarChanged),由這個模組決定後果:`changesOwnAtlas` → reload words + progress + stats 再 `refreshEntitlement`;`invalidatesPublicFeed` → 標記 `CommunityFeedRefresh`。刷新策略只有這一個家。

### 學習整合

自製字進統一學習流程(`/api/users/custom-words` → WordsStore,queue 內按 word.id 去重);mastery 在伺服器端獨立 namespace(`user_atlas_item_mastery`),由 `/api/users/mastery` 合併以 `atlas:<itemId>` 回傳。從物見收藏來的字走同一條路(`/api/users/saved-words`,§12)。

一個 item 會產出兩張卡(image_recall + flashcard),而佇列是按卡抓的,所以自製字會重複出現 —— `StudyQueueStore` 以 `word.id` 去重(§6.2)。

---

## 12. 物見(公開圖鑑與合集)

物見是自製圖鑑的公開面:§11 是你自己拍的東西,這一章是它怎麼變成大家的東西,以及你怎麼消費別人的。程式碼在 `Features/Atlas/`(公開半邊)與 `Core/Models/AtlasCommunity.swift`(wire model)。

### 12.1 領域詞彙

- **公開圖鑑(public atlas)** — 通過審核閘門、所有人都看得到的 item。含**無**私人資料。
- **合集(collection)** — 作者自己已確認 item 的**具名策展集合**,綁定單一學習語言。這是公開的單位:**沒有單項送審動作**,公開一個合集就是把它的私有成員整批送審。
- **作者主頁(author profile)** — 每個註冊帳號都有的公開頁:身分 + 已公開作品 + 累計被收藏數。
- **收藏(saving)** — 消費路徑。**收藏公開項目不吃自製圖鑑的格數額度**(§11 的 quota 只算自己拍的)。

### 12.2 瀏覽 — `AtlasPublicFeedView`

物見分頁的根畫面。GET `/api/atlas/public/collections?lang=`(公開、吃 CDN 快取)。

- **依當前學習語言自動過濾**:學日文只看日文合集。這頁**沒有手動語言切換**,是產品決定。
- **兩個書架**(`PublicAtlasBrowsingModel.Shelf`):`explore`(探索)與 `saved`(已收藏)。兩者的語言化載入狀態機、refresh policy、未登入邊界、收藏狀態對帳全部在 `PublicAtlasBrowsingModel` 裡;這個 model 刻意不認得 `SettingsStore` / `AuthService` / `CommunityFeedRefresh` / `CollectionBookmarkStore`,由 View 把環境值翻譯成明確輸入。
- 剛公開的內容會透過 `CommunityFeedRefresh` 標記,讓下一次進 feed 繞過 URLCache,不然使用者會看不到自己剛送出去的東西。

### 12.3 合集詳情 — `AtlasCollectionDetailView` / `CollectionDetailVM`

`CollectionDetailVM.open(context:)` 一個 workflow 收掉:抓詳情 → 判斷是否本人 → 讀收藏狀態 → 必要時 auto-save。從 feed 卡片帶 preview model 進來,標題區先畫出來,成員在後面載。

- **未收藏前成員不可點**(`vm.unlocked`)。收藏這個合集之後才開放逐項閱讀,以及「**全部加入學習**」批次動作(`CollectionLearning.learnCollection` → POST `/api/atlas/collections/{slug}/learn`)。
- 確認過的收藏變更回傳一個單純的 `BookmarkChange` 讓 View 廣播出去,**不重抓整份詳情**。

### 12.4 單項消費 — `AtlasPublicDetailView` / `AtlasPublicDetailVM`

- **收藏 / 取消收藏** — POST/DELETE `/api/atlas/public/{slug}/save`,回傳最新收藏數。有 in-flight guard;**失敗不翻轉開關**(取消收藏失敗了,開關就得留在「已收藏」)。
- 成功後跑 `CommunityLearningRefreshing`:invalidate `StudyQueueStore` 再 best-effort `WordsStore.reload()`,讓佇列與圖鑑立刻反映這次變更。**收藏本身的成功與否,從不取決於刷新是否成功。**
- **檢舉** — 共用 `ReportFlow` 選五種原因:垃圾內容 / 不當內容 / 侵犯版權 / 內容有誤 / 其他。只有 POST 成功後才進 `.sent`;401/429/網路失敗不會顯示成「已收到」。
- 分析事件留在 View(VM 不碰 `AnalyticsService`):`atlas_public_item_viewed`、`atlas_public_saved`、`author_profile_viewed`。

### 12.5 作者主頁 — `AtlasAuthorProfileView` / `AuthorProfileVM`

GET `/api/atlas/public/authors/{handle}`(公開、吃 CDN 快取)。同一個畫面服務兩種讀者,`isSelf` 只多一個直接開編輯的入口 —— 看到問題能當場改,迴圈是閉的。

- **註冊完成就存在**,不需要先發表任何東西,也沒有另外的「開通」或同意狀態。零公開作品時顯示合成的頁首 + 一條出路。
- **可用 UID 或既有連結到達,但不進作者搜尋、推薦或公開目錄。**
- 內容分兩段(有東西才顯示切換):已通過審核的**合集**與單獨的**公開項目**。`collections` 這個 key 在 1.0.4 之後才加,所以是 defaulted 解碼 —— 作者主頁不能因為前後端部署順序而整頁解不開。
- 累計被收藏數(`saveCount`)是這頁的利他訊號:別人因為你的整理受益了幾次。

### 12.6 作者端:我的合集 — `AtlasMyCollectionsView` / `MyCollectionsVM` / `CollectionEditVM`

入口在 圖鑑管理 → 合集(§11)。

- 列表存在 **app-lifetime 的 `MyCollectionsCache`**,不是畫面自己的 `@State` —— 圖鑑管理是一個會離開再回來的地方,而 `@State` VM 在 pop 時會被 SwiftUI 丟掉,每次回來都從空列表 + spinner 重新回答幾秒前才答過的問題。登出時與 `AtlasStore.reset()` 一起清,下一個帳號不會繼承。
- **reload 時「已載入者勝」**:畫面上已經有列時,重新載入不得把它換成 spinner;從 編輯合集 回來時同一幀觸發的兩次刷新(list 的 `.task` 重啟 + 編輯頁的 `onDisappear`)會合併成一次請求。
- **編輯合集**(`CollectionEditVM`):載入 → 校正標題/簡介 → 換公開頭像 → 挑選成員 → 送審。`submit()` 的順序是有意義的 —— **先存 meta,再打 publish**,因為公開閘門讀的是存下來的那一列。
- **成員資格**:可加入已通過、審核中、私有的自己的項目;**不能**加入已否決、已下架、未完成、已刪除的項目。
- **頭像**:合集的方形頭像照片是公開的,與早期由成員推導的封面/背景圖無關(新畫面不再渲染後者)。推導出的安全色只當頭像的載入中與舊資料 fallback。剛上傳的頭像透過 `CollectionIdentityStore` 立刻在列表、已收藏書架、作者主頁、詳情四處生效。

### 12.7 檢舉與封鎖 — `ReportFlow` / `BlockStore`

- **三種檢舉目標**:`ReportTarget.item(slug:)` / `.collection(slug:)` / `.author(handle:)`,由 `ReportSubmitting` 選正確 endpoint。公開項目、合集詳情與作者主頁共用一個 reason sheet 與成功/失敗狀態機。
- **不能檢舉或封鎖自己**:`NavRoute.authorProfile(handle:isSelf:)` 的 `isSelf` 沒有 default,所有入口都必須明確回答;合集/作者畫面依 owner 判斷隱藏治理動作。
- **封鎖語意是停止 discovery**:`BlockStore` 的帳號清單在 App 啟動後載入,對物見 feed、合集/作者入口與單字頁「大家的圖鑑」做 client filter。已收藏的字和 SRS 屬於封鎖者自己的學習歷史,不會被刪除。
- **公開 API 仍可共享快取**:四條 public discovery API 不做 per-user server filter;一份小而低頻變更的封鎖清單換回 CDN/URLCache。清單載入失敗 fail-open(不隱藏),避免網路抖動把物見變空。
- 封鎖採 optimistic hide,server 失敗回滾;設定 → 已封鎖的作者 可解除。登出時由 account-scoped reset 清除,避免下一帳號繼承。

### 12.8 審核閘門 — `AtlasReviewStatus`

送審會跑一道機器閘門,結果是三選一:直接公開、轉人工、或退回。

| 狀態 | 文案 | 可再送審 | 可收回 |
|---|---|---|---|
| `draft` | 未公開 | ✅ | — |
| `pending` / `pending_auto` / `pending_review` | 審核中 | — | — |
| `approved` | 已公開 | — | ✅ |
| `rejected` | 未通過 | ✅ | — |
| `takedown` | 已下架 | ❌ | — |
| `withdrawn` | 已收回 | ✅ | — |

- **`withdrawn` 可以再送審,`takedown` 不行。** 收回是作者自己的決定,可逆、不帶懲罰;下架是審核端移除的,收回不能拿來規避它。
- 文案一律說「送審 / 審核中」,絕不暗示「已經公開了」—— 通過不是自動的。
- `pending` 是舊的單一佇列,留給早期資料列。

### 12.9 端點對照

| 用途 | 端點 |
|---|---|
| 公開合集牆 / 單一合集 | GET `/api/atlas/public/collections`、`/api/atlas/public/collections/{slug}` |
| 公開項目 | GET `/api/atlas/public`、`/api/atlas/public/{slug}`、`/api/atlas/public/by-lemma` |
| 作者主頁 | GET `/api/atlas/public/authors/{handle}` |
| 消費動作 | POST/DELETE `…/{slug}/save`、POST `…/{slug}/learn` |
| 檢舉 | POST 公開項目 `…/{slug}/report`、合集 `…/collections/{slug}/report`、作者 `…/authors/{handle}/report` |
| 作者端合集 | `/api/atlas/collections`(CRUD)、`…/{id}/avatar`、`…/{id}/items`、`…/{id}/publish`、`…/{id}/withdraw`、`…/candidates` |
| 已收藏的字 | GET `/api/users/saved-words`(併入 `WordsStore`,§8) |
| 封鎖 | GET/POST `/api/users/blocks`、DELETE `/api/users/blocks/{handle}` |

完整定義見 `Core/Networking/Endpoint.swift`。

---

## 13. 我的(Me)

檔案:`Features/Me/MeView.swift`, `MeProgressSections.swift`

**我的 是私人中樞,作者主頁 是公開作品集**,兩者刻意分開:這頁只有你看得到,§12.5 那頁是別人看到的。

- **頁首**:頭像 + 顯示名(暱稱 → UID)+ UID。
- **三格統計**:連勝 / 已學字數 / 自製圖鑑數。連勝與已學字讀共用的 `ProgressStore`,主頁、進度、我的 共用同一份抓取結果。
- **完整進度**:`MeProgressSections` 呈現圖鑑完成度、目前/最長連勝、6 週 heatmap 與主題明細;原 Progress 主分頁已移除。
- **最弱三個字**:GET `/api/users/top-words?type=weak&limit=3`,點進 WordPeek。這是 我的 專屬的 payload,所以留在 `MeVM`。
- **兩張選單卡**,分組本身就是重點:
  - **創作** — 圖鑑管理(§11)、我的主頁(§12.5,帶 `isSelf`)。你做的東西,和它流向的公開頁。
  - **帳號** — 我的收藏(§10)、設定(§15)、意見收集、分享 App。
  - 拆開之前這八列擠在同一張卡裡,連同 Pro 與分享,讀起來像雜物抽屜而不是一個家。
- **Pro 卡**:是否為 Pro 只問 `EffectiveEntitlementReading`:已有 server snapshot 時(包含 free)server 雙向勝出,只有首次 sync 前才以裝置 StoreKit 交易暫時 fallback。這同時涵蓋管理員贈與、跨裝置購買與訂閱重新綁定。
- 掛載時 warm `AtlasStore`(§11 的 sync)。
- **DEBUG 限定**:底部「除錯工具」可展開,內含 Bearer smoke test(GET `/api/test_smoke/whoami`),release 編譯排除。

---

## 14. Tuji Pro 訂閱

### StoreKit 2 — `Core/Billing/StoreKitService.swift`

- 產品:`app.tuji.pro.monthly` / `app.tuji.pro.yearly`(自動續訂)。
- **伺服器是有效權限權威**:每筆已驗證交易(首購/背景續訂/恢復)都把 JWS 轉送 POST `/api/billing/verify`;伺服器把 App Store 訂閱與營運手動贈與分開保存,再取聯集回 `AtlasEntitlement.plan`。贈與不覆寫訂閱,收回贈與也不取消訂閱。
- **一份訂閱只綁一個帳號**:`original_transaction_id` 唯一;同一 Apple 訂閱同步到另一 Tuji 帳號時會轉移綁定,所以已有 server snapshot 時連 `free` 都必須勝過裝置 `isPro`。
- 單例常駐監聽 `Transaction.updates`(背景續訂、退款、Ask-to-Buy);驗證後同步伺服器並 `finish()`。
- `restore()` = `AppStore.sync()` + 重新枚舉 currentEntitlements 全部上報。
- 同步成功後刷新 atlas entitlement,配額 UI 立即更新。
- 使用者畫面一律讀 `EffectiveEntitlementReading`;`StoreKitService.isPro` 只服務首次 snapshot 前的 fallback 與 paywall 自己的購買/restore 狀態。

### Paywall — `Features/Paywall/PaywallView.swift`

- 入口:我的 分頁的 Pro 卡(§13)、設定、拍照流程的滿格橫幅與 AI 402、Free 點高精度。
- 權益文案:格數 300 / AI 每月 500 / 高精度每月 30 / 優先支援。
- 處理「載入成功但商品是空陣列」的情況(loadingProducts 旗標 + 重新載入鈕),不會無限轉圈。
- 購買成功或恢復後為 Pro 即自動 dismiss。

---

## 15. 設定

檔案:`Features/Settings/SettingsView.swift`, `Core/Settings/SettingsStore.swift`

### 即時套用模型

- 沒有儲存鈕:控制項直接改 `SettingsStore.current`(`update(_:)` / `binding(_:)`),記憶體立即生效,**400ms debounce** 合併連續修改成一次 POST `/api/users/settings`。
- `uiLang` 變更:靜態 UI 隨 environment locale 即時切換;分類名與單字釋義是伺服器端本地化,所以再 reload categories + words(不 invalidate — 資料集相同,只是釋義語言不同,舊字留在畫面直到新資料到,不閃空白)。
- `uiLang` 同時鏡射到 UserDefaults(`tuji.ui.lang`)供 nonisolated 的 `tujiLocalized()` 讀取 — 這是把 zh-Hant 原文 key 查到使用者所選語言的 helper(直接找對應 .lproj bundle;`String(localized:locale:)` 的 locale 參數不會切換字表)。

### 設定項目

| 區塊 | 項目 | 邏輯 |
|---|---|---|
| 學習 | 學習語言 | 切換 zh-en / zh-ja:invalidate + reload words/categories/progress/mastery/stats;兩種語言進度分開保留;訪客只寫本機 |
| 學習 | 每日目標題數 | 影響新字額度(§6.1) |
| 學習 | 學習主題 | 影響學新字出題範圍與主題進度統計 |
| 學習 | 中文釋義 | showZh 開關,各列表/學習畫面條件渲染中文 |
| 顯示 | 語言 | 介面語言四選一(§16 本地化) |
| 顯示 | 發音口音 | 美式/英式(僅 zh-en 顯示) |
| 方案 | Tuji Pro / 目前方案 | 有效權限為 Free 才顯示升級;Pro 顯示目前方案,不以裝置交易 flag 判斷 |
| 帳號 | 編輯個人資料 | 見下方 |
| 帳號 | 已封鎖的作者 | 讀 `BlockStore`,可解除並讓物見 discovery 重新出現 |
| 帳號 | 登出 | 確認 prompt → `auth.signOut()` |
| 危險 | 清除學習進度 | 二段確認,見 §7.3 |
| 危險 | 刪除帳號 | **兩層確認** prompt → DELETE `/api/users/delete-account` → 自動登出 |

### 編輯個人資料 — `Features/Settings/EditProfileView.swift`

**擁有整份公開身分的唯一畫面**(§3)。暱稱 / 簽名 / 裁切後頭像照片以**單一 multipart POST** `/api/users/profile` 一次送出;伺服器回傳的權威 `AtlasAuthor` 直接更新作者主頁快取,再鏡射回 session。

- 一次編輯就是一次 Author 身分變更:被否決時保留原本的完整身分,而不是露出改到一半的狀態。
- UID 在這裡顯示但不可編輯,而且讀的是**伺服器真值** —— session 鏡像會落後,而這裡正是使用者來確認自己 UID 到底是什麼的地方。
- `dirty` 比對的是畫面打開時伺服器的內容,不是可能過期的 session 副本。
- 頭像走共用的 `ImageIntake` 流程(來源對話框 → 相簿/相機 → 裁切 → 編碼 → 遞交 → 重試,§11 拍照新增是第三個 adapter),個人資料用 1200px / 0.86 圓形遮罩(合集用 1600px / 0.82 方形)。

### 意見收集 — `Features/Me/FeedbackSheet.swift`

我的 → 意見收集:選類型(`FeedbackType`:功能建議 / 錯誤回報 / 內容問題 / 其他)+ 描述 → POST `/api/users/feedback`,附 requestId、平台、App 版本、uiLang。raw value 是 API 契約,必須與後端白名單和 `feedback_type` CHECK 一致。

### 啟動時的學習方向 seed

`SettingsStore.init` 從 UserDefaults 讀持久化的 learningDirection 先填 `current`,讓 splash 後面的字典預載抓對語言(否則 zh-ja 使用者每次冷啟都會先抓英文字);伺服器 `load()` 回來若方向不同,會全面 invalidate + reload。

---

## 16. 基礎設施

### HTTP — `Core/Networking/APIClient.swift`, `Endpoint.swift`, `EndpointPolicy.swift`, `APIError.swift`

- 型別化 client:所有 endpoint 集中在 `Endpoint` enum(一個 case 對應一組 path/query);access、cache policy、timeout 由 `EndpointPolicy` 明確決定,不用 broad default 讓新 case 偷繼承錯政策。
- 受保護請求透過 `AccessTokenProviding` 取 Bearer;**401 重試一次**(supabase-swift 讀 session 時已順帶 refresh)。JSON 與 multipart 都重建完整 request,照片上傳重試不會丟 body。
- Base URL 從 Info.plist `TUJI_BASE_URL` 讀,缺失 fallback 到 prod。
- URLSession 帶磁碟 URLCache(16MB/128MB):公開 GET 依伺服器 Cache-Control/ETag 快取、重啟仍有效;使用者/寫入端點一律 `reloadIgnoringLocalCacheData`。
- Timeout:一般 15 秒;AI 端點(上傳辨識/enrich/detail)60 秒。
- `upload()` 手工組 multipart;`fireAndForget()` 給 analytics 用(掉了就掉)。
- JSON:`JSONCoder+Tuji` 的 decoder 做 snake_case→camelCase 與 `.iso8601`;Postgres NUMERIC 會序列化成字串的欄位用 `decodeFlexibleDouble` 容忍兩種型別。

### 圖片

- **`TujiImagePipeline`**(Nuke):100MB 記憶體 + 500MB 磁碟 DataCache(關掉 URLCache 避免重複快取);Supabase Storage 的圖有一年 max-age + ETag。
- **簽名 URL 的快取鍵**:自製圖鑑存在**私有** Supabase bucket,所以 API 每次回應都重新簽一個 URL — 同一個物件、每次不同的 `token=`。Nuke 兩層快取都以 URL 為鍵,結果是重進圖鑑管理等於一整面沒人看過的圖、每張縮圖重抓,500MB DataCache 對使用者自己的照片**永遠 miss**。簽章授權取用,但它不識別這張圖,所以 pipeline 改成以「簽章以外的一切」建鍵(`URL.signedStorageObjectID`);query 裡其他參數(例如轉檔尺寸)仍然決定你拿到哪張圖,所以保留。非簽名 URL 走 Nuke 預設鍵不受影響。
- **`ImageDownscale`**:拍照上傳前用 ImageIO thumbnail(不整張解碼)縮到 ≤1600px JPEG(後端存 1600px、辨識只看 1024px,傳原圖是浪費)。
- **`ImageCrop` / `ImageCropView`**:上傳前的手動裁切。

### 推播 — `Core/Push/PushNotificationService.swift`, `PushAppDelegate.swift`

- 授權流程保留給未來提醒設定 UI:`requestAuthorization()` → 允許則註冊 APNs → delegate 收 token → POST `/api/users/push-token`(帶穩定的 per-install deviceId)。
- 登出時 `unregister()` 刪除該裝置 token,舊帳號不再收通知。
- 通知點擊經 deep link 管線路由。

### 本地化

- **四種介面語言**(`Core/Settings/UILanguage.swift`,宣告順序 = picker 顯示順序):`zh-Hant` 繁體中文 / `zh-Hans` 简体中文 / `ja` 日本語 / `en` English。raw value 就是與 tuji-web 共用的 wire code,值域由 `UILanguageTests` 釘住;**新增語言是前後端協同的變更**(伺服器會把不認得的 code 夾回 zh-Hant)。
- **首次啟動的預設值**由 `UILanguage.deviceDefault` 從裝置偏好語言清單挑第一個支援的;無明確 script 的 `zh` 依地區判定(CN/SG 用簡體,其餘與裸 `zh` 用繁體)。
- 介面語言與**學習方向**正交:不論介面是哪一種,學習內容的釋義都跟著介面語言走(`contentLanguageCode` 直接就是 wire code,由伺服器決定 ja/en 定義、zh-Hant 基準或 OpenCC 轉簡)。
- 原文 key 為 zh-Hant,字表在 `Resources/i18n/Localizable.xcstrings`。
- SwiftUI 內用 `LocalizedStringKey` 走 environment locale;String 型別的參數/模型層字串一律經 `tujiLocalized()`(否則不會跟隨 uiLang 切換)。它讀 UserDefaults 的 `tuji.ui.lang` 鏡像,直接查對應的 `.lproj` bundle。

### 診斷

- `Core/Diagnostics/CrashReporting.swift`:Firebase Crashlytics(詳見 `CRASH_REPORTING.md`)。
- 全 App 用 OSLog(subsystem `app.tuji.ios`)分 category 記錄;Atlas 佇列另有 OSSignposter 打點。
- DEBUG 限定:我的 分頁「除錯工具」的 Bearer smoke test(GET `/api/test_smoke/whoami`),release 編譯排除。

### 測試 — `TujiTests/`

單元測試覆蓋純邏輯與畫面 model(目前 71 個 `*Tests.swift` 檔),不碰正式網路 —— 每個 model 都能站在自己的 role seam fake 上:

| 範圍 | 代表測試 |
|---|---|
| 學習流程 | `NewFlowCoordinatorTests`、`ReviewFlowCoordinatorTests`、`StudyOptionStateTests`、`StudyLadderTests`、`TileBoardTests` |
| SRS 寫入與刷新 | `DurableAnswerWriterTests`、`StudyAnswerOutboxTests`、`SessionRefreshTests` |
| 額度與排程 | `StudyQuotasTests`、`AtlasQuotasTests`、`ReviewScheduleTests` |
| 自製圖鑑 | `AtlasCaptureVMTests`、`AtlasStoreTests`、`AtlasShelfModelTests`、`AtlasImageStatusTests`、`AtlasMutationRefreshTests`、`ImageCropTests` |
| 物見 | `PublicAtlasBrowsingModelTests`、`CollectionDetailVMTests`、`CollectionEditVMTests`、`MyCollectionsVMTests`、`AtlasPublicDetailVMTests`、`AuthorProfileVMTests`、`AtlasReviewStatusTests`、`CommunityLearningRefreshTests`、`SavedCommunityWordsTests`、`BlockStoreTests`、`ReportFlowTests` |
| 身分與設定 | `AuthSessionTests`、`AccountScopedStoreTests`、`EffectiveEntitlementTests`、`AuthorProfileModuleTests`、`SessionUserMirrorTests`、`ImageIntakeTests`、`UILanguageTests` |
| 其他 | `SearchVMTests`、`WordsStoreMergeTests`、`TodayDecisionsTests`、`EndpointPolicyTests`、`NavigationSafetyNetTests`、`AnalyticsTests`、`SignedStorageObjectIDTests`、`FeedbackTests` |

`AtlasTestSupport.swift` 提供共用 fake。`AnalyticsTests` 會把 `AnalyticsEvent` 的值域釘住,新增事件必須同步更新白名單。
