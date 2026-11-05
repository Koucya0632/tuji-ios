import Foundation
import Testing
import UIKit
@testable import Tuji

@MainActor
struct StoryStagePresentationTests {
    private func segment(_ stage: String = "null", speaker: String = "cat") throws -> Story.Segment {
        let json = """
        {"speaker":"\(speaker)","text":"Two apples.","translation":"兩顆蘋果。","wordIds":["apple"],"stage":\(stage)}
        """
        return try JSONDecoder().decode(Story.Segment.self, from: Data(json.utf8))
    }

    @Test(arguments: ["null", "42", "[]", "\"bad\"", "{}", "{\"areaId\":7,\"moiraAction\":false}"])
    func malformedHintsKeepTheSentence(_ raw: String) throws {
        let line = try self.segment(raw)
        #expect(line.text == "Two apples.")
        #expect(line.translation == "兩顆蘋果。")
        #expect(line.wordIds == ["apple"])
        let presentation = SupermarketPresentation(segment: line)
        #expect(presentation.area == .general)
        #expect(presentation.action == .think)
    }

    @Test
    func openingOldRepliesAndUnknownHintsHaveSafeDefaults() throws {
        #expect(SupermarketPresentation(segment: nil).action == .greet)
        #expect(try SupermarketPresentation(segment: self.segment(speaker: "you")).action == .listen)
        let unknown = try self.segment("{\"areaId\":\"frozen\",\"moiraAction\":\"dance\"}")
        #expect(SupermarketPresentation(segment: unknown).area == .general)
        #expect(SupermarketPresentation(segment: unknown).action == .think)
    }

    @Test
    func validCueFieldsSurviveIndependently() throws {
        let line = try self.segment("{\"areaId\":42,\"moiraAction\":\"hold_apple\"}")
        #expect(SupermarketPresentation(segment: line).area == .general)
        #expect(SupermarketPresentation(segment: line).action == .holdApple)
        let second = try self.segment("{\"areaId\":\"checkout\",\"moiraAction\":42}")
        #expect(SupermarketPresentation(segment: second).area == .checkout)
        #expect(SupermarketPresentation(segment: second).action == .think)
    }

    @Test
    func malformedCueStillArrivesAsAStreamedSegment() throws {
        let json = """
        {"type":"segment","segment":{"speaker":"you","text":"Milk.","wordIds":[],"stage":false}}
        """
        guard case let .segment(line) = try LiveAssistantStoryRepository.event(from: Data(json.utf8)) else {
            Issue.record("Valid streamed sentence was dropped because of a bad presentation hint")
            return
        }
        #expect(line.text == "Milk.")
        #expect(SupermarketPresentation(segment: line).action == .listen)
    }

    @Test
    func everyPresentationHasBundledArtworkAndUsableGrounding() {
        for area in SupermarketPresentation.Area.allCases {
            #expect(UIImage(named: area.imageName) != nil)
        }
        for action in SupermarketPresentation.Action.allCases {
            #expect(UIImage(named: action.imageName) != nil)
            let bounds = StorySpriteMetrics.bounds(for: action)
            #expect(bounds.top >= 0 && bounds.top < bounds.bottom && bounds.bottom <= 1)
            #expect(bounds.left >= 0 && bounds.left < bounds.right && bounds.right <= 1)
        }
    }
}
