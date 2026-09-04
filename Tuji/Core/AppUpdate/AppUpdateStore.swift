// 「有沒有新版」這件事在畫面上的樣子。
//
// 三件事在這裡碰頭：裝置上的版本（`AppInfo`）、App Store 上的版本
// （`AppStoreVersionLookup`）、以及使用者按過什麼（`AppUpdateMemory`）。
// 決定本身不在這裡 —— 那是 `AppUpdatePolicy`，純函式，才測得到。
//
// 沒有任何一條路會讓這個 store 顯示錯誤。查詢失敗、版本號解不開、使用者離線，
// 全部都是「沒有新版」。這是一個提示，不是一個功能。

import Foundation
import Observation

@MainActor
@Observable
final class AppUpdateStore {
    static let shared = AppUpdateStore()

    /// 有值 = 現在該跳提示，值是 App Store 上的版本號。
    private(set) var pendingVersion: String?

    /// 商店頁的網址。**提示關掉時不會跟著清空**：`TujiPrompt` 在跑 primary action
    /// 之前就先把 `isPresented` 設回 false，動作讀到的會是關掉之後的狀態 ——
    /// 如果這個網址跟著 `pendingVersion` 一起被清掉，「前往更新」會什麼都不做。
    private(set) var appStoreURL: URL?

    private let installedVersion: String
    private let lookup: any AppStoreVersionLookup
    private let memory: AppUpdateMemory

    /// 每個參數都可以換掉，包括 `installedVersion` —— 測試要能演「裝置上是舊版」，
    /// 而 bundle 裡的那個數字在測試程序裡是測試 bundle 的版本，不是 App 的。
    init(
        installedVersion: String = AppInfo.shortVersion,
        lookup: any AppStoreVersionLookup = LiveAppStoreLookup(),
        memory: AppUpdateMemory = AppUpdateMemory()
    ) {
        self.installedVersion = installedVersion
        self.lookup = lookup
        self.memory = memory
    }

    /// 進到主畫面時、以及每次回到前景時呼叫。自己會判斷該不該真的去查。
    func checkIfNeeded(now: Date = .now) async {
        guard AppUpdatePolicy.shouldCheck(
            lastCheckedAt: self.memory.lastCheckedAt,
            now: now
        )
        else { return }

        guard let release = try? await self.lookup.latestRelease() else { return }

        // 只有查成功才記時間。失敗就記的話，飛航模式下打開一次 App
        // 會把接下來一整天的檢查都關掉。
        self.memory.lastCheckedAt = now
        self.appStoreURL = release.url

        guard AppUpdatePolicy.shouldPrompt(
            installed: self.installedVersion,
            latest: release.version,
            snoozed: self.memory.snoozed,
            now: now
        )
        else { return }

        self.pendingVersion = release.version
    }

    /// 提示被關掉 —— 按「前往更新」和按「稍後再說」都會走這裡。
    ///
    /// 去了 App Store 也一樣要靜音：使用者可能只是看了一眼就退出來，
    /// 而下一次啟動又跳一次同一句話，會讓那顆按鈕看起來沒有作用。
    func dismiss(now: Date = .now) {
        if let version = self.pendingVersion {
            self.memory.snoozed = SnoozedAppUpdate(version: version, at: now)
        }
        self.pendingVersion = nil
    }
}

/// 使用者按過什麼、上次什麼時候查的。`UserDefaults` 的那一半，單獨拿出來
/// 是為了讓 store 的測試不必碰到裝置上的真實偏好設定。
struct AppUpdateMemory {
    private let defaults: UserDefaults
    private let lastCheckedKey = "tuji.appUpdate.lastCheckedAt.v1"
    private let snoozedVersionKey = "tuji.appUpdate.snoozedVersion.v1"
    private let snoozedAtKey = "tuji.appUpdate.snoozedAt.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastCheckedAt: Date? {
        get { self.defaults.object(forKey: self.lastCheckedKey) as? Date }
        nonmutating set { self.defaults.set(newValue, forKey: self.lastCheckedKey) }
    }

    var snoozed: SnoozedAppUpdate? {
        get {
            guard let version = self.defaults.string(forKey: self.snoozedVersionKey),
                  let at = self.defaults.object(forKey: self.snoozedAtKey) as? Date
            else { return nil }
            return SnoozedAppUpdate(version: version, at: at)
        }
        nonmutating set {
            self.defaults.set(newValue?.version, forKey: self.snoozedVersionKey)
            self.defaults.set(newValue?.at, forKey: self.snoozedAtKey)
        }
    }
}
