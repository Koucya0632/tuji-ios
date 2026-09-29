// 方案權益 — which rows each plan card lists, under which membership policy.
//
// These used to be literals inside `PaywallView`'s body, with `if isV2` beside
// two of them, so "Pro under v1 must not mention 詞表" was checkable only by
// screenshot. The numbers must match docs/MEMBERSHIP_PUBLIC_COPY.md §1.

import Foundation

enum MembershipPlanCard {
    case lifetime
    case pro
}

struct MembershipBenefit: Equatable {
    let icon: String
    /// The zh-Hant catalogue key.
    let key: String
}

enum MembershipBenefits {
    static func rows(for card: MembershipPlanCard, policy: MemberPolicy) -> [MembershipBenefit] {
        let v2 = policy == .v2
        switch card {
        case .lifetime:
            return [
                .init(icon: "books.vertical.fill", key: "解鎖全部官方圖鑑系列"),
                .init(icon: "square.stack.3d.up.fill", key: "個人自製圖鑑 20 格"),
                .init(icon: "sparkles", key: "AI 辨識每月 10 次"),
                .init(icon: "bookmark.fill", key: "收藏、學習與投稿物見"),
                .init(icon: "list.bullet.rectangle", key: "個人詞表 20 張，可以從詞表背詞"),
                .init(icon: "note.text", key: "為每個字寫下自己的筆記")
            ]
        case .pro:
            var rows: [MembershipBenefit] = [
                .init(icon: "square.stack.3d.up.fill", key: "自製圖鑑容量提升至 300 格"),
                // v1 is the pre-membership quota; v2 moved the difference into
                // 永久會員's 10 and Pro's total of 200.
                .init(icon: "sparkles", key: v2 ? "AI 辨識次數提升至每月 200 次" : "AI 辨識次數提升至每月 500 次"),
                .init(icon: "scope", key: "高精度 AI 辨識（每月 30 次）")
            ]
            // 詞表 does not exist under v1.
            if v2 { rows.append(.init(icon: "list.bullet.rectangle", key: "個人詞表增加到 100 張")) }
            rows.append(.init(icon: "bolt.fill", key: "優先支援與後續 Pro 功能"))
            return rows
        }
    }
}
