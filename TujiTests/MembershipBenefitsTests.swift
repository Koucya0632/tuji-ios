// 方案權益: what each plan card lists under each policy, and that every row is
// translated. Keys only — which sentence renders is the catalogue's business.

import Foundation
import Testing
@testable import Tuji

struct MembershipBenefitsTests {
    private func keys(_ card: MembershipPlanCard, _ policy: MemberPolicy) -> [String] {
        MembershipBenefits.rows(for: card, policy: policy).map(\.key)
    }

    @Test
    func proUnderV1KeepsTheOldQuotaAndNoWordLists() {
        let rows = self.keys(.pro, .v1)
        #expect(rows.contains("AI 辨識次數提升至每月 500 次"))
        #expect(!rows.contains("AI 辨識次數提升至每月 200 次"))
        #expect(!rows.contains { $0.contains("詞表") })
    }

    @Test
    func proUnderV2HasTheNewQuotaAndWordLists() {
        let rows = self.keys(.pro, .v2)
        #expect(rows.contains("AI 辨識次數提升至每月 200 次"))
        #expect(rows.contains("個人詞表增加到 100 張"))
        #expect(rows.contains("高精度 AI 辨識（每月 30 次）"))
    }

    @Test
    func lifetimeListsWordListsAndNotesButNotInsights() {
        let rows = self.keys(.lifetime, .v2)
        #expect(rows.contains("個人詞表 20 張，可以從詞表背詞"))
        #expect(rows.contains("為每個字寫下自己的筆記"))
        // Decided 2026-09-28: 常見誤用 and 用法補充 are too sparse to sell.
        #expect(!rows.contains { $0.contains("誤用") || $0.contains("用法補充") })
    }

    @Test
    func everyRowIsTranslated() {
        let all = [MembershipPlanCard.lifetime, .pro].flatMap { card in
            [MemberPolicy.v1, .v2].flatMap { self.keys(card, $0) }
        }
        for key in Set(all) {
            for lang in ["en", "ja", "zh-Hans"] {
                #expect(tujiLocalized(String.LocalizationValue(key), lang: lang) != key, "\(key) missing in \(lang)")
            }
        }
    }
}
