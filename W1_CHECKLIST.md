# W1 起手 Checklist — Tuji iOS

> 目標：**5 天**做完。週末跑 smoke test → `dev-w1` tag → 進 W2。
> 完成標準：app 起得來、按主題 token 渲染、能用 Bearer 打到後端。

---

## 評估表

| 項目 | 預估 | 何時做 |
|---|---|---|
| 0. 前置帳號 / 服務 | 0.5d（外部 review 不在內） | D1 上午 |
| 1. 本機環境 | 1h | D1 上午 |
| 2. Apple Developer | 1h | D1 上午 |
| 3. Supabase 雙環境 | 2h | D1 下午 |
| 4. 後端 Bearer 支援 | 0.5d | D1 下午 |
| 5. Xcode 專案 init | 2h | D2 上午 |
| 6. Config / Scheme 接線 | 2h | D2 下午 |
| 7. SPM 依賴 | 1h | D2 下午 |
| 8. Asset Catalog | 1d | D3 |
| 9. Theme code | 1d | D4 |
| 10. First-build 畫面 | 0.5d | D5 上午 |
| 11. Smoke test | 0.5d | D5 上午 |
| 12. Git / CI / tag | 0.5d | D5 下午 |

---

## 0. 前置帳號 / 服務

- [ ] **Apple Developer Program**：USD $99/年。若已是會員跳過。Apple 審 1–2 天。
- [ ] **App Store Connect** 帳號可用（用 Apple ID 登入）
- [ ] **GitHub** 帳號可用，可以開私 repo
- [ ] **Supabase** 帳號可用（免費版即可）
- [ ] **Vercel** 帳號 + tuji web project 已部署到 production（既有）

---

## 1. 本機環境

```bash
# Xcode 16.2+（從 App Store 裝；認真會跑 1 小時下載）
xcode-select -p
# /Applications/Xcode.app/Contents/Developer

# Command Line Tools
xcode-select --install

# Homebrew
brew --version || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 必裝
brew install swiftlint swiftformat xcbeautify

# fastlane（簽章 / 上傳，W9 才用，但先裝起來）
brew install fastlane

# Ruby（fastlane 需要；macOS 內建版本通常夠）
ruby --version  # ≥ 3.0
```

**驗收**：

```bash
xcodebuild -version
# Xcode 16.2 Build version ...

swiftlint version
# 0.55+

swiftformat --version
# 0.55+

swift --version
# Swift 6.0+
```

---

## 2. Apple Developer

