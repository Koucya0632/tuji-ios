# Tuji iOS Release

更新日期：2026-08-04

App 已於 2026-07-16 上架。以下是**已上架後**的發版規則，不是首次送審的清單。

## 1. Release 原則

iOS 是 Tuji 的主要產品面。發版前必須先保證：

- App 可 build/archive。
- Auth、Study、Catalog、Settings、Account deletion 可用。
- Atlas（自製圖鑑）失敗狀態可恢復。
- 社群（公開圖鑑／合集／作者主頁）的檢舉與下架路徑可用 —— 這是 UGC App Review 的必查項。
- Privacy Manifest 與實際 SDK/權限一致。
- metadata 不宣稱尚未完成的能力。目前仍未完成的是：
  - **Push**：程式碼存在，但 entitlement 沒有 `aps-environment`（`Tuji.entitlements` 只有 Sign in with Apple）。未完成前不要打開正式推播能力。
  - **Universal Links**：尚未完成 Associated Domains / AASA，目前只有 custom scheme `tuji://`。
- Pro 訂閱已上線（`app.tuji.pro.monthly` / `app.tuji.pro.yearly`），送審必附 restore purchases 與訂閱條款。

## 2. Schemes

| Scheme | 用途 |
|---|---|
| `Tuji-Debug` | 本機開發與 Simulator build |
| `Tuji-TestFlight` | TestFlight |
| `Tuji-Release` | App Store archive |

## 3. 支援版本

- 最低支援：iOS 18.0（`IPHONEOS_DEPLOYMENT_TARGET`）。
- 已驗證可正常 build/啟動、無 crash：iOS 18.0（最低）與 iOS 26.5（目前最新）。
- 程式碼目前沒有 `@available`/版本分支，單一 build 即涵蓋整個支援範圍，不需分版本另外編譯。

## 4. Build

```bash
xcodebuild -project Tuji.xcodeproj \
  -scheme Tuji-Debug \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  build
```

Archive 前用 Release/TestFlight scheme 再跑一次。

## 5. 配置

核對：

- `TUJI_BASE_URL`
- `TUJI_SUPABASE_URL`
- `TUJI_SUPABASE_ANON_KEY`
- `TUJI_GOOGLE_CLIENT_ID`
- `TUJI_GOOGLE_REVERSED_CLIENT_ID`
- Bundle ID
- App display name
- Version/build number

不要提交 private key、service role key、App Store Connect API private key。

## 6. Capability

目前可確認：

- Sign in with Apple entitlement 已存在。
- Camera usage description 已存在。
- **沒有** `NSPhotoLibraryUsageDescription`，也不需要：相簿選圖走 SwiftUI `PhotosPicker`（out-of-process，不取得相簿存取權）。若哪天改用 `PHPhotoLibrary` 直接讀取，這條就要補。
- Custom scheme `tuji://` 已存在。

仍未完成，見 §1：Push entitlement、Universal Links。

## 7. 手工測試

發 TestFlight 前至少跑：

**基本**

- 冷啟動/重啟 session。
- Email/Apple/Google 登入。
- 登出。
- 刪除帳號。

**學習與內容**

- Today -> Study -> Complete（新字與復習兩條）。
- Cards -> Word detail -> Favorite。
- Search。
- Progress。
- Settings（含切換介面語言四種、切換學習方向）。
- Atlas golden path：拍照 -> 校正 -> 生成卡片 -> 出現在圖鑑格。

**身分與社群**（UGC，App Review 會看）

- 編輯個人資料：改暱稱／簽名／頭像，確認作者主頁同步。
- 我的 -> 我的主頁：零公開作品時也要開得起來。
- 圖鑑管理 -> 合集：建立 -> 加成員 -> 換頭像 -> 送審 -> 收回。
- 社群 -> 瀏覽合集 -> 收藏 -> 全部加入學習 -> 確認字進了圖鑑與學習佇列。
- 公開項目 -> 檢舉，確認送出成功。

詳見 umbrella repo 的 `../docs/ios/MANUAL_TEST.md`。

## 8. App Store Review Notes

需要準備：

- 測試帳號（要有已公開的合集，否則審核者看不到社群內容）。
- **UGC 審核說明**（現在是必備，不是「如果有」）：
  - 檢舉入口：社群 -> 公開項目詳情 -> 檢舉，五種理由 + 說明。
  - 下架與收回：作者可自行「取消公開」；審核端下架後作者無法再送審。
  - 審核閘門：送審不等於公開，文案一律說「送審／審核中」。
- **AI 功能說明**：拍照辨識後有校正表單，使用者可修改 lemma 與釋義後才生成卡片。
- **刪除帳號**：設定 -> 危險區 -> 刪除帳號（兩層確認）。
- **訂閱**：restore purchases 入口在 Paywall，並附訂閱條款連結。
