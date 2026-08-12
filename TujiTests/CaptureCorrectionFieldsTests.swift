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
}
