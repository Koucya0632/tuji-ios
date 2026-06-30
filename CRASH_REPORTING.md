# Tuji iOS Crash Reporting

更新日期：2026-07-01

## 1. 當前策略

Tuji iOS 使用 Firebase Crashlytics 做 crash reporting。目標是發現崩潰，不做行為分析產品。

允許：

- FirebaseCore
- FirebaseCrashlytics
- TestFlight/Release fatal crash
- 少量 non-fatal error，且不含個資或內容資料

不允許：

- Google Analytics
- Performance Monitoring
- Remote Config
- BigQuery export
- 使用者 ID、email、token、搜尋字串、答題內容、圖片 URL
- 在 Debug build 自動上報

## 2. 代碼邊界

代表檔案：

- `Tuji/Core/Diagnostics/CrashReporting.swift`
- `Tuji/GoogleService-Info.plist`
- `Tuji/PrivacyInfo.xcprivacy`

Crash reporting 呼叫必須集中，不要在 View 裡到處直接碰 Firebase。

## 3. 隱私

Crashlytics 對 App Store privacy 的影響：

- Crash Data：未連結到使用者。
- Other Diagnostic Data：未連結到使用者。
- Tracking：false。

如果未來啟用 Analytics 或把 user id 傳給 Crashlytics，必須重新改 privacy manifest 和 App Store 隱私問卷。

## 4. 初始化規則

- Debug：不初始化或不送出。
- TestFlight：允許收 fatal crash。
- Release：允許收 fatal crash。
- non-fatal：只記錄可診斷的技術錯誤，不帶 payload。

## 5. 上架前檢查

- [ ] `GoogleService-Info.plist` Bundle ID 正確。
- [ ] 沒有 service account / Admin SDK key 被提交。
- [ ] Release log 不輸出 token/email。
- [ ] Privacy manifest 與 Firebase 實際使用一致。
- [ ] App Store Connect 隱私問卷與本文件一致。
