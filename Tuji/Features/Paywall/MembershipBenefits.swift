// 方案權益 — the rows the 永久會員 card lists.
//
// One list for every billing mode: Pro is no longer sold (2026-10-06), and the
// pre-points numbers (20 格, 10 次 a month) are void. The rows must match
// docs/marketing/CLAIMS.md §1.

import Foundation

struct MembershipBenefit: Equatable {
    let icon: String
    /// The zh-Hant catalogue key.
    let key: String
}

enum MembershipBenefits {
    /// 圖鑑 and 場面 first — what the app is for — then what the membership
    /// opens on top, then which AI features draw on 罐頭點數. AI has no
    /// monthly quota: it is paid per use from the points.
    static let lifetime: [MembershipBenefit] = [
        .init(icon: "books.vertical", key: "永久解鎖全部官方圖鑑"),
        .init(icon: "bubble.left.and.bubble.right", key: "全部場面練習"),
        .init(icon: "square.grid.2x2", key: "自製圖鑑 200 格"),
        .init(icon: "list.bullet.rectangle", key: "個人詞表 20 張，可以從詞表背詞"),
        .init(icon: "note.text", key: "為每個字寫下自己的筆記"),
        .init(icon: "bookmark", key: "收藏、學習與投稿物見"),
        .init(icon: "sparkles", key: "AI 辨識、查詞與語法，需要使用罐頭點數")
    ]
}
