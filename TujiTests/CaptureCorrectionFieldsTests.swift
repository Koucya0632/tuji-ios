// The whole {UILanguage × TargetLanguage} grid, in one place. It used to be
// answered twice — `monolingual` in a View computed property and
// `needsSeparateGloss` in the VM — as exact complements that nothing kept in
// step, and the View's copy was unreachable from a test.

import Testing
@testable import Tuji

struct CaptureCorrectionFieldsTests {
    @Test
    func chineseInterfacesEditTheChineseNameWhicheverLanguageTheyLearn() {
        for target in TargetLanguage.allCases {
            #expect(CaptureCorrectionFields.second(ui: .zhHant, target: target) == .chineseName)
            #expect(CaptureCorrectionFields.second(ui: .zhHans, target: target) == .chineseName)
        }
    }

    @Test
    func aMonolingualCaptureHasNoMeaningLeftToHandEnter() {
        // The lemma is already in the user's own language and the definition is
        // generated, so a second field would be asking them to repeat themselves.
        #expect(CaptureCorrectionFields.second(ui: .ja, target: .ja) == .hidden)
        #expect(CaptureCorrectionFields.second(ui: .en, target: .en) == .hidden)
    }

    @Test
    func crossLanguageCapturesEditTheirOwnLanguageGloss() {
        #expect(CaptureCorrectionFields.second(ui: .ja, target: .en) == .gloss)
        #expect(CaptureCorrectionFields.second(ui: .en, target: .ja) == .gloss)
    }

    @Test
    func theGlossQuestionIsTheFieldQuestion() {
        // Derived rather than restated: the two answers cannot drift apart,
        // which is the entire reason this module exists.
        for ui in UILanguage.allCases {
            for target in TargetLanguage.allCases {
                #expect(
                    CaptureCorrectionFields.needsGloss(ui: ui, target: target)
                        == (CaptureCorrectionFields.second(ui: ui, target: target) == .gloss)
                )
            }
        }
    }

    @Test
    func onlyJaEnLearningTheOtherOneNeedsAGloss() {
        // Pinned as a truth table so a new UI language cannot quietly inherit
        // "no gloss" — 4 × 2 cells, two of them true.
        let needing = UILanguage.allCases.flatMap { ui in
            TargetLanguage.allCases.compactMap { target in
                CaptureCorrectionFields.needsGloss(ui: ui, target: target) ? "\(ui)-\(target)" : nil
            }
        }
        #expect(Set(needing) == ["ja-en", "en-ja"])
    }

    @Test
    func aChipNeverShowsChineseToAJaOrEnInterface() {
        // 英文介面學英文曾在每個候選字下面看到中文——表單上根本沒有的欄位。
        #expect(CaptureCorrectionFields.candidateMeaning(second: .chineseName, zhHant: "貓", gloss: "cat") == "貓")
        #expect(CaptureCorrectionFields.candidateMeaning(second: .gloss, zhHant: "貓", gloss: "cat") == "cat")
        #expect(CaptureCorrectionFields.candidateMeaning(second: .gloss, zhHant: "貓", gloss: nil) == nil)
        #expect(CaptureCorrectionFields.candidateMeaning(second: .hidden, zhHant: "貓", gloss: "cat") == nil)
        #expect(CaptureCorrectionFields.candidateMeaning(second: .chineseName, zhHant: "  ", gloss: nil) == nil)
    }

    @Test
    func aRenameWithoutTheChineseFieldWithholdsTheChineseName() {
        for second in [CaptureSecondField.gloss, .hidden] {
            // Untouched: the candidate's Chinese name still describes the card.
            #expect(
                CaptureCorrectionFields.chineseNameToSend(
                    second: second, lemma: "keyboard ", suggestedLemma: "keyboard", zhHant: "鍵盤"
                ) == "鍵盤"
            )
            // Renamed: 鍵盤 now names the thing the user corrected away from.
            #expect(
                CaptureCorrectionFields.chineseNameToSend(
                    second: second, lemma: "laptop", suggestedLemma: "keyboard", zhHant: "鍵盤"
                ) == nil
            )
        }
        // A Chinese interface edits the name itself, so whatever is there is sent.
        #expect(
            CaptureCorrectionFields.chineseNameToSend(
                second: .chineseName, lemma: "laptop", suggestedLemma: "keyboard", zhHant: "鍵盤"
            ) == "鍵盤"
        )
        // No candidate was ever applied: nothing to be stale against.
        #expect(
            CaptureCorrectionFields.chineseNameToSend(
                second: .hidden, lemma: "laptop", suggestedLemma: nil, zhHant: "筆電"
            ) == "筆電"
        )
    }

    @Test
    func anItemsLocalNameFollowsTheInterfaceLanguage() {
        let item = AtlasFixtures.item(
            "t1",
            imageId: "i1",
            language: .en,
            lemma: "cat",
            displayJa: "猫",
            displayEn: "cat"
        )
        #expect(item.localName(ui: .zhHant) == "中文-t1")
        #expect(item.localName(ui: .ja) == "猫")
        // Monolingual: the lemma is already the name.
        #expect(item.localName(ui: .en) == nil)
        // Not filled yet (or an older server): nothing, rather than Chinese.
        let bare = AtlasFixtures.item("t2", imageId: "i2", language: .en, lemma: "cat")
        #expect(bare.localName(ui: .ja) == nil)
    }
}
