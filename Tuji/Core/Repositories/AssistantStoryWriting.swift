// 情境故事 — 助手's second paid step, tuji-web `/api/assistant/story`.
//
// The person picks one to three 圖鑑 items, a place, what is happening there
// and a difficulty; a model writes a short scene between Moira, the cat, and them. The
// server owns the list of places and levels (labelled in the interface
// language), charges a story what its tokens cost — `minPoints`–`maxPoints` is
// only the typical range, and `maxPoints` the balance a story needs to start —
// and charges nothing for a story it cannot deliver.

import Foundation

/// The choices, the price range and the balance, read before anything is picked.
struct StoryOffer: Decodable, Equatable {
    struct Situation: Decodable, Equatable, Identifiable {
        let id: String
        let label: String
    }

    struct Scene: Decodable, Equatable, Identifiable {
        let id: String
        let label: String
        let situations: [Situation]
    }

    struct Level: Decodable, Equatable, Identifiable {
        let id: String
        let label: String
        /// One line under the label: what the difficulty means.
        let hint: String
    }

    /// The typical range, said before the tap. Not a cap: a story is charged
    /// what it cost.
    let minPoints: Int
    /// Also the balance a story needs to start.
    let maxPoints: Int
    let available: Int
    let scenes: [Scene]
    let levels: [Level]
}

struct StoryPayload: Encodable, Equatable {
    /// Kept across a resend of the same choices: the server charges a request
    /// id once, so a retry after a lost response is not a second charge.
    let requestId: String
    let uiLanguage: String
    let learningDirection: String
    /// Catalogue ids or `atlas:<uuid>`. The server reads the entries itself.
    let wordIds: [String]
    let sceneId: String
    let situationId: String
    let levelId: String
}

struct Story: Decodable, Equatable {
    struct Segment: Decodable, Equatable {
        enum Speaker: String, Decodable {
            case narrator, cat, you
        }

        let speaker: Speaker
        /// Narration in the interface language; a spoken line in the language
        /// being learned.
        let text: String
        /// Japanese lines only: kana over each kanji run.
        let furigana: [FuriganaSegment]?
        /// Japanese lines only, when there is no `furigana`: the whole line in kana.
        let reading: String?
        /// Spoken lines only, and only when the interface language is not the
        /// one being learned.
        let translation: String?
        /// Picked items this segment uses.
        let wordIds: [String]
    }

    struct WordNote: Decodable, Equatable {
        let id: String
        /// What the word means, in the language being learned.
        let note: String
    }

    let title: String
    let intro: String
    let segments: [Segment]
    /// Only when the interface language is the one being learned: a
    /// translation would repeat each line, so the picked words are explained.
    let wordNotes: [WordNote]?
}

struct StoryResult: Decodable, Equatable {
    let story: Story
    let charged: Int
    let available: Int
    let minPoints: Int
    let maxPoints: Int
}

@MainActor
protocol AssistantStoryWriting {
    func storyOffer(uiLanguage: String) async throws -> StoryOffer
    func writeStory(_ payload: StoryPayload) async throws -> StoryResult
}

@MainActor
struct LiveAssistantStoryRepository: AssistantStoryWriting {
    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func storyOffer(uiLanguage: String) async throws -> StoryOffer {
        try await self.api.get(.assistantStoryOffer(uiLanguage: uiLanguage))
    }

    func writeStory(_ payload: StoryPayload) async throws -> StoryResult {
        try await self.api.post(.assistantStory, body: payload)
    }
}
