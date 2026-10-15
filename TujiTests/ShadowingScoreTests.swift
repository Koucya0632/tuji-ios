// 跟讀 — what counts as heard. Decisions only: which words, what share.

import Testing
@testable import Tuji

struct ShadowingScoreTests {
    private func missed(_ score: ShadowingScore) -> [String] {
        score.words.filter { !$0.heard }.map(\.surface)
    }

    @Test
    func kanjiHeardAsKanaStillCounts() {
        let score = ShadowingScore(target: "傘はここに置いてね。", heard: "かさはここにおいてね", language: .ja)
        #expect(self.missed(score).isEmpty)
        #expect(score.ratio == 1)
    }

    @Test
    func katakanaAndHiraganaAreTheSameSound() {
        let score = ShadowingScore(target: "コーヒーをください", heard: "こーひーをください", language: .ja)
        #expect(score.ratio == 1)
    }

    @Test
    func aJapaneseWordLeftOutIsMissed() {
        let score = ShadowingScore(target: "熱いから気をつけてね。", heard: "気をつけてね", language: .ja)
        #expect(self.missed(score).contains("熱い"))
        #expect(score.ratio < 1)
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
        #expect(self.missed(score) == ["umbrella"])
        #expect(score.ratio == 0.75)
    }

    @Test
    func nothingHeardIsZero() {
        let score = ShadowingScore(target: "Put your umbrella here", heard: "", language: .en)
        #expect(score.ratio == 0)
    }

    @Test
    func wordsHeardOutOfOrderAreNotAllCredited() {
        let score = ShadowingScore(target: "one two three four", heard: "four three two one", language: .en)
        #expect(self.missed(score).count == 3)
    }
}
