<!--
分支命名提醒：
  feat/<area>-<short>     新功能
  fix/<area>-<short>      修 bug
  refactor/<area>-<short> 不改外部行為的重寫
  chore/<short>           升 deps / 雜事
  docs/<short>            純文件
  hotfix/v<x.y.z>-<short> 從 main 開的緊急修

Commit 訊息走 Conventional Commits：
  feat(study): NewFlow Step 1 寫 SRS
  fix(auth): Apple Sign-in 第一次拿不到 email 時不能 crash
-->

## 改了什麼

<!-- 一句話描述。例：「Study NewFlow Step 1 接 /api/study/answer，Step 2/3 留純練習」-->

## 為什麼

<!-- 連結設計書章節 / Issue / 後端 PR；沒有相關就寫 N/A -->

- Design: `iOS_DESIGN_BOOK.md` §___
- Architecture: `ARCHITECTURE.md` §___
- Backend PR: tuji#___
- Issue: LIN-___

## 影響範圍

勾選有改到的（沒勾的留空、不要刪）：

- [ ] 新增 / 改變 API 呼叫
- [ ] 改變 `LocalCache` schema（要寫 migration）
- [ ] 改變 `Theme` tokens（顏色 / 字 / 間距 / 圓角）
- [ ] 改變 `Endpoint` enum
- [ ] 需要 server 配套（後端 PR 必須先合）
- [ ] 改 `Info.plist` / `entitlements` / Privacy Manifest
- [ ] 改 `Version.xcconfig`（marketing version / build number）
- [ ] 加 / 改 i18n key
- [ ] 加 / 改埋點事件

## Self-review checklist

### 紀律（每次都檢查）

- [ ] **SRS**：NewFlow Step 2/3 沒打 `/api/study/answer`
- [ ] **熱路徑**：沒在 query 內重複 `getUser()`、`userId` 由呼叫端傳入
- [ ] **Auth**：所有 user-scoped API 都帶 `Authorization: Bearer`
- [ ] **i18n**：UI 字串沒寫死中文 / 英文，全部走 `Localizable.xcstrings`
- [ ] **Theme**：顏色用 `.tujiTeal` 而非 `Color(hex: 0x006F72)`；字型用 `.tujiH1` 而非 `Font.custom(...)`
- [ ] **API**：URL 沒寫死，全走 `Endpoint` enum
- [ ] **Secrets**：access / refresh token 沒進 log；沒 commit `.xcconfig` 機密
- [ ] **Concurrency**：`@MainActor` / async / Task cancel 處理乾淨

### 看狀況

- [ ] 新 API → 後端 PR 已合 main 且 prod deploy
- [ ] 改 LocalCache schema → 寫了 migration、舊用戶不會 crash
- [ ] 新依賴（SPM package）→ 更新 Privacy Manifest、檢查授權條款
- [ ] 新 ViewModel → 畫面消失時取消 inflight Task
- [ ] 新動畫 → 在 SE 第 3 代 / iPhone 15 Pro Max 都跑過
- [ ] 改 BBtn / Mascot / WordPeek 這類共用元件 → 全站視覺檢查

## 螢幕錄影 / 截圖

<!-- UI 改動必附，其他類型可省 -->
<!-- 建議：iPhone 15 Pro 模擬器（6.1"）+ iPhone SE（4.7"）各一張，深淺底各一 -->

| 改之前 | 改之後 |
|---|---|
|  |  |

## 測試

- [ ] Unit tests 跑過：`xcodebuild test -scheme Tuji-Debug`
- [ ] 真機 / 模擬器手動測過（golden path + 邊界）
- [ ] 離線情境檢查（如適用）
- [ ] 訪客模式檢查（如適用）

## Rollout 注意

<!-- 上 TestFlight / App Store 時需要特別注意的事，沒有就刪 -->
<!-- 例：「需要 Supabase 上 enable Apple Provider 才會 work」-->

---

<!--
PR 大小指引：
  ≤ 400 行 diff、≤ 8 個檔案 = 順暢
  > 400 行  = 拆 PR
  > 1000 行 = 一定要拆，不然 review 不出 bug

完成後在 PR 頁面用 Squash merge 合到 main，
branch 合完自動刪。
-->
