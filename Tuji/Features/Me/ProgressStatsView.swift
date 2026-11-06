// 學習統計 — 我 的那幾塊數字，從 今天 直接打得開。
//
// 內容一個字都不是新的：`MeProgressSections` 就是 我 頁上的完成度、熟練度、
// 連續天數、熱力圖和主題明細。這裡是它的第二個宿主，不是它的副本 —— 它會被
// 切成一個獨立的元件，為的就是這件事。
//
// 會需要第二個宿主，是因為 今天 的墨塊收成一條總進度條之後，其餘的數字都在
// 我 那邊了，而「我到底學到哪」是在 今天 冒出來的問題，不是在 我 冒出來的。
//
// 用 push 不用跳分頁：跳去 我 會把人丟在一個有身分列、有設定、有弱點字的頁面
// 最上面，還得自己找路回來；push 進來看完一返回就回到 今天。
//
// 沒有下拉重新整理。`MeProgressSections` 自己帶 `.warmsAccumulation`，進來就
// 會依 TTL 重讀；而 `LearningRefreshCause` 裡唯一對得上的 `.pulledMe` 說的是
// 「我 下拉」，借來用會讓那句話變成假的。

import SwiftUI

struct ProgressStatsView: View {
    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back)
            ScrollView {
                TujiScreenTitle("學習統計")
                MeProgressSections()
                    .padding(.bottom, Space.s6)
            }
        }
        .background(.tujiPaper)
        .navigationTitle("學習統計")
        .toolbar(.hidden, for: .navigationBar)
    }
}
