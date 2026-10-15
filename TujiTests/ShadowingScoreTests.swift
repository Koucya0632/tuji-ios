// 跟讀 — what counts as heard. Decisions only: which words, which verdict.

import Testing
@testable import Tuji

struct ShadowingScoreTests {
    @Test
    func kanjiHeardAsKanaStillCounts() {
        let score = ShadowingScore(target: "傘はここに置いてね。", heard: "かさはここにおいてね", language: .ja)
        #expect(score.missed.isEmpty)
        #expect(score.verdict == .great)
    }

    @Test
    func katakanaAndHiraganaAreTheSameSound() {
        let score = ShadowingScore(target: "コーヒーをください", heard: "こーひーをください", language: .ja)
        #expect(score.verdict == .great)
    }

    @Test
    func aJapaneseWordLeftOutIsMissed() {
        let score = ShadowingScore(target: "熱いから気をつけてね。", heard: "気をつけてね", language: .ja)
        #expect(score.missed.contains("熱い"))
        #expect(score.verdict != .great)
    }

    @Test
    func missedWordsNextToEachOtherAreOnePhrase() {
        let score = ShadowingScore(target: "いらっしゃいませ！傘はここに置いてね。", heard: "いらっしゃいませ", language: .ja)
        #expect(score.missedPhrases(joiner: "") == ["傘はここに置いてね"])
        let english = ShadowingScore(target: "Put your umbrella over here", heard: "put here", language: .en)
        #expect(english.missedPhrases(joiner: " ") == ["your umbrella over"])
    }

    @Test
    func punctuationIsNotScored() {
        let score = ShadowingScore(target: "いらっしゃいませ！", heard: "いらっしゃいませ", language: .ja)
        #expect(score.ratio == 1)
        #expect(!score.words.map(\.surface).contains("！"))
    }

    @Test
    func englishIgnoresCaseAndPunctuation() {
        let score = ShadowingScore(target: "Thanks. A coffee, please!", heard: "thanks a coffee please", language: .en)
        #expect(score.ratio == 1)
        #expect(score.words.map(\.surface) == ["Thanks", "A", "coffee", "please"])
    }

    @Test
    func anEnglishWordSaidWronglyIsMissed() {
        let score = ShadowingScore(target: "Put your umbrella here", heard: "put your umbrellas here", language: .en)
        #expect(score.missed == ["umbrella"])
        #expect(score.verdict == .close)
    }

    @Test
    func nothingHeardIsTryAgain() {
        let score = ShadowingScore(target: "Put your umbrella here", heard: "", language: .en)
        #expect(score.ratio == 0)
        #expect(score.verdict == .again)
    }

    @Test
    func wordsHeardOutOfOrderAreNotAllCredited() {
        let score = ShadowingScore(target: "one two three four", heard: "four three two one", language: .en)
        #expect(score.missed.count == 3)
    }
}
