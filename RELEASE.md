# Tuji iOS Release

更新日期：2026-07-01

## 1. Release 原則

iOS 是 Tuji 的主要產品面。發版前必須先保證：

- App 可 build/archive。
- Auth、Study、Catalog、Settings、Account deletion 可用。
- Atlas 若對使用者開放，失敗狀態可恢復。
- Privacy Manifest 與實際 SDK/權限一致。
- 沒有宣稱尚未完成的 Push/Universal Links/Pro 訂閱。

## 2. Schemes

| Scheme | 用途 |
|---|---|
| `Tuji-Debug` | 本機開發與 Simulator build |
| `Tuji-TestFlight` | TestFlight |
| `Tuji-Release` | App Store archive |

## 3. Build

```bash
xcodebuild -project Tuji.xcodeproj \
  -scheme Tuji-Debug \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  build
```

Archive 前用 Release/TestFlight scheme 再跑一次。

## 4. 配置

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

## 5. Capability

目前可確認：

- Sign in with Apple entitlement 已存在。
- Camera usage description 已存在。
- Custom scheme `tuji://` 已存在。

需要注意：

- Push service 代碼存在，但 entitlement 目前未見 `aps-environment`。未完成前不要打開正式推播能力。
- Universal Links 尚未完成 Associated Domains/AASA。metadata 不要宣稱完整支援。

## 6. 手工測試

發 TestFlight 前至少跑：

- 冷啟動/重啟 session。
- Email/Apple/Google 登入。
- 登出。
- 刪除帳號。
- Today -> Study -> Complete。
- Cards -> Word detail -> Favorite。
- Search。
- Progress。
- Settings。
- Atlas golden path（若入口開放）。

詳見 `docs/ios/MANUAL_TEST.md`。

## 7. App Store Review Notes

需要準備：

- 測試帳號。
- 如果有 Atlas/UGC 公開能力，說明檢舉/下架方式。
- 如果有 AI 功能，說明使用者可確認/校正結果。
- 如果有刪除帳號，說明 Settings 入口。
- 如果有訂閱，提供 restore purchases 與訂閱條款。
