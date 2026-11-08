// The register or ordering screen a screen question shows, as the scene JSON
// writes it. Drawn by the app rather than photographed: every chain's machine
// looks different, so a photo of one would teach that one (場面練習方案 §4).
//
// Each button names the question's choice it answers, so a tap on 「クレジット」
// answers choice `credit`. `SceneContentTests` holds every screen's buttons to
// its question's choices.

import Foundation

nonisolated struct ScreenMock: Hashable, Decodable {
    struct Button: Hashable, Decodable {
        /// The `SceneChoice.id` this button answers.
        let choiceId: String
        let ja: String
    }

    /// What the screen says across its top, in Japanese as the machine would.
    let heading: String
    /// A line under the heading, such as the total.
    let detail: String?
    /// In the order the screen lays them out.
    let buttons: [Button]

    func label(for choiceId: String) -> String? {
        self.buttons.first { $0.choiceId == choiceId }?.ja
    }
}
