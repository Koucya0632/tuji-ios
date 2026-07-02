# Tuji iOS PR

## 改了什麼

-

## 類型

- [ ] Feature UI
- [ ] Networking/API contract
- [ ] Repository/Store refactor
- [ ] Auth/account
- [ ] Atlas
- [ ] Study/Progress
- [ ] Release/privacy/config
- [ ] Docs

## 架構檢查

- [ ] View 沒有新增直接 `APIClient.shared` 呼叫。
- [ ] 新 API 經過 `Endpoint` + Repository。
- [ ] 使用者資料不進共享快取。
- [ ] 錯誤狀態可恢復，不會無限 loading。
- [ ] 登入/登出/session 失效路徑已考慮。
- [ ] 若改 Atlas/UGC，已考慮檢舉、刪除、AI 失敗。

## App Store/隱私檢查

- [ ] 沒有新增未申報 SDK。
- [ ] 若改權限，已更新 `Info.plist` 文案。
- [ ] 若改 required reason API，已更新 `PrivacyInfo.xcprivacy`。
- [ ] 若改 Push，entitlement/provisioning 已核對。
- [ ] 若改付款，使用 StoreKit 並提供 restore purchases。

## 測試

- [ ] Build:

```bash
xcodebuild -project tuji-ios/Tuji.xcodeproj \
  -scheme Tuji-Debug \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  build
```

- [ ] 手工測試過 golden path。
- [ ] 弱網/失敗狀態測過。
- [ ] UI 截圖或錄影已附（UI 改動）。

## 備註

-
