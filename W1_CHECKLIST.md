# Tuji iOS 當前工作清單

更新日期：2026-07-01  
用途：取代早期 W1 啟動清單，保留目前真正有用的開發順序。

## 1. 已完成的基線

- SwiftUI 原生 App。
- MainTabs：Today、Cards、Study、Progress、Me。
- Supabase Auth + Apple/Google/email。
- `APIClient` + typed `Endpoint`。
- `Core/Repositories` 已承接主要後端依賴。
- URLCache、LocalCache、Nuke image cache。
- Study New/Review flow。
- Progress/Mastery/StudyStats stores。
- Atlas UI/API 基本骨架。
- Privacy manifest。
- Camera permission。
- Crashlytics 基礎。

## 2. 近期最高優先級

| 優先級 | 項目 | 原因 |
|---|---|---|
| P0 | Release build/archive 驗證 | 上 TestFlight 前必做 |
| P0 | 帳號刪除端到端確認 | App Review 必查 |
| P0 | Push capability 決策 | 有代碼但 entitlement 不完整 |
| P0 | Universal Links 文案降級 | 目前只有 custom scheme |
| P1 | Repository DI/test double | 降低後續大改風險 |
| P1 | 啟動 bundle endpoint | 降低後端集中依賴 |
| P1 | Atlas quota/idempotency | 控成本與防重複生成 |
| P2 | StoreKit Pro | 商業化 |
| P2 | 更完整 offline queue | 弱網體驗 |

## 3. 開發規則

- 新 View 不直接打 `APIClient`。
- 新 endpoint 先進 Repository。
- 使用者資料 response 不做 public cache。
- AI/Atlas 失敗要保留使用者已做的操作。
- Release 入口不暴露 debug/smoke/admin。

## 4. 驗證

```bash
xcodebuild -project Tuji.xcodeproj \
  -scheme Tuji-Debug \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  build
```

手工測試參考 umbrella repo 的 `docs/ios/MANUAL_TEST.md`。
