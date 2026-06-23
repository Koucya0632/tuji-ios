# Tuji iOS Crash Reporting

Tuji 僅使用 Firebase Crashlytics 做 iOS crash reporting。此決策最後核對於
**2026-06-22**：Crashlytics 在 Firebase 價格頁標示為 no-cost，Spark 方案不需要
付款方式。

## 固定邊界

- Firebase 專案使用 **Spark**，不綁 billing account。
- 只加入 `FirebaseCore` 與 `FirebaseCrashlytics`。
- 不啟用 Google Analytics、Performance Monitoring、Remote Config、BigQuery、
  Cloud Logging export、Gemini、App Distribution SDK 或其他 Firebase 產品。
- 不使用 Sentry。
- Debug (`TUJI_DEV`) 不呼叫 `FirebaseApp.configure()`，不建立 Firebase
  installation，也不上報。
- TestFlight (`TUJI_BETA`) 與 Release 自動收集 fatal crash；只有明確選定的
  non-fatal 類別可經 `CrashReporting.record` 上報。
- 不設定 Crashlytics user ID，不傳 Supabase UUID、Email、姓名、搜尋字串、單字、
  答題內容、API URL／response 或 access token。

## Firebase Console 一次性設定

1. 建立獨立 Firebase project，方案選 Spark，建立時不要啟用 Google Analytics。
2. 新增 Apple app，Bundle ID 必須是 `app.tuji.ios`。
3. 在 Build → Crashlytics 啟用 Crashlytics；不要啟用其他產品或資料匯出。
4. 下載 production `GoogleService-Info.plist`。
5. 確認 plist 的 `BUNDLE_ID` 是 `app.tuji.ios`、Analytics 相關值為關閉，再放到：

   ```text
   Tuji/GoogleService-Info.plist
   ```

6. 提交該檔。Firebase Apple client configuration 不是服務端密鑰；repo 已只對這個
   固定路徑解除 `.gitignore`。不要把 Admin SDK key、service account JSON 或其他
   server credential 放入 repo。

在取得正式檔以前，可參考 `Config/GoogleService-Info.plist.example`，但不可將範本
複製成 production 檔或拿它 archive。TestFlight／Release build phase 會在缺少正式
plist 時中止。

## SDK 與程式結構

- SPM repository：`https://github.com/firebase/firebase-ios-sdk.git`
- 最低版本：`12.15.0`（2026-06-22 最新可解析 release tag），限制在 `12.x`。
- 唯一 Firebase 呼叫邊界：`Tuji/Core/Diagnostics/CrashReporting.swift`。
- `PushAppDelegate` 在 app launch 最早期呼叫 `CrashReporting.configure()`。
- Debug 的 `configure()` 是空操作；TestFlight／Release 才初始化 Firebase。
- 可上報的 custom keys 僅有：
  - `build_channel`
  - `app_version`
  - `build_number`
  - `flow`
  - `step`
- `Flow`、`Step`、`Category` 都是固定 enum。不要增加接收任意字串的 API。
- `record(error:category:)` 會丟棄原始 error message 與 `userInfo`，只送固定 domain、
  code 與 category，避免個資或伺服器內容外洩。
- 預期中的網路失敗、取消操作、表單驗證與授權拒絕只記 `OSLog`，不送 non-fatal。

若新增 enum case，PR 必須回答：

1. 它是否真的代表可行動的 app defect？
2. 值是否完全由程式定義、沒有使用者或伺服器文字？
3. 是否能以 `OSLog` 完成診斷而不用上報？

## dSYM 與 CI

Xcode target 最後一個 Build Phase 是 `Upload Crashlytics dSYMs`：

- Debug 直接跳過。
- TestFlight／Release 先確認 built app 含 `GoogleService-Info.plist`。
- release workflow 會在編譯前驗證 plist 存在、Bundle ID 正確且 Analytics 關閉。
- 使用 Firebase SPM checkout 中的 `Crashlytics/run`。
- Run Script Sandboxing 所需的 dSYM、Info.plist、Firebase plist、app executable 與
  Crashlytics `run` tool 已列為 Input Files。
- script 失敗會讓 archive 失敗，避免發布無法 symbolicate 的 build。
- GitHub Actions 仍保存 `build/*.dSYM.zip`，供事故時人工補傳。

人工補傳方式（路徑依 DerivedData／archive 調整）：

```bash
path/to/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols \
  -gsp Tuji/GoogleService-Info.plist \
  -p ios path/to/Tuji.app.dSYM
```

補傳後在 Firebase Console 確認 Missing dSYM 警告消失，且 stack trace 能顯示 Tuji 的
Swift function 與行號。

## 接入驗證

測試 crash 入口只會編進 `TUJI_BETA`：

- `-CrashlyticsTestNonFatal`：啟動後送一筆匿名 integration test non-fatal。
- `-CrashlyticsTestCrash`：Firebase 初始化後執行 `fatalError`。

驗證步驟：

1. 使用 `Tuji-TestFlight` scheme build 並安裝到測試裝置／Simulator。
2. 先以 `-CrashlyticsTestNonFatal` 啟動，確認 App 可正常使用。
3. 以 `-CrashlyticsTestCrash` 啟動；觸發時必須斷開 Xcode debugger。
4. 再次正常啟動 App，讓前一次 crash report 上傳。
5. 在 Firebase Console 確認：
   - channel 是 `testflight`，版本與 build number 正確；
   - stack trace 已 symbolicate；
   - event 沒有 user ID、Email、姓名或學習內容；
   - non-fatal 只有固定的 `integration_test` category。
6. 移除 launch argument。正式 Release 不包含這兩個入口。
7. 再以 `Tuji-Debug` 操作一次；Firebase Console 不應出現 Debug session 或事件。

## App Store 隱私揭露

`Tuji/PrivacyInfo.xcprivacy` 宣告：

- Diagnostics → Crash Data
- Linked to User：No
- Used for Tracking：No
- Purpose：App Functionality

每次送審前同步檢查 App Store Connect 的 App Privacy 回答。Firebase SDK 自帶 privacy
manifest 不能取代開發者對實際使用方式的揭露責任。

## 發版後處理

- 每個 TestFlight／App Store build 上線後，確認版本出現在 Crashlytics dashboard，
  且沒有 Missing dSYM。
- Firebase email／console alert 只用內建免費能力，不建立付費 export 或自訂 GCP
  notification pipeline。
- 分級：
  - P0：啟動失敗、資料損壞、安全問題；停止 rollout，立即 hotfix。
  - P1：核心登入／學習流程高頻 crash；當日定位並準備修復。
  - P2：低頻、可繞過；排入下一 patch。
- 修復 PR 連結 Firebase issue、記錄受影響版本與驗證方式；不要在 issue title 或
  custom key 加入使用者資料。

## 官方資料

- [Firebase pricing](https://firebase.google.com/pricing)
- [Crashlytics Apple SDK setup](https://firebase.google.com/docs/crashlytics/ios/get-started)
- [Crashlytics test implementation](https://firebase.google.com/docs/crashlytics/ios/test-implementation)
- [Readable crash reports and dSYMs](https://firebase.google.com/docs/crashlytics/ios/get-deobfuscated-reports)
- [Firebase Apple data collection](https://firebase.google.com/docs/ios/app-store-data-collection)
