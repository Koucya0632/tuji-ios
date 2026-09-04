// 提示本身：一句話、兩顆按鈕，掛在 App 的殼上。
//
// 為什麼是 modifier 而不是寫在 `MainTabsView` 裡：那個檔案是導覽根，已經有
// 分頁、手勢、深連結和第一次啟動的導覽四件事在裡面，而更新提示跟它們沒有
// 任何關係 —— 它只是需要一個「永遠都在畫面上」的位置。殼提供位置，其餘都在這裡。
//
// 不寫更新內容。要寫就得在每次發版時多維護一份文案（還要四種語言），而使用者
// 在這一步要做的決定只有一個：現在更新，還是等一下。

import SwiftUI

extension View {
    /// `tourRunning`：第一次啟動的功能導覽正在跑。只有殼知道這件事。
    func appUpdatePrompt(tourRunning: Bool) -> some View {
        modifier(AppUpdatePromptModifier(tourRunning: tourRunning))
    }
}

private struct AppUpdatePromptModifier: ViewModifier {
    let tourRunning: Bool

    @Environment(AppUpdateStore.self) private var updates
    @Environment(StudyFocus.self) private var studyFocus
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            // 冷啟動一次，之後每次回到前景再問一次 —— 後者是給「幾天沒關過 App」
            // 的人，`.task` 一輩子只跑一次。`checkIfNeeded` 自己有一天一次的節流，
            // 所以這裡不必也不該再判斷一次。
            .task { await self.updates.checkIfNeeded() }
            .onChange(of: self.scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await self.updates.checkIfNeeded() }
            }
            .tujiPrompt(
                isPresented: self.isPresented,
                style: .confirmation,
                title: "有新版本可用",
                message: "App Store 上已經有 \(self.updates.pendingVersion ?? "") 了。",
                primary: TujiPromptAction("前往更新") {
                    // `appStoreURL` 刻意不隨提示關閉而清空 —— 見 `AppUpdateStore`。
                    if let url = self.updates.appStoreURL { self.openURL(url) }
                },
                secondary: TujiPromptAction("稍後再說", role: .cancel) {}
            )
    }

    /// 關掉就等於「這個版本先安靜幾天」，所以兩顆按鈕都會走到 `dismiss()`：
    /// `TujiPrompt` 在跑按鈕的動作之前，就先把這個 binding 設回 false。
    private var isPresented: Binding<Bool> {
        Binding(
            get: {
                AppUpdatePolicy.mayPresent(
                    pendingVersion: self.updates.pendingVersion,
                    studyFocusActive: self.studyFocus.active,
                    tourRunning: self.tourRunning
                )
            },
            set: { presented in
                if !presented { self.updates.dismiss() }
            }
        )
    }
}
