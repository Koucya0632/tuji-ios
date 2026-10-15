// 情境故事 — what the person has picked so far, and the one paid step at the end.
//
// The order on screen is the order of the decision: 圖鑑物品 → 場地 → 場地情況
// → 難度 → 生成. Changing a place clears the situation, because situations
// belong to a place. A story is written only when the person taps the button
// that says what it costs; nothing here spends points on its own.

import Foundation
import Observation

@MainActor
@Observable
final class StoryBuilderModel {
    /// The server's limit.
    static let maxItems = 3

    /// Why the last attempt did not produce a story. Every case charged nothing.
    enum Failure: Equatable {
        case insufficientPoints
        case busy
        case offline
        /// Not a 罐頭點數 account, the feature is off, or signed out.
        case unavailable
        /// A picked card is gone or no longer matches the language being learned.
        case itemsChanged
        /// The model failed, or wrote a story that left out a picked item.
        case failed
    }

    enum Writing: Equatable {
        case idle
        case writing
        case failed(Failure)
    }

    private(set) var offerPhase: LoadPhase = .idle
    private(set) var offer: StoryOffer?
    private(set) var picked: [CardWord] = []
    private(set) var sceneId: String?
    private(set) var situationId: String?
    private(set) var levelId: String?
    private(set) var writing: Writing = .idle
    private(set) var story: Story?
    /// The language the story's spoken lines are in — the one being learned
    /// when it was asked for, so a direction changed since does not give its
    /// lines the wrong voice.
    private(set) var storyLanguage: TargetLanguage = .en

    private let repository: AssistantStoryWriting
    private let dictionary: LocalDictionaryReading
    private let language: LanguageContext
    private let makeRequestId: @MainActor () -> String
    private let isBlocked: @MainActor (String?) -> Bool
    /// One id per set of choices, reused when the same choices are sent again.
    private var pending: (payload: StoryPayload, requestId: String)?

    init(
        repository: AssistantStoryWriting = LiveAssistantStoryRepository(),
        dictionary: LocalDictionaryReading = WordsStore.shared,
        language: LanguageContext = SettingsStore.shared,
        makeRequestId: @escaping @MainActor () -> String = { UUID().uuidString.lowercased() },
        isBlocked: @escaping @MainActor (String?) -> Bool = { BlockStore.shared.isBlocked($0) }
    ) {
        self.repository = repository
        self.dictionary = dictionary
        self.language = language
        self.makeRequestId = makeRequestId
        self.isBlocked = isBlocked
    }

    // MARK: - 選項

    func loadOffer() async {
        guard self.offerPhase != .loading else { return }
        self.offerPhase = self.offerPhase.reloading
        do {
            self.offer = try await self.repository.storyOffer(uiLanguage: self.uiLanguage)
            self.offerPhase = .loaded
        } catch {
            if self.offer == nil { self.offerPhase = .failed } else { self.offerPhase = .loaded }
        }
    }

    /// Items that can go into a story: the official dictionary, the person's
    /// own cards, and the 物見 cards they took in — except a blocked author's.
    /// Blocking leaves those in 圖鑑, but a story is new use of the work. A
    /// taken-down card never reaches the dictionary at all; the server checks
    /// both again, so a stale block list only costs a refused request.
    var candidates: [CardWord] {
        self.dictionary.words.filter {
            $0.id.savedCommunitySlug == nil || !self.isBlocked($0.authorHandle)
        }
    }

    func isPicked(_ word: CardWord) -> Bool {
        self.picked.contains { $0.id == word.id }
    }

    var canPickMore: Bool {
        self.picked.count < Self.maxItems
    }

    func toggle(_ word: CardWord) {
        if let index = self.picked.firstIndex(where: { $0.id == word.id }) {
            self.picked.remove(at: index)
        } else if self.canPickMore {
            self.picked.append(word)
        }
        self.choicesChanged()
    }

    var scene: StoryOffer.Scene? {
        self.offer?.scenes.first { $0.id == self.sceneId }
    }

    func chooseScene(_ id: String) {
        guard id != self.sceneId else { return }
        self.sceneId = id
        self.situationId = nil
        self.choicesChanged()
    }

    func chooseSituation(_ id: String) {
        guard self.scene?.situations.contains(where: { $0.id == id }) == true else { return }
        self.situationId = id
        self.choicesChanged()
    }

    func chooseLevel(_ id: String) {
        self.levelId = id
        self.choicesChanged()
    }

    // MARK: - 生成

    var isComplete: Bool {
        !self.picked.isEmpty && self.sceneId != nil && self.situationId != nil && self.levelId != nil
    }

    /// The ceiling, not the floor: the server refuses an account holding less
    /// than a story could cost.
    var canAfford: Bool {
        guard let offer else { return false }
        return offer.available >= offer.maxPoints
    }

    var canWrite: Bool {
        self.isComplete && self.canAfford && self.writing != .writing
    }

    func write() async {
        guard self.canWrite, let payload = self.payload() else { return }
        self.writing = .writing
        let language = self.language.learningDirection.targetLanguage
        do {
            let result = try await self.repository.writeStory(payload)
            self.pending = nil
            self.storyLanguage = language
            self.story = result.story
            self.writing = .idle
            self.offer = self.offer.map {
                StoryOffer(
                    minPoints: result.minPoints,
                    maxPoints: result.maxPoints,
                    available: result.available,
                    scenes: $0.scenes,
                    levels: $0.levels
                )
            }
        } catch {
            self.writing = .failed(self.failure(for: error))
        }
    }

    /// Back to the choices, kept as they were, for another story.
    func closeStory() {
        self.story = nil
    }

    private var uiLanguage: String {
        UILanguage(code: self.language.uiLang).rawValue
    }

    private func payload() -> StoryPayload? {
        guard let sceneId, let situationId, let levelId else { return nil }
        var payload = StoryPayload(
            requestId: "",
            uiLanguage: self.uiLanguage,
            learningDirection: self.language.learningDirection.rawValue,
            wordIds: self.picked.map(\.id),
            sceneId: sceneId,
            situationId: situationId,
            levelId: levelId
        )
        if let pending, pending.payload == payload {
            payload = payload.with(requestId: pending.requestId)
        } else {
            let requestId = self.makeRequestId()
            self.pending = (payload, requestId)
            payload = payload.with(requestId: requestId)
        }
        return payload
    }

    /// A new set of choices is a new request; an old failure no longer applies.
    private func choicesChanged() {
        if case .failed = self.writing { self.writing = .idle }
    }

    private func failure(for error: Error) -> Failure {
        switch error {
        case let APIError.conflict(reason, _) where reason == "insufficient_credits":
            .insufficientPoints
        case APIError.rateLimited:
            .busy
        case APIError.transport:
            .offline
        case APIError.forbidden, APIError.notFound, APIError.unauthorized:
            .unavailable
        case let APIError.server(status, _) where status == 400:
            .itemsChanged
        default:
            .failed
        }
    }
}

private extension StoryPayload {
    func with(requestId: String) -> StoryPayload {
        StoryPayload(
            requestId: requestId,
            uiLanguage: self.uiLanguage,
            learningDirection: self.learningDirection,
            wordIds: self.wordIds,
            sceneId: self.sceneId,
            situationId: self.situationId,
            levelId: self.levelId
        )
    }
}
