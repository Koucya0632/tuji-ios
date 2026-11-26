// 方案權益: what the 永久會員 card lists, and that every row is translated.
// Keys only — which sentence renders is the catalogue's business.

import Foundation
import Testing
@testable import Tuji

struct MembershipBenefitsTests {
    private var keys: [String] { MembershipBenefits.lifetime.map(\.key) }

    @Test
    func atlasAndScenesComeFirst() {
        #expect(Array(self.keys.prefix(2)) == ["永久解鎖全部官方圖鑑", "全部場面練習"])
    }

    @Test
    func listsWhatTheMembershipOpens() {
        #expect(self.keys.contains { $0.contains("物見") })
        #expect(self.keys.contains { $0.contains("筆記") })
        #expect(self.keys.contains("個人詞表 20 張，可以從詞表背詞"))
        #expect(self.keys.contains("自製圖鑑 200 格"))
        #expect(self.keys.contains { $0.contains("AI") && $0.contains("罐頭點數") })
        // Decided 2026-09-28: 常見誤用 and 用法補充 are too sparse to sell.
        #expect(!self.keys.contains { $0.contains("誤用") || $0.contains("用法補充") })
    }

    @Test
    func sellsNoProAndNoMonthlyQuota() {
        // Pro is off sale; AI is paid per use from the points.
        #expect(!self.keys.contains { $0.contains("Pro") || $0.contains("每月") })
    }

    @Test
    func everyRowIsTranslated() {
        for key in self.keys {
            for lang in ["en", "ja", "zh-Hans"] {
                #expect(tujiLocalized(String.LocalizationValue(key), lang: lang) != key, "\(key) missing in \(lang)")
            }
        }
    }
}
