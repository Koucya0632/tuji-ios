// Pins what goes with a headword: ruby, a line, or nothing.
//
// The rule used to be five copies of `if let pronunciation` across five
// screens, and only 認識 checked the reading against the headword. On the other
// four, every kana-only Japanese word printed itself twice — バスマット at
// display size and バスマット again underneath — because the server sends
// `pronunciation` as a copy of `reading`, and a kana headword *is* its own
// reading. These tests exist so that stays fixed and so English IPA, which
// looks superficially like the same case, keeps behaving differently.

import Foundation
import Testing
@testable import Tuji

struct HeadwordDisplayTests {
    private func jaWord(
        _ word: String,
        reading: String?,
        segments: [FuriganaSegment]? = nil
    )
        -> CardWord
    {
        CardWord(
            id: word,
            word: word,
            chinese: "",
            imageUrl: "",
            category: "kitchen",
            // The backend sends `pronunciation` as a copy of `reading` for
            // every Japanese word — all 480 of them — so the fixture does too.
            pronunciation: reading ?? "",
            reading: reading,
            readingSegments: segments,
            targetLanguage: .ja
        )
    }

    @Test
    func japaneseWithSegmentsGetsRuby() {
        let segments = [
            FuriganaSegment(text: "歯", ruby: "は"),
            FuriganaSegment(text: "磨", ruby: "みが"),
            FuriganaSegment(text: "き", ruby: nil),
            FuriganaSegment(text: "粉", ruby: "こ")
        ]
        let word = self.jaWord("歯磨き粉", reading: "はみがきこ", segments: segments)
        #expect(word.headwordDisplay == .ruby(segments))
    }

    @Test
    func japaneseWithoutSegmentsFallsBackToTheLine() {
        // MRT（台湾の地下鉄）is the one catalogue word nothing can align, so it
        // must keep the behaviour ruby replaced rather than losing its kana.
        let word = self.jaWord("MRT（台湾の地下鉄）", reading: "mrt（たいわんのちかてつ）")
        #expect(word.headwordDisplay == .line("mrt（たいわんのちかてつ）"))
    }

    @Test
    func kanaOnlyJapaneseSaysNothingTwice() {
        // 231 of the 480 Japanese words are written entirely in kana. There is
        // nothing to annotate and nothing to add underneath.
        let word = self.jaWord("バスマット", reading: "バスマット")
        #expect(word.headwordDisplay == .plain)
    }

    @Test
    func emptySegmentsAreNotRuby() {
        // An empty array is not a split; it would draw a headword with no text.
        let word = self.jaWord("洗剤", reading: "せんざい", segments: [])
        #expect(word.headwordDisplay == .line("せんざい"))
    }

    @Test
    func englishKeepsItsIPALine() {
        let word = CardWord(
            id: "toothpaste",
            word: "toothpaste",
            chinese: "牙膏",
            imageUrl: "",
            category: "bathroom",
            pronunciation: "/ˈtuːθpeɪst/",
            targetLanguage: .en
        )
        #expect(word.headwordDisplay == .line("/ˈtuːθpeɪst/"))
    }

    @Test
    func englishWithoutPronunciationAddsNothing() {
        let word = CardWord(
            id: "tomato",
            word: "tomato",
            chinese: "蕃茄",
            imageUrl: "",
            category: "kitchen",
            pronunciation: "",
            targetLanguage: .en
        )
        #expect(word.headwordDisplay == .plain)
    }

    @Test
    func languageIsInferredFromTheReadingWhenTheServerDidNotTag() {
        // Older caches and just-captured custom words carry no targetLanguage;
        // `wordLanguage` reads a kana reading as the Japanese marker it is.
        let word = CardWord(
            id: "x",
            word: "洗剤",
            chinese: "",
            imageUrl: "",
            category: "custom",
            pronunciation: "せんざい",
            reading: "せんざい",
            readingSegments: [
                FuriganaSegment(text: "洗", ruby: "せん"),
                FuriganaSegment(text: "剤", ruby: "ざい")
            ]
        )
        #expect(
            word.headwordDisplay == .ruby([
                FuriganaSegment(text: "洗", ruby: "せん"),
                FuriganaSegment(text: "剤", ruby: "ざい")
            ])
        )
    }

    @Test
    func theSameRuleAnswersForAStudyQueueWord() throws {
        // The three payload types must not diverge — divergence is the bug.
        let json = """
        {
          "id": "w1",
          "word": "バスマット",
          "chinese": "浴室防滑墊",
          "imageUrl": "",
          "pronunciation": "バスマット",
          "reading": "バスマット",
          "targetLanguage": "ja",
          "category": "bathroom"
        }
        """
        let word = try JSONDecoder().decode(StudyQueueWord.self, from: Data(json.utf8))
        #expect(word.headwordDisplay == .plain)
        #expect(word.readingSegments == nil)
    }
}
