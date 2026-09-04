// 「要不要提示更新」拆成兩個問題，兩個都是純函式：
//
//   1. 現在該不該去問 App Store？（`shouldCheck`）
//   2. 問到的版本值不值得跳一次提示？（`shouldPrompt`）
//
// 分開是因為它們的失敗方式不同。查詢太頻繁只是浪費一次請求；提示太頻繁是
// 每次打開 App 都被同一句話擋一下 —— 那種 App 使用者只會學會閉著眼睛按掉。
//
// 兩條規則之外沒有第三條：這裡不做強制更新。沒有「低於某版就不能用」的閘門，
// 因為那需要一個伺服器端的真相來源，而現在的真相來源是 App Store 自己。

import Foundation

/// 使用者按過「稍後再說」的那個版本，以及按下去的時間。
struct SnoozedAppUpdate: Equatable {
    let version: String
    let at: Date
}

enum AppUpdatePolicy {
    /// 問 App Store 的間隔。查詢本身沒有成本壓力，但一天一次已經遠比 App Store
    /// 自己的 CDN 更新得快 —— 那邊的版本號本來就會晚幾個小時才變。
    static let checkInterval: TimeInterval = 60 * 60 * 24

    /// 按了「稍後再說」之後，同一個版本能安靜多久。
    ///
    /// 不是永久靜音：使用者按「稍後」通常是「現在不方便」，不是「這輩子都不要」。
    /// 但也不是下次啟動就再問一次 —— 那等於沒有這顆按鈕。
    static let snoozeInterval: TimeInterval = 60 * 60 * 24 * 3

    /// 沒查過（`nil`）就是該查。第一次啟動就會問一次。
    static func shouldCheck(lastCheckedAt: Date?, now: Date) -> Bool {
        guard let lastCheckedAt else { return true }
        // 使用者把系統時間往回調過，`now` 會早於上次查詢時間。當作該查，
        // 而不是讓一個壞掉的時間戳把檢查永久關掉。
        guard now >= lastCheckedAt else { return true }
        return now.timeIntervalSince(lastCheckedAt) >= self.checkInterval
    }

    /// 查到了新版，不代表現在就是說出口的時候。
    ///
    /// 主畫面上有兩件事會被這個提示蓋掉：正在進行的學習，以及第一次啟動的功能導覽。
    /// 兩件事都是使用者正在做的，而更新可以等 —— 提示不會消失，只是往後站。
    static func mayPresent(
        pendingVersion: String?,
        studyFocusActive: Bool,
        tourRunning: Bool
    )
        -> Bool
    {
        pendingVersion != nil && !studyFocusActive && !tourRunning
    }

    /// 只有「App Store 上的版本確實比裝置上的新」才會是 `true`。
    ///
    /// 版本號看不懂就回 `false`（見 `AppVersion`）。TestFlight 的包版本號可能
    /// 比上架版還新，那也是 `false` —— 叫一個內測使用者「更新」到比他手上還舊的版本
    /// 是這條路上最容易寫出來的 bug。
    static func shouldPrompt(
        installed: String,
        latest: String,
        snoozed: SnoozedAppUpdate?,
        now: Date
    )
        -> Bool
    {
        guard let installed = AppVersion(installed),
              let latest = AppVersion(latest),
              latest > installed
        else { return false }

        // 比的是版本，不是字串：靜音時存的是 App Store 給的那串，而 `1.2` 和
        // `1.2.0` 是同一版 —— 字串比對會讓靜音在改寫法的那一版失效。
        guard let snoozed, AppVersion(snoozed.version) == latest else { return true }
        guard now >= snoozed.at else { return true }
        return now.timeIntervalSince(snoozed.at) >= self.snoozeInterval
    }
}
