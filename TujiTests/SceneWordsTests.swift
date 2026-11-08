// A 問句's 相關詞條: which words show, in what order, and which carry a lock.

import Testing
@testable import Tuji

struct SceneWordsTests {
    private let words = [
        CardWord(
            id: "plastic-bag",
            word: "ビニール袋",
            chinese: "塑膠袋",
            imageUrl: "",
            category: "supermarket",
            pronunciation: ""
        ),
        CardWord(
            id: "point-card",
            word: "ポイントカード",
            chinese: "集點卡",
            imageUrl: "",
            category: "convenience-store",
            pronunciation: ""
        ),
        CardWord(id: "menu", word: "メニュー", chinese: "菜單", imageUrl: "", category: "restaurant", pronunciation: "")
    ]

    private func resolve(
        _ ids: [String],
        studyable: [String]?,
        direction: LearningDirection = .zhJa
    )
        -> [SceneWord]
    {
        SceneWords.resolve(ids: ids, in: self.words, studyable: studyable, direction: direction)
    }

    @Test
    func keepsTheQuestionsOrderNotTheDictionarys() {
        #expect(self.resolve(["point-card", "plastic-bag"], studyable: nil).map(\.id) == ["point-card", "plastic-bag"])
    }

    @Test
    func dropsIdsTheDictionaryHasNotLoaded() {
        #expect(self.resolve(["microwave-station", "menu"], studyable: nil).map(\.id) == ["menu"])
        #expect(SceneWords.resolve(ids: ["menu"], in: [], studyable: nil, direction: .zhJa).isEmpty)
    }

    @Test
    func withoutAStudyGateNothingIsLocked() {
        #expect(self.resolve(["plastic-bag", "point-card"], studyable: nil).allSatisfy { !$0.isLocked })
    }

    @Test
    func aWordOutsideTheStudyableTopicsIsLocked() {
        let rows = self.resolve(["plastic-bag", "point-card"], studyable: ["convenience-store", "fruits"])
        #expect(rows.map(\.id) == ["plastic-bag", "point-card"])
        #expect(rows.map(\.isLocked) == [true, false])
    }

    @Test
    func anEnglishLearnerGetsNoWords() {
        #expect(self.resolve(["menu"], studyable: nil, direction: .zhEn).isEmpty)
    }
}
