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
        #expect(word.headwordDisplay(in: .en) == .ruby(segments))
    }

    @Test
    func japaneseWithoutSegmentsFallsBackToTheLine() {
        // MRT（台湾の地下鉄）is the one catalogue word nothing can align, so it
        // must keep the behaviour ruby replaced rather than losing its kana.
        let word = self.jaWord("MRT（台湾の地下鉄）", reading: "mrt（たいわんのちかてつ）")
        #expect(word.headwordDisplay(in: .en) == .line("mrt（たいわんのちかてつ）"))
    }

    @Test
    func kanaOnlyJapaneseSaysNothingTwice() {
        // 231 of the 480 Japanese words are written entirely in kana. There is
        // nothing to annotate and nothing to add underneath.
        let word = self.jaWord("バスマット", reading: "バスマット")
        #expect(word.headwordDisplay(in: .en) == .plain)
    }

    @Test
    func emptySegmentsAreNotRuby() {
        // An empty array is not a split; it would draw a headword with no text.
        let word = self.jaWord("洗剤", reading: "せんざい", segments: [])
        #expect(word.headwordDisplay(in: .en) == .line("せんざい"))
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
        #expect(word.headwordDisplay(in: .en) == .line("/ˈtuːθpeɪst/"))
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
        #expect(word.headwordDisplay(in: .en) == .plain)
    }

    @Test
    func languageIsInferredFromTheReadingWhenTheServerDidNotTag() {
        // Older caches and just-captured custom words carry no targetLanguage;
        // a kana reading is the Japanese marker it looks like, and it beats the
        // session — the display is `.ruby` under an 英文 session.
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
            word.headwordDisplay(in: .en) == .ruby([
                FuriganaSegment(text: "洗", ruby: "せん"),
                FuriganaSegment(text: "剤", ruby: "ざい")
            ])
        )
    }

    /// A payload with neither a tag nor a reading — the case that used to read
    /// as English at eleven of thirteen call sites, on a coin flip the untagged
    /// word never got to call. There is nothing on the word to go on, so
    /// 當前圖鑑語言 decides, and it decides *differently* in the two sessions.
    private var untagged: CardWord {
        CardWord(
            id: "u",
            word: "ざる",
            chinese: "笊籬",
            imageUrl: "",
            category: "custom",
            pronunciation: ""
        )
    }

    @Test
    func anUntaggedWordFollowsTheSessionRatherThanGuessingEnglish() {
        #expect(self.untagged.language(in: .ja) == .ja)
        #expect(self.untagged.language(in: .en) == .en)
        // The payload itself still says nothing — the session is doing the work.
        #expect(self.untagged.taggedLanguage == nil)
    }

    @Test
    func aTaggedWordIgnoresTheSessionInBothDirections() {
        let japanese = self.jaWord("洗剤", reading: "せんざい")
        #expect(japanese.language(in: .en) == .ja)
        #expect(japanese.language(in: .ja) == .ja)
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
        let word = try JSONDecoder.tuji.decode(StudyQueueWord.self, from: Data(json.utf8))
        #expect(word.headwordDisplay(in: .en) == .plain)
        #expect(word.readingSegments == nil)
    }
}
