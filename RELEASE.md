# Tuji iOS — Release / TestFlight 流水線

簽章走 **fastlane match**：憑證 + provisioning profile 加密存在另一個私有 git
repo，CI 只 read-only 拉。tag `v*` → GitHub Actions `release.yml` 自動 archive +
上 TestFlight。

```
push tag v1.0.0-beta.N
        │
        ▼
release.yml (macos-15)
  ├─ ruby/setup-ruby + bundle install      (Gemfile：fastlane)
  ├─ 還原 Config/Secrets.xcconfig           (SECRETS_XCCONFIG_B64)
  ├─ bump Version.xcconfig                  (build = run number)
  └─ fastlane beta
       ├─ setup_ci                          (臨時 keychain)
       ├─ match appstore --readonly         (從 certs repo 拉憑證)
       ├─ build_app (gym)                   (Tuji-TestFlight / app-store)
       └─ upload_to_testflight (pilot)      (App Store Connect API key)
```

---

## 一次性設定（只做一次）

### 1. 建憑證 repo
在 GitHub 開一個**私有** repo，例如 `tuji-ios-certs`（空的即可）。記下 HTTPS URL。

### 2. App Store Connect API Key
App Store Connect → Users and Access → Integrations → Keys → **+**
- Access：**App Manager**
- 下載 `.p8`（**只能下載一次**），記下 **Key ID**（10 碼）與 **Issuer ID**（UUID）

base64 起來給 CI：
```bash
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy   # → secret APP_STORE_CONNECT_API_KEY_P8
```

### 3. 建 App 紀錄
App Store Connect → Apps → **+** → New App
- Platform：iOS、Bundle ID：`app.tuji.ios`、SKU 自取
- （TestFlight 上傳前一定要先有這筆紀錄）

### 4. 本機產出憑證並推上 certs repo（read-write，**只此一次**）
```bash
cd tuji-ios
bundle install

export MATCH_GIT_URL="https://github.com/<you>/tuji-ios-certs.git"
export MATCH_PASSWORD="<自取一組強密碼，記起來>"
export TUJI_DEV_TEAM="TH28V27744"
export APP_STORE_CONNECT_KEY_ID="<Key ID>"
export APP_STORE_CONNECT_ISSUER_ID="<Issuer ID>"
export APP_STORE_CONNECT_API_KEY_P8="$(base64 -i AuthKey_XXXXXXXXXX.p8)"

bundle exec fastlane bootstrap_certificates
```
這會替 `app.tuji.ios` + `app.tuji.ios.beta` 各產生 Distribution 憑證 +
`match AppStore …` profile，加密 push 到 certs repo。

### 5. 設 GitHub Secrets（repo `tuji-ios` → Settings → Secrets and variables → Actions）

| Secret | 值 / 怎麼拿 |
|---|---|
| `SECRETS_XCCONFIG_B64` | `base64 -i Config/Secrets.xcconfig`（含真實 Team ID） |
| `TUJI_DEV_TEAM` | `TH28V27744` |
| `APP_STORE_CONNECT_KEY_ID` | 步驟 2 的 Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | 步驟 2 的 Issuer ID |
| `APP_STORE_CONNECT_API_KEY_P8` | 步驟 2 base64 過的 .p8 |
| `MATCH_GIT_URL` | certs repo HTTPS URL |
| `MATCH_PASSWORD` | 步驟 4 設的密碼 |
| `MATCH_GIT_BASIC_AUTHORIZATION` | `printf 'USER:PAT' \| base64`（PAT 需 certs repo 的 `repo` 讀取權） |

> `MATCH_GIT_BASIC_AUTHORIZATION` 讓 CI 能 HTTPS clone 私有 certs repo。
> PAT 用 fine-grained、只授權那一個 certs repo 的 Contents: Read。

---

## 出一個 TestFlight build

```bash
git checkout main && git pull
git tag -a v1.0.0-beta.1 -m "First TestFlight build"
git push origin v1.0.0-beta.1
```
→ `release.yml` 跑完，App Store Connect → TestFlight 會出現 build（processing 幾分鐘）。

- **build number** = GitHub run number（單調遞增，不會撞號）。
- **marketing version** 取自 tag（`v1.0.0-beta.1` → `1.0.0`）。
- tag 規則：`v1.0.0-beta.N` → TestFlight（`Tuji-TestFlight`）；無 `-beta`/`-rc` 後綴的 `v1.0.0` → `Tuji-Release`（App Store channel，仍走同一上傳，正式送審在 App Store Connect 手動點）。

### 本機手動出 build（不發 tag，debug 用）
```bash
export MATCH_GIT_URL=... MATCH_PASSWORD=... TUJI_DEV_TEAM=... \
       APP_STORE_CONNECT_KEY_ID=... APP_STORE_CONNECT_ISSUER_ID=... \
       APP_STORE_CONNECT_API_KEY_P8="$(base64 -i AuthKey_*.p8)"
bundle exec fastlane beta
```

---

## 換憑證 / 加新裝置時
憑證過期或要重簽：本機重跑 `bundle exec fastlane bootstrap_certificates`
（read-write）即可刷新 certs repo；CI 下次自動拉到新的。

## 常見坑
- **`MATCH_PASSWORD` 不對** → match 解不開憑證，CI 報 decrypt 失敗。
- **沒先建 App 紀錄**（步驟 3）→ pilot 上傳 404。
- **改了 Bundle ID** → 要重跑 bootstrap 產新 profile，並更新 `fastlane/Matchfile`、`Fastfile` 的 `APP_IDENTIFIERS`。
- **`SECRETS_XCCONFIG_B64` 還是舊的 stub Team ID** → 簽章 team 對不上；更新成含 `TH28V27744` 的版本。
