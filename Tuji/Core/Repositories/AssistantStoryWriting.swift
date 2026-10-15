// 情境故事 — 助手's second paid step, tuji-web `/api/assistant/story`.
//
// The person picks one to three 圖鑑 items, a place, what is happening there
// and a difficulty; a model writes a short scene between Moira, the cat, and them. The
// server owns the list of places and levels (labelled in the interface
// language), charges a story what its tokens cost — `minPoints`–`maxPoints` is
// only the typical range, and `maxPoints` the balance a story needs to start —
// and charges nothing for a story it cannot deliver. The story is streamed:
// the title and intro first, then each segment as the model finishes it, so
// reading starts seconds before the writing ends.

import Foundation

/// The choices, the price range and the balance, read before anything is picked.
struct StoryOffer: Codable, Equatable {
    struct Situation: Codable, Equatable, Identifiable {
        let id: String
        let label: String
    }

    struct Scene: Codable, Equatable, Identifiable {
        let id: String
        let label: String
        let situations: [Situation]
    }

    struct Level: Codable, Equatable, Identifiable {
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
    /// Grows while the story is being written.
    var segments: [Segment]
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

/// A story as it is written: the opening as soon as there is one, each
/// segment as it closes, then the whole story and what it cost.
enum StoryEvent: Equatable {
    case opening(title: String, intro: String)
    case segment(Story.Segment)
    case done(StoryResult)
}

/// The server stopped partway, after the story had started arriving. Its
/// `error` code; nothing was charged.
struct StoryInterrupted: Error, Equatable {
    let code: String
}

@MainActor
protocol AssistantStoryWriting {
    func storyOffer(uiLanguage: String) async throws -> StoryOffer
    /// Throws before the first event the way any request does; a failure
    /// after it ends the stream with `StoryInterrupted`.
    func writeStory(_ payload: StoryPayload) async throws -> AsyncThrowingStream<StoryEvent, Error>
}

/// One line of the streamed answer.
private struct StoryLine: Decodable {
    enum Kind: String, Decodable {
        case opening, segment, done, error
    }

    let type: Kind
    let title: String?
    let intro: String?
    let segment: Story.Segment?
    let error: String?
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

    func writeStory(_ payload: StoryPayload) async throws -> AsyncThrowingStream<StoryEvent, Error> {
        let lines = try await self.api.postLines(.assistantStory, body: payload)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await data in lines {
                        if let event = try Self.event(from: data) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// nil for a line this version does not know, so a new kind of line is
    /// skipped rather than fatal. A server that does not stream answers with
    /// the whole result in one body; that is the finished story.
    static func event(from data: Data) throws -> StoryEvent? {
        let decoder = JSONDecoder.tuji
        guard let line = try? decoder.decode(StoryLine.self, from: data) else {
            return (try? decoder.decode(StoryResult.self, from: data)).map(StoryEvent.done)
        }
        switch line.type {
        case .opening:
            guard let title = line.title, let intro = line.intro else { return nil }
            return .opening(title: title, intro: intro)
        case .segment:
            return line.segment.map(StoryEvent.segment)
        case .done:
            do {
                return try .done(decoder.decode(StoryResult.self, from: data))
            } catch {
                throw APIError.decoding(error)
            }
        case .error:
            throw StoryInterrupted(code: line.error ?? "assistant_unavailable")
        }
    }
}
