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
        let presentation = StoryStagePresentation(scene: .supermarket, segment: line)
        #expect(presentation.area == .general)
        #expect(presentation.action == .think)
    }

    @Test
    func openingOldRepliesAndUnknownHintsHaveSafeDefaults() throws {
        #expect(StoryStagePresentation(scene: .supermarket, segment: nil).action == .greet)
        #expect(try StoryStagePresentation(scene: .supermarket, segment: self.segment(speaker: "you"))
            .action == .listen)
        let unknown = try self.segment("{\"areaId\":\"frozen\",\"moiraAction\":\"dance\"}")
        #expect(StoryStagePresentation(scene: .supermarket, segment: unknown).area == .general)
        #expect(StoryStagePresentation(scene: .supermarket, segment: unknown).action == .think)
    }

    @Test
    func validCueFieldsSurviveIndependently() throws {
        let line = try self.segment("{\"areaId\":42,\"moiraAction\":\"hold_apple\"}")
        #expect(StoryStagePresentation(scene: .supermarket, segment: line).area == .general)
        #expect(StoryStagePresentation(scene: .supermarket, segment: line).action == .holdApple)
        let second = try self.segment("{\"areaId\":\"checkout\",\"moiraAction\":42}")
        #expect(StoryStagePresentation(scene: .supermarket, segment: second).area == .checkout)
        #expect(StoryStagePresentation(scene: .supermarket, segment: second).action == .think)
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
        #expect(StoryStagePresentation(scene: .supermarket, segment: line).action == .listen)
    }

    @Test
    func everyPresentationHasBundledArtworkAndUsableGrounding() {
        for scene in StoryStagePresentation.Scene.allCases {
            for area in scene.areas {
                #expect(UIImage(named: "story-\(scene.rawValue)-\(area.rawValue)") != nil)
            }
        }
        for action in StoryStagePresentation.Action.allCases {
            #expect(UIImage(named: action.imageName) != nil)
            let bounds = StorySpriteMetrics.bounds(for: action)
            #expect(bounds.top >= 0 && bounds.top < bounds.bottom && bounds.bottom <= 1)
            #expect(bounds.left >= 0 && bounds.left < bounds.right && bounds.right <= 1)
        }
    }

    @Test(arguments: StoryStagePresentation.Scene.allCases)
    func eachPlaceResolvesItsOwnAreasAndProps(_ scene: StoryStagePresentation.Scene) throws {
        for area in scene.areas {
            for action in scene.actions {
                let line = try self.segment("{\"areaId\":\"\(area.rawValue)\",\"moiraAction\":\"\(action.rawValue)\"}")
                let state = StoryStagePresentation(scene: scene, segment: line)
                #expect(state.area == area)
                #expect(state.action == action)
                #expect(state.backgroundImageName == "story-\(scene.rawValue)-\(area.rawValue)")
            }
        }
        for area in StoryStagePresentation.Area.allCases where !scene.areas.contains(area) {
            let line = try self.segment("{\"areaId\":\"\(area.rawValue)\",\"moiraAction\":\"listen\"}")
            let state = StoryStagePresentation(scene: scene, segment: line)
            #expect(state.area == .general)
            #expect(state.action == .listen)
        }
        for action in StoryStagePresentation.Action.allCases where !scene.actions.contains(action) {
            let line = try self.segment(
                "{\"areaId\":\"general\",\"moiraAction\":\"\(action.rawValue)\"}",
                speaker: "you"
            )
            #expect(StoryStagePresentation(scene: scene, segment: line).action == .listen)
        }
        #expect(StoryStagePresentation(scene: scene, segment: nil).action == .greet)
    }
}
