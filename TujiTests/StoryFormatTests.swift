// 情境故事 — what a story looks like on the wire, and how a Japanese line is
// cut for furigana.

import Foundation
import Testing
@testable import Tuji

struct StoryFormatTests {
    @Test
    func aMonolingualJapaneseStoryDecodesWithFuriganaAndNotes() throws {
        let json = """
        {"title":"Moiraと買い物","intro":"i","segments":[
          {"speaker":"narrator","text":"n","wordIds":[]},
          {"speaker":"cat","text":"三つ買います。","furigana":[
            {"text":"三","ruby":"みっ"},{"text":"つ","ruby":null},{"text":"買","ruby":"か"},{"text":"います。","ruby":null}
          ],"wordIds":["apple"]}
        ],"wordNotes":[{"id":"apple","note":"赤くて丸い果物"}]}
        """
        let story = try JSONDecoder().decode(Story.self, from: Data(json.utf8))
        #expect(story.segments[1].furigana?.count == 4)
        #expect(story.segments[1].translation == nil)
        #expect(story.wordNotes == [Story.WordNote(id: "apple", note: "赤くて丸い果物")])
    }

    @Test
    func aBilingualStoryDecodesWithoutEither() throws {
        let json = """
        {"title":"t","intro":"i","segments":[
          {"speaker":"you","text":"Two apples, please.","translation":"請給我兩個蘋果。","wordIds":["apple"]}
        ]}
        """
        let story = try JSONDecoder().decode(Story.self, from: Data(json.utf8))
        #expect(story.segments[0].furigana == nil)
        #expect(story.segments[0].translation == "請給我兩個蘋果。")
        #expect(story.wordNotes == nil)
    }

    @Test
    func kanjiRunsStayWholeAndBareKanaBreaksAnywhere() {
        let units = FuriganaSentence.units([
            FuriganaSegment(text: "三", ruby: "みっ"),
            FuriganaSegment(text: "つ", ruby: nil),
            FuriganaSegment(text: "会議室", ruby: "かいぎしつ"),
            FuriganaSegment(text: "へ", ruby: nil)
        ])
        #expect(units == [
            .init(text: "三", ruby: "みっ"),
            .init(text: "つ", ruby: nil),
            .init(text: "会議室", ruby: "かいぎしつ"),
            .init(text: "へ", ruby: nil)
        ])
    }

    @Test
    func punctuationAndSmallKanaNeverStartALine() {
        let units = FuriganaSentence.units([
            FuriganaSegment(text: "行", ruby: "い"),
            FuriganaSegment(text: "きましょう。", ruby: nil)
        ])
        #expect(units.map(\.text) == ["行", "き", "ま", "しょ", "う。"])
        #expect(!units.contains { $0.text.first.map { "。ょ".contains($0) } == true })
    }
}
