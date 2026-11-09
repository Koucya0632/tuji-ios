// The immersive staging of a 場面 (SCENE_PRACTICE_IMMERSIVE_DESIGN.md): a
// photo background says where the traveller is, props sit on the counter,
// and each 問句 is answered by doing something. A listening 問句 offers short
// replies to say; a screen 問句 hands over a working machine.
//
// It lives in the scene's own JSON beside the questions it stages, keyed by
// question id, so progress keeps keying on the same ids.

import CryptoKit
import Foundation

nonisolated struct SceneStage: Hashable, Decodable {
    /// The trips through this place. The first that is not optional is the
    /// one first practice takes.
    let routes: [StageRoute]
    /// Keyed by question id.
    let steps: [String: StageStep]

    var defaultRoute: StageRoute? {
        self.routes.first { !$0.isOptional } ?? self.routes.first
    }

    func route(_ id: String?) -> StageRoute? {
        id.flatMap { id in self.routes.first { $0.id == id } }
    }
}

/// One trip: why the traveller is here, and the 問句 they meet, in order. A
/// meal-ticket shop skips table ordering; buying beer adds the age check.
/// 問句 on a route not taken stay unpractised and are not counted as done.
nonisolated struct StageRoute: Hashable, Decodable, Identifiable {
    let id: String
    /// How the scene page names this trip.
    let title: LocalizedText
    /// What the traveller is here to do, said before anything plays.
    let intent: LocalizedText
    /// The button that walks in and starts the first line.
    let enter: LocalizedText
    let questions: [SceneQuestionID]
    /// Practised only when chosen from the scene page.
    let optional: Bool?

    var isOptional: Bool {
        self.optional ?? false
    }
}

nonisolated struct StageStep: Hashable, Decodable {
    /// An asset catalog name.
    let background: String
    /// Props on the counter when the 問句 starts, by asset name.
    let props: [String]?
    /// A line about this moment, when the intent alone does not cover it
    /// ("this time there is a can of beer in the basket").
    let note: LocalizedText?
    let replies: [StageReply]?
    let machine: StageMachine?
    /// A paper slip on the counter: a ticket, a key sleeve, a receipt. Its
    /// Japanese is the paper's own and is shown as written.
    let card: StageCard?
}

nonisolated struct StageCard: Hashable, Decodable {
    let title: String
    let lines: [String]
}

/// A short thing to say back. `fits` says whether it fits this trip: a reply
/// that does not still shows what happens, then the traveller tries again. A
/// pure preference (a bag or not) has more than one that fits.
nonisolated struct StageReply: Hashable, Decodable, Identifiable {
    let id: String
    let ja: String
    let meaning: LocalizedText
    let fits: Bool
    /// What the traveller sees happen.
    let result: LocalizedText
    /// Props that appear as the result.
    let show: [String]?
    /// False for something done rather than said (taking the plate off the
    /// belt): it is shown by its meaning and not read aloud.
    let says: Bool?

    var isSpoken: Bool {
        self.says ?? true
    }

    /// Its clip's file name, named by the Japanese so every scene that uses
    /// the same reply shares one (`generate-scene-audio.mjs` names it alike).
    var clip: String {
        let digest = SHA256.hash(data: Data(self.ja.utf8)).map { String(format: "%02x", $0) }.joined()
        return "reply-\(digest.prefix(12)).mp3"
    }
}

nonisolated struct StageMachine: Hashable, Decodable {
    let kind: MachineKind
    let total: Int?
    let item: String?
    /// The 食券機's items or the kiosk's upgrades.
    let menu: [MachineMenuItem]?
    /// What the screen's title bar says, when not the machine's usual one.
    let brand: String?
    /// What finishing it should look like: a payment method's raw value, or
    /// `yes` for the age check. Absent, any finish counts.
    let expect: String?

    func makeMachine() -> SceneMachine {
        SceneMachine(kind: self.kind, total: self.total, item: self.item, menu: self.menu)
    }

    /// Whether this finish is the one the trip wanted.
    func fits(_ outcome: MachineOutcome) -> Bool {
        guard let expect else { return true }
        switch outcome {
        case let .paid(method, _): return method.rawValue == expect
        case let .age(answer): return answer == .yes && expect == "yes"
        case let .ticket(item, _): return item == expect
        case let .kioskOrder(option, _): return option == expect
        case .ordered: return true
        }
    }
}
