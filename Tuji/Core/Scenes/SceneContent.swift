// 場面練習's content, decoded from the bundled `Resources/Scenes/<id>.json`.
//
// The JSON is shared with the audio pipeline (scene-contract.md), so its shape is
// flat: a phrasing carries `text`, `voice` and `audio` side by side, each nullable.
// Decoding folds those three into one optional `SpokenLine`, so "a voice with no
// text" fails to load instead of reaching a screen that would have to guess.
//
// The top-level type is `PracticeScene`, not `Scene`: a `Scene` in this module
// would shadow SwiftUI's, and `TujiApp.body` is `some Scene`.

import Foundation

nonisolated struct SceneID: RawRepresentable, Hashable, Codable, CodingKeyRepresentable {
    let rawValue: String
}

nonisolated struct SceneQuestionID: RawRepresentable, Hashable, Codable, CodingKeyRepresentable {
    let rawValue: String
}

nonisolated struct PhrasingID: RawRepresentable, Hashable, Codable, CodingKeyRepresentable {
    let rawValue: String
}

/// Copy written for the three content languages. A Japanese interface reads the
/// English: nobody using Tuji in Japanese is learning to understand a Japanese clerk.
nonisolated struct LocalizedText: Hashable, Decodable {
    let zhHant: String
    let zhHans: String
    let en: String

    private enum CodingKeys: String, CodingKey {
        case zhHant = "zh-Hant"
        case zhHans = "zh-Hans"
        case en
    }

    func resolved(_ language: UILanguage) -> String {
        switch language {
        case .zhHant: self.zhHant
        case .zhHans: self.zhHans
        case .en, .ja: self.en
        }
    }

    var all: [String] {
        [self.zhHant, self.zhHans, self.en]
    }
}

nonisolated enum SceneAccess: String, Decodable {
    case free
    case lifetime
}

nonisolated struct PracticeScene: Identifiable, Hashable, Decodable {
    let schemaVersion: Int
    let id: SceneID
    let revision: Int
    let access: SceneAccess
    let title: LocalizedText
    let summary: LocalizedText
    let questions: [SceneQuestion]
}

nonisolated struct SceneQuestion: Identifiable, Hashable, Decodable {
    enum Kind: String, Decodable {
        /// Play a phrasing, pick what it means.
        case listening
        /// Look at a register or ordering screen, tap the button to press.
        case screen
    }

    let id: SceneQuestionID
    let kind: Kind
    let goal: LocalizedText
    let phrasings: [Phrasing]
    let choices: [SceneChoice]
    let response: SceneResponse
    let explanation: LocalizedText
    let wordIds: [String]

    /// The one phrasing first practice uses.
    var firstPhrasing: Phrasing? {
        self.phrasings.first { $0.role == .first }
    }

    func phrasing(_ id: PhrasingID) -> Phrasing? {
        self.phrasings.first { $0.id == id }
    }
}

/// One recorded line: what is said, by which TTS voice, in which bundled file.
nonisolated struct SpokenLine: Hashable {
    let text: String
    let voice: String
    let audio: String
}

nonisolated struct Phrasing: Identifiable, Hashable, Decodable {
    enum Role: String, Decodable {
        case first
        case review
    }

    enum Speaker: String, Decodable {
        case clerk
        case register
        case screen
    }

    enum Speed: String, Decodable {
        case normal
        case fast
    }

    let id: PhrasingID
    let role: Role
    let speaker: Speaker
    let speed: Speed
    let ambience: Bool
    /// Nil only for a screen shown with nothing said over it.
    let spoken: SpokenLine?
    let screen: ScreenMock?

    /// Review prefers these: the version furthest from the clear first practice.
    var isHardest: Bool {
        self.speed == .fast && self.ambience
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, speaker, text, voice, speed, ambience, screen, audio
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(PhrasingID.self, forKey: .id)
        self.role = try c.decode(Role.self, forKey: .role)
        self.speaker = try c.decode(Speaker.self, forKey: .speaker)
        self.speed = try c.decode(Speed.self, forKey: .speed)
        self.ambience = try c.decode(Bool.self, forKey: .ambience)
        self.screen = try c.decodeIfPresent(ScreenMock.self, forKey: .screen)
        let text = try c.decodeIfPresent(String.self, forKey: .text)
        let voice = try c.decodeIfPresent(String.self, forKey: .voice)
        let audio = try c.decodeIfPresent(String.self, forKey: .audio)
        switch (text, voice, audio) {
        case let (text?, voice?, audio?):
            self.spoken = SpokenLine(text: text, voice: voice, audio: audio)
        case (nil, nil, nil):
            self.spoken = nil
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .text,
                in: c,
                debugDescription: "\(self.id.rawValue): text, voice and audio must be all set or all null"
            )
        }
    }
}

nonisolated struct SceneChoice: Identifiable, Hashable, Decodable {
    /// Unique within its question. On a screen question it also names the
    /// button its `ScreenMock` draws for it.
    let id: String
    let text: LocalizedText
    let correct: Bool
}

nonisolated struct SceneResponse: Hashable, Decodable {
    /// What to say, or the label of the button to press.
    let ja: String
    /// Nil when the answer is a button press with nothing to say.
    let clip: Clip?

    struct Clip: Hashable {
        let audio: String
        let voice: String
    }

    private enum CodingKeys: String, CodingKey {
        case ja, audio, voice
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.ja = try c.decode(String.self, forKey: .ja)
        let audio = try c.decodeIfPresent(String.self, forKey: .audio)
        let voice = try c.decodeIfPresent(String.self, forKey: .voice)
        switch (audio, voice) {
        case let (audio?, voice?): self.clip = Clip(audio: audio, voice: voice)
        case (nil, nil): self.clip = nil
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .audio,
                in: c,
                debugDescription: "response audio and voice must be both set or both null"
            )
        }
    }
}