- [ ] 進 [developer.apple.com](https://developer.apple.com) → Certificates, IDs & Profiles
- [ ] **Identifiers** → 註冊 3 個 Bundle ID：
  - `app.tuji.ios.debug`（Capability：Sign in with Apple、Push Notifications）
  - `app.tuji.ios.beta`（同上）
  - `app.tuji.ios`（同上）
- [ ] 拿 **Team ID**（Membership 頁右上角，10 字）→ 填進 `Config/Secrets.xcconfig` 的 `TUJI_DEV_TEAM`
- [ ] **App Store Connect API Key**：
  - Users and Access → Integrations → Keys → "+"
  - Role：App Manager
  - 下載 `.p8`（**只能下載一次**）
  - 記下 Key ID（10 字）+ Issuer ID（UUID）
  - 留著 W9 上 TestFlight 用

> **延後做**：fastlane match（憑證管理）— W9 才需要

---

## 3. Supabase 雙環境

> 設計書要求 dev / prod 兩個 project，避免測試污染 prod 資料。

- [ ] **建 dev project**：
  - 在 Supabase Dashboard → New Project → name=`tuji-dev`
  - 區域選 `Tokyo`（latency 最低）
  - 記下 project ref + anon key
- [ ] **prod project** = 既有的 tuji web project（不動）
- [ ] **dev project 跑 migrations**：把 `tuji` repo 的 `scripts/migrate.ts` 對 dev 跑一次

  ```bash
  cd /Users/rex/Desktop/tuji
  DATABASE_URL="postgres://...dev pooler:6543..." npm run migrate
  ```

- [ ] **dev project 加 OAuth Providers**：
  - Authentication → Providers → Google → Enable
    - 用同一個 Google Cloud project 的 OAuth client（client_id / secret 共用）
    - Redirect URL：`tuji://auth/callback`（之後在 Xcode 設 URL Scheme）
  - Authentication → Providers → Apple → Enable
    - Service ID：`app.tuji.ios.signin`（在 Apple Developer 後台新建一個 Services ID）
- [ ] **prod project 同樣設一次**（用實際 Bundle ID）
- [ ] 填進 `Config/Secrets.xcconfig`：
  ```
  TUJI_SUPABASE_PROJECT_DEV = <dev-ref>
  TUJI_SUPABASE_PROJECT_PROD = <prod-ref>
  TUJI_SUPABASE_ANON_KEY_DEV = <dev-anon>
  TUJI_SUPABASE_ANON_KEY_PROD = <prod-anon>
  ```

---

## 4. 後端：加 Bearer header 支援

對應 `iOS_DESIGN_BOOK.md §I.2.4`。這是 iOS 端能打 API 的前提。

- [ ] 切回 tuji repo 的 develop branch
  ```bash
  cd /Users/rex/Desktop/tuji
  git checkout develop
  git pull
  git checkout -b feat/api-bearer-auth
  ```

- [ ] 改 `lib/current-user.ts`：

  ```ts
  import { createClient } from '@supabase/supabase-js';
  import { headers } from 'next/headers';

  const supabaseAdmin = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { autoRefreshToken: false, persistSession: false } }
  );

  export async function getCurrentUser() {
    // 1. Bearer header 路徑（mobile）
    const hdr = headers().get('authorization');
    const bearer = hdr?.replace(/^Bearer\s+/i, '');
    if (bearer) {
      const { data, error } = await supabaseAdmin.auth.getUser(bearer);
      if (data?.user && !error) return data.user;
    }
    // 2. cookie 路徑（既有 web）— 不動
    const supabase = createServerClient(...);
    const { data } = await supabase.auth.getUser();
    return data.user;
  }
  ```

- [ ] 寫一個 smoke test endpoint（之後刪）：
  ```ts
  // app/api/_test/whoami/route.ts
  export async function GET() {
    const user = await getCurrentUser();
    return Response.json({ user: user?.email ?? null });
  }
  ```

- [ ] 本機跑 `npm run dev`，用 curl 測：
  ```bash
  # 先用 Supabase Studio → SQL → 註一個測試帳號拿 access token
  TOKEN="eyJ..."
  curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/_test/whoami
  # 應該回 {"user":"test@tuji.app"}
  ```

- [ ] 開 PR → review → 合 develop → 等 Vercel preview 部署成功
- [ ] **記下 preview URL** → 填進 `Config/Debug.xcconfig` 的 `TUJI_BASE_URL`

---

## 5. Xcode 專案 init

- [ ] 開 Xcode → File → New → Project → iOS → App
  - Product Name：`Tuji`
  - Team：選自己的（會自動帶 Team ID）
  - Organization Identifier：`app.tuji`
  - Bundle Identifier：自動變 `app.tuji.Tuji`（**先不管**，等下 xcconfig 會覆蓋）
  - Interface：**SwiftUI**
  - Language：**Swift**
  - Storage：**None**（不用 Core Data / SwiftData v1）
  - Include Tests：✓
  - 存到 `/Users/rex/Desktop/tuji-ios/`

- [ ] 關掉 Xcode，把剛產生的 `Tuji.xcodeproj` 移到 `/Users/rex/Desktop/tuji-ios/` 根目錄（與已有的 .gitignore / Config / .github 同層）

- [ ] 確認結構：
  ```
  /Users/rex/Desktop/tuji-ios/
  ├── Tuji.xcodeproj
  ├── Tuji/                        ← Xcode 產生的 source 目錄
  │   ├── TujiApp.swift
  │   ├── ContentView.swift
  │   └── Assets.xcassets
  ├── TujiTests/
  ├── TujiUITests/
  ├── Config/                      ← 已有
  ├── .github/                     ← 已有
  ├── .gitignore                   ← 已有
  ├── .swiftlint.yml               ← 已有
  └── .swiftformat                 ← 已有
  ```

- [ ] 重開 Xcode，從根目錄打開 `Tuji.xcodeproj`

---

## 6. Config / Scheme 接線

### 6.1 把 xcconfig 綁進 project

- [ ] Xcode → 選 Tuji project（最上層）→ Info tab
- [ ] **Configurations**：刪掉預設的 `Debug` 和 `Release`（圖示是齒輪），新增 3 個：
  - `Debug` → file: `Config/Debug.xcconfig`
  - `TestFlight` → file: `Config/TestFlight.xcconfig`
  - `Release` → file: `Config/Release.xcconfig`

  > Xcode 介面：點 Project → Info → Configurations → "+" 複製 Debug → rename → 點 Based on Configuration File 那欄選 xcconfig

### 6.2 建 3 個 Scheme

- [ ] Xcode → Product → Scheme → Manage Schemes
- [ ] 把預設 `Tuji` 改名 `Tuji-Debug`，**勾 Shared**（CI 才能用）
- [ ] 複製 `Tuji-Debug` 一份 → 改名 `Tuji-TestFlight`
- [ ] 複製 `Tuji-Debug` 一份 → 改名 `Tuji-Release`
- [ ] 對每個 scheme，編輯：
  - `Tuji-Debug`：所有 phase（Run / Test / Profile / Analyze / Archive）→ Build Configuration = **Debug**
  - `Tuji-TestFlight`：所有 phase → **TestFlight**
  - `Tuji-Release`：所有 phase → **Release**
- [ ] **每個 scheme 都勾 Shared**

### 6.3 複製 Secrets

```bash
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
# 編輯 Config/Secrets.xcconfig 填入 §2 §3 拿到的真實值
```

### 6.4 Info.plist 套用 xcconfig 變數

- [ ] 開 `Tuji/Info.plist`（或 Project → Info → Custom iOS Target Properties）
- [ ] 加 key：

  ```xml
  <key>CFBundleDisplayName</key>
  <string>$(APP_DISPLAY_NAME)</string>

  <key>CFBundleShortVersionString</key>
  <string>$(MARKETING_VERSION)</string>

  <key>CFBundleVersion</key>
  <string>$(CURRENT_PROJECT_VERSION)</string>

  <key>TUJI_BASE_URL</key>
  <string>$(TUJI_BASE_URL)</string>

  <key>TUJI_SUPABASE_URL</key>
  <string>$(TUJI_SUPABASE_URL)</string>

  <key>TUJI_SUPABASE_ANON_KEY</key>
  <string>$(TUJI_SUPABASE_ANON_KEY_DEV)</string>   <!-- Debug 用 DEV，其他 build config 在 xcconfig 內 override -->

  <key>ITSAppUsesNonExemptEncryption</key>
  <false/>

  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
  </dict>

  <key>UIRequiredDeviceCapabilities</key>
  <array><string>arm64</string></array>

  <key>UISupportedInterfaceOrientations</key>
  <array>
    <string>UIInterfaceOrientationPortrait</string>
  </array>
  ```

- [ ] **驗收**：選 `Tuji-Debug` scheme → Product → Build → 沒紅色

### 6.5 Enable Capabilities

- [ ] Project → Signing & Capabilities → 對每個 target 加：
  - Sign in with Apple
  - Push Notifications（W7 才用，先開）
  - Background Modes → Remote notifications

---

## 7. SPM 依賴

Xcode → File → Add Package Dependencies → 依序加：

- [ ] **supabase-swift**
  ```
  https://github.com/supabase/supabase-swift
  Dependency Rule: Up to Next Major Version
  Version: 2.20.0
  ```
  Target：`Tuji`

- [ ] **GoogleSignIn-iOS**
  ```
  https://github.com/google/GoogleSignIn-iOS
  Version: 8.0.0
  ```
  Target：`Tuji`

- [ ] **Nuke**
  ```
  https://github.com/kean/Nuke
  Version: 12.8.0
  ```
  加 `Nuke` + `NukeUI` 兩個 product 到 `Tuji`

- [ ] **KeychainAccess**
  ```
  https://github.com/kishikawakatsumi/KeychainAccess
  Version: 4.2.2
  ```

> **不裝**：Lottie / Sentry / SwiftyOpenCC（v1 不需要；v1.1 再加）

**驗收**：

```bash
xcodebuild -resolvePackageDependencies -project Tuji.xcodeproj -scheme Tuji-Debug
# Resolve Package Graph 成功
```

---

## 8. Asset Catalog

### 8.1 Mascot（6 個姿勢）

- [ ] 從 `Tuji_UIUX/mascot.jsx` 看設計，或用 UIUX 設計師給的 PDF
- [ ] **暫時方案（W1 內）**：先用 placeholder
  - SF Symbols：`cat.fill` 當所有 6 個 pose 的暫代
  - 不阻塞流程，W3 再放真正的 PDF

- [ ] Asset Catalog → 新增 Image Set × 6：
  - `mascot-face` / `mascot-wave` / `mascot-think` / `mascot-cheer` / `mascot-sleep` / `mascot-peek`
  - 屬性 → Preserves Vector Data ✓
  - Render As：Original Image
  - 拖入 PDF（或暫用 PNG 1x/2x/3x）

### 8.2 Colors（與 Theme tokens 對齊）

- [ ] Asset Catalog → 新增 Color Set × 主要 token：
  - `TujiBg` (#FFFCF5)
  - `TujiTeal` (#006F72)
  - `TujiCoral` (#FF6F4D)
  - `TujiYellow` (#FFD24A)

  > 其餘走 Code 端（`TujiColor.swift`）— Asset Catalog 只放會在 Storyboard / Asset 引用的

### 8.3 AppIcon × 3 變體

- [ ] Asset Catalog → 新增 App Icon Set × 3：
  - `AppIcon` (Release 用)
  - `AppIcon-Beta` (TestFlight 用，加紅色「BETA」字樣)
  - `AppIcon-Dev` (Debug 用，加綠色「DEV」字樣)
- [ ] **暫時方案**：用 `Tuji_UIUX/assets/tuji_logo.png` 跑：

  ```bash
  # macOS 內建工具或用 ImageMagick
  brew install imagemagick
  cd /Users/rex/Desktop/tuji-ios
  # 生 1024×1024 base icon（之後讓設計重做）
  convert ../tuji/Tuji_UIUX/assets/tuji_logo.png -resize 1024x1024 -background "#FFFCF5" -gravity center -extent 1024x1024 AppIcon-1024.png
  ```

- [ ] 用 [appicon.co](https://appicon.co) 上傳 1024×1024 生全套尺寸，下載解壓進 Asset Catalog

### 8.4 字型

- [ ] 下載：
  - Plus Jakarta Sans (OFL，[Google Fonts](https://fonts.google.com/specimen/Plus+Jakarta+Sans))
  - Noto Sans TC (OFL)
  - JetBrains Mono (OFL)
- [ ] 放進 `Tuji/Resources/Fonts/`：
  ```
  PlusJakartaSans-Regular.ttf
  PlusJakartaSans-Medium.ttf
  PlusJakartaSans-SemiBold.ttf
  PlusJakartaSans-Bold.ttf
  PlusJakartaSans-ExtraBold.ttf
  NotoSansTC-Regular.otf
  NotoSansTC-Medium.otf
  NotoSansTC-Bold.otf
  JetBrainsMono-Regular.ttf
  JetBrainsMono-Medium.ttf
  ```
- [ ] Xcode 拖入專案 → 勾 Copy items if needed → Add to target `Tuji`
- [ ] `Info.plist` 加：

  ```xml
  <key>UIAppFonts</key>
  <array>
    <string>PlusJakartaSans-Regular.ttf</string>
    <string>PlusJakartaSans-Medium.ttf</string>
    <string>PlusJakartaSans-SemiBold.ttf</string>
    <string>PlusJakartaSans-Bold.ttf</string>
    <string>PlusJakartaSans-ExtraBold.ttf</string>
    <string>NotoSansTC-Regular.otf</string>
    <string>NotoSansTC-Medium.otf</string>
    <string>NotoSansTC-Bold.otf</string>
    <string>JetBrainsMono-Regular.ttf</string>
    <string>JetBrainsMono-Medium.ttf</string>
  </array>
  ```

---

## 9. Theme code

依 `iOS_DESIGN_BOOK.md §I.1` 結構建檔：

### 9.1 目錄

```bash
cd Tuji
mkdir -p Core/Theme
```

### 9.2 `Core/Theme/TujiColor.swift`

```swift
import SwiftUI

extension Color {
    static let tujiBg       = Color(hex: 0xFFFCF5)
    static let tujiBgInk    = Color(hex: 0x0F1A1A)
    static let tujiCard     = Color.white
    static let tujiInk      = Color(hex: 0x0F1A1A)
    static let tujiInk2     = Color(hex: 0x3F4F4F)
    static let tujiInk3     = Color(hex: 0x7C8C8C)
    static let tujiInk4     = Color(hex: 0xB5C2C2)
    static let tujiTeal     = Color(hex: 0x006F72)
    static let tujiTealDark = Color(hex: 0x004A4C)
    static let tujiTealSoft = Color(hex: 0xD4ECEC)
    static let tujiYellow   = Color(hex: 0xFFD24A)
    static let tujiCoral    = Color(hex: 0xFF6F4D)
    static let tujiPink     = Color(hex: 0xFFCDD2)
    static let tujiGreen    = Color(hex: 0x4FAE6F)

    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: alpha
        )
    }

    func darken(by ratio: Double) -> Color {
        // 簡化版：給 BBtn 用
        Self(hex: 0x000000).opacity(ratio).blended(over: self)
    }
}
```

### 9.3 `Core/Theme/TujiFont.swift`

```swift
import SwiftUI

extension Font {
    static let tujiDisplay = Font.custom("PlusJakartaSans-ExtraBold", size: 60)
    static let tujiH1      = Font.custom("PlusJakartaSans-Bold", size: 44)
    static let tujiH2      = Font.custom("PlusJakartaSans-Bold", size: 28)
    static let tujiH3      = Font.custom("PlusJakartaSans-Bold", size: 22)
    static let tujiH4      = Font.custom("PlusJakartaSans-SemiBold", size: 18)
    static let tujiBody    = Font.custom("PlusJakartaSans-Regular", size: 14)
    static let tujiBodyLg  = Font.custom("PlusJakartaSans-Regular", size: 16)
    static let tujiCaption = Font.custom("PlusJakartaSans-Regular", size: 12)
    static let tujiOverline = Font.custom("PlusJakartaSans-SemiBold", size: 12)
    static let tujiMono    = Font.custom("JetBrainsMono-Regular", size: 13)
}
```

### 9.4 `Core/Theme/TujiSpace.swift`

```swift
import CoreGraphics

enum Space {
    static let s0:  CGFloat = 0
    static let s1:  CGFloat = 4
    static let s2:  CGFloat = 8
    static let s3:  CGFloat = 12
    static let s4:  CGFloat = 16
    static let s5:  CGFloat = 20
    static let s6:  CGFloat = 24
    static let s8:  CGFloat = 32
    static let s10: CGFloat = 40
    static let s12: CGFloat = 48
    static let s16: CGFloat = 64
}
```

### 9.5 `Core/Theme/TujiRadius.swift`

```swift
import CoreGraphics

enum Radius {
    static let xs:   CGFloat = 4
    static let sm:   CGFloat = 6
    static let md:   CGFloat = 10
    static let lg:   CGFloat = 14
    static let xl:   CGFloat = 20
    static let pill: CGFloat = 999
}
```

### 9.6 `Core/Theme/TujiShadow.swift`

```swift
import SwiftUI

struct TujiCardShadow: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(0.08), radius: 24, x: 0, y: 8)
    }
}

extension View {
    func tujiCardShadow() -> some View { modifier(TujiCardShadow()) }
}
```

### 9.7 驗證 SwiftLint 紀律有抓

故意寫一行錯的：

```swift
// 在 ContentView.swift 加
Color(hex: 0x123456)  // 應該被 SwiftLint no_hex_color_outside_theme 擋
```

跑 `swiftlint` → 看到紅字錯誤。確認規則生效後刪掉。

---

## 10. First-build 畫面

把 `ContentView.swift` 改成：

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: Space.s5) {
            Image("mascot-wave")    // 暫時用 placeholder
                .resizable()
                .frame(width: 88, height: 88)

            Text("Tuji")
                .font(.tujiH1)
                .foregroundStyle(.tujiInk)

            Text("用圖學英文")
                .font(.tujiBody)
                .foregroundStyle(.tujiInk3)

            Button {
                // smoke test 入口
                Task { await SmokeTest.ping() }
            } label: {
                Text("Smoke test")
                    .font(.tujiH4)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s6)
                    .padding(.vertical, Space.s4)
                    .background(.tujiTeal, in: .rect(cornerRadius: Radius.lg))
            }

            // dev overlay
            #if TUJI_DEV
            Text(buildInfo)
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk4)
                .padding(.top, Space.s8)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.tujiBg)
    }

    private var buildInfo: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let url = Bundle.main.infoDictionary?["TUJI_BASE_URL"] as? String ?? "?"
        return "v\(v) (\(b))\n\(url)"
    }
}

#Preview { ContentView() }
```

**驗收**：
- 選 `Tuji-Debug` + iPhone 15 模擬器 → Cmd+R
- 看到吉祥物 + Tuji 字樣 + smoke test 按鈕
- 底部 dev overlay 顯示版本 + base URL
- 沒紅色 build error

---

## 11. Smoke test

### 11.1 寫一個 `SmokeTest.swift`

```swift
import Foundation
import OSLog

enum SmokeTest {
    private static let log = Logger(subsystem: "app.tuji.ios", category: "smoke")

    static func ping() async {
        guard let urlStr = Bundle.main.object(forInfoDictionaryKey: "TUJI_BASE_URL") as? String,
              let url = URL(string: urlStr + "/api/_test/whoami") else {
            log.error("BASE_URL missing")
            return
        }

        var req = URLRequest(url: url)
        // 沒 token，預期回 {"user": null}
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            log.info("status=\((resp as? HTTPURLResponse)?.statusCode ?? 0)")
            log.info("body=\(String(data: data, encoding: .utf8) ?? "")")
        } catch {
            log.error("err=\(error.localizedDescription)")
        }
    }
}
```

### 11.2 跑

- App 跑起來 → 點「Smoke test」按鈕
- Xcode → View → Debug Area → 看 console
- 應該看到：
  ```
  smoke: status=200
  smoke: body={"user":null}
  ```

### 11.3 進階：Supabase SDK 接通

```swift
import Supabase

extension SmokeTest {
    static func supabaseHealthcheck() async {
        let url = Bundle.main.object(forInfoDictionaryKey: "TUJI_SUPABASE_URL") as! String
        let anon = Bundle.main.object(forInfoDictionaryKey: "TUJI_SUPABASE_ANON_KEY") as! String
        let client = SupabaseClient(supabaseURL: URL(string: url)!, supabaseKey: anon)
        do {
            let session = try await client.auth.session
            log.info("session=\(String(describing: session))")
        } catch {
            log.error("supabase=\(error.localizedDescription)")
        }
    }
}
```

跑一次，看不到 crash 就 OK（session 沒登入會 throw，但 SDK 接通了）。

### 11.4 用真實 token 驗 Bearer

- 在 Supabase Studio → SQL Editor 註一個帳號 + 拿 access token
- 暫時把 token 寫死進 SmokeTest：

  ```swift
  let TOKEN = "eyJ..."
  var req = URLRequest(url: url)
  req.setValue("Bearer \(TOKEN)", forHTTPHeaderField: "Authorization")
  ```

- 看到 `{"user":"test@tuji.app"}` → 後端 Bearer 路徑通了

### 11.5 清乾淨

- 刪掉 `/api/_test/whoami`（後端）
- 刪掉 token 寫死（前端）— 用一個 git commit 留 SmokeTest 殼，token 永遠不要進 repo

---

## 12. Git / CI / Tag

### 12.1 Git 初始化

```bash
cd /Users/rex/Desktop/tuji-ios

git init -b main
git add .
git status
# 確認 Secrets.xcconfig 不在裡面（在 .gitignore 內）
# 確認 xcuserdata/ 不在裡面

git commit -m "chore: bootstrap iOS project (W1)

- Xcode 16.2 + Swift 6 + iOS 17 deployment target
- 3 schemes + xcconfig (Debug / TestFlight / Release)
- SPM deps: supabase-swift, GoogleSignIn, Nuke, KeychainAccess
- Theme tokens (Color / Font / Space / Radius / Shadow)
- Fonts: Plus Jakarta + Noto Sans TC + JetBrains Mono
- Smoke test: backend Bearer auth verified
- SwiftLint + SwiftFormat + 10 自家紀律規則
- CI: pr.yml + release.yml + PR template + CODEOWNERS

Refs: iOS_DESIGN_BOOK.md, iOS_SWIFT_PLAN.md"
```

### 12.2 推遠端

```bash
# 在 GitHub 開私 repo: tuji-ios
git remote add origin git@github.com:<you>/tuji-ios.git
git push -u origin main
```

### 12.3 設 GitHub Secrets（之後 CI 用）

GitHub → Settings → Secrets and variables → Actions → New repository secret：

- [ ] `SECRETS_XCCONFIG_B64`
  ```bash
  base64 -i Config/Secrets.xcconfig | pbcopy
  ```
- [ ] `TUJI_DEV_TEAM`（10 字 Team ID）
- [ ] `APP_STORE_CONNECT_KEY_ID`（W9 才需要，先擱）
- [ ] `APP_STORE_CONNECT_ISSUER_ID`（同上）
- [ ] `APP_STORE_CONNECT_API_KEY_P8`（同上）
- [ ] `MATCH_PASSWORD`（同上）
- [ ] `MATCH_GIT_URL`（同上）

### 12.4 開第一個 PR 試 CI

```bash
git checkout -b chore/ci-smoke
echo "" >> README.md
git commit -am "chore: trigger CI"
git push -u origin chore/ci-smoke
gh pr create --title "chore: trigger CI" --body "Smoke test the PR workflow"
```

去 GitHub PR 頁看 Actions → lint + build-test 應該全綠。
合 PR + 刪 branch。

### 12.5 第一個 tag

```bash
git tag -a dev-w1 -m "W1 complete: bootstrap done, ready for W2 (Auth + RootView)"
git push origin dev-w1
```

> `dev-w1` 是純里程碑 tag，不觸發 `release.yml`（那個只認 `v*`）。

---

## W1 完成驗收（必須全綠才能進 W2）

- [ ] Xcode `Tuji-Debug` scheme 在 iPhone 15 模擬器跑得起來
- [ ] 看到 Tuji 字樣 + Mascot 圖（即使是 placeholder）+ Smoke test 按鈕
- [ ] dev overlay 顯示正確版本與 BASE_URL
- [ ] Smoke test 按鈕能打到 Vercel preview 的 `/api/_test/whoami` 並收到 JSON
- [ ] 用真實 access token 帶 Bearer，後端能回 `{user: <email>}`
- [ ] Supabase SDK 能初始化、不 crash
- [ ] 3 個 scheme 切換能 build（Debug / TestFlight / Release）
- [ ] SwiftLint `swiftlint --strict` 全綠
- [ ] SwiftFormat `swiftformat . --lint` 全綠
- [ ] GitHub Actions PR workflow 全綠
- [ ] `dev-w1` tag 已推
- [ ] Secrets.xcconfig 沒進 repo（`git log --all --full-history -- Config/Secrets.xcconfig` 為空）

---

## W2 預備（提前看）

W2 主題：**Auth + RootView state machine + Apple Sign-in + Google Sign-in**

預習：
- `iOS_DESIGN_BOOK.md §I.3` AuthService
- `iOS_DESIGN_BOOK.md §III.C` Welcome / Signup / Signin
- `iOS_DESIGN_BOOK.md §III.A` RootView 三態

W2 第一個 PR：`feat/auth-rootview` —— 拆出 `AuthService` + `RootView` 三態 + 訪客模式 + Email signup。
