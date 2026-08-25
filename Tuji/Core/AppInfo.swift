// 版本號只有一個來源：bundle。
//
// 設定頁與「關於」頁各寫死了一行 `Text("Tuji v1.1.0 · 圖記")`，靠發版時手改。
// git 說 1.0.0 → 1.1.0 是在 1.1.0 的發版 commit 手改的，而 1.1.1 沒人改 ——
// 送出去的包會對使用者說自己是 1.1.0，簡體使用者甚至看到一個被翻譯過的錯版本號
// （字表裡躺著 `Tuji v1.1.0 · 图记`）。沒有任何測試看得到它，因為在型別上它是一句文案。
//
// 這件事的修法不是「這次記得改」，是讓那個數字不再是文案的一部分。
//
// 意見回饋與學習回報早就在讀 bundle 了，只是各讀各的 —— 同一句
// `Bundle.main.object(forInfoDictionaryKey:)` 抄了好幾份。這裡給它一個名字。
// `CrashReporting` 沒有跟過來：它的 fallback 是 "unknown" 而不是 "?"，
// 那是會進遙測的值，不該為了收攏寫法而改掉。
//
// `nonisolated`: 純值型別，讀的是 App 啟動後就不再變的 Info.plist。

import Foundation

nonisolated enum AppInfo {
    /// `CFBundleShortVersionString` — App Store 上顯示的 SemVer（1.1.1）。
    static let shortVersion = AppInfo.string(for: "CFBundleShortVersionString")

    /// `CFBundleVersion` — 每次 archive 遞增的內部 build number。
    static let buildNumber = AppInfo.string(for: "CFBundleVersion")

    private static func string(for key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "?"
    }
}
