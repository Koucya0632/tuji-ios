// 情境故事 — what the person has picked so far, and the one paid step at the end.
//
// The order on screen is the order of the decision: 圖鑑物品 → 場地 → 情景
// → 難度 → 生成. A situation can be picked before a place: the server gives
// every place the same ones today, so they are offered from the start, and a
// place that lacks the picked one clears it. A story is written only when the
// person taps the button that says what it costs; nothing here spends points
// on its own.
//
// The story arrives in pieces: the page is the story's from the tap, `story`
// fills in once its title and intro exist, and `writing` stays `.writing`
// while the segments come in. A failure leaves what arrived on the page —
// or, when nothing did, the choices with the reason — charged nothing.

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
    /// Whether `offer.available` was read for this account since launch. One
    /// remembered from an earlier launch shows the choices but cannot say
    /// whether a story can be paid for.
    private(set) var balanceKnown = false
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
    private let offerCache: StoryOfferCache
    private let dictionary: LocalDictionaryReading
    private let language: LanguageContext
    private let makeRequestId: @MainActor () -> String
    private let isBlocked: @MainActor (String?) -> Bool
    /// One id per set of choices, reused when the same choices are sent again.
    private var pending: (payload: StoryPayload, requestId: String)?
    /// The write in flight, so leaving the story stops it.
    private var writeTask: Task<Void, Never>?

    init(
        repository: AssistantStoryWriting = LiveAssistantStoryRepository(),
        offerCache: StoryOfferCache = .shared,
        dictionary: LocalDictionaryReading = WordsStore.shared,
        language: LanguageContext = SettingsStore.shared,
        makeRequestId: @escaping @MainActor () -> String = { UUID().uuidString.lowercased() },
        isBlocked: @escaping @MainActor (String?) -> Bool = { BlockStore.shared.isBlocked($0) }
    ) {
        self.repository = repository
        self.offerCache = offerCache
        self.dictionary = dictionary
        self.language = language
        self.makeRequestId = makeRequestId
        self.isBlocked = isBlocked
    }

    // MARK: - 選項

    /// Changes when the kept balance stops being trusted; the page loads again on it.
    var offerRevision: Int {
        self.offerCache.revision
    }

    /// Shows the kept offer at once, when there is one. Entering does not read
    /// the balance again when this launch already has it.
    func loadOffer() async {
        guard self.offerPhase != .loading else { return }
        if let entry = self.offerCache.entry(uiLanguage: self.uiLanguage) {
            self.offer = entry.offer
            self.balanceKnown = entry.current
            self.offerPhase = .loaded
            if entry.current { return }
        }
        self.offerPhase = self.offerPhase.reloading
        do {
            self.offer = try await self.offerCache.load(uiLanguage: self.uiLanguage, using: self.repository)
            self.balanceKnown = true
            self.offerPhase = .loaded
        } catch {
            // Choices without a balance cannot be acted on: say it failed.
            self.offerPhase = self.balanceKnown ? .loaded : .failed
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

    /// What can happen at the chosen place, or before one is chosen, every
    /// situation any place offers, in the order first offered.
    var situations: [StoryOffer.Situation] {
        if let scene { return scene.situations }
        var seen = Set<String>()
        return (self.offer?.scenes ?? []).flatMap(\.situations).filter { seen.insert($0.id).inserted }
    }

    func chooseScene(_ id: String) {
        guard id != self.sceneId else { return }
        self.sceneId = id
        if let situationId, !self.situations.contains(where: { $0.id == situationId }) {
            self.situationId = nil
        }
        self.choicesChanged()
    }

    func chooseSituation(_ id: String) {
        guard self.situations.contains(where: { $0.id == id }) else { return }
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
        guard self.balanceKnown, let offer else { return false }
        return offer.available >= offer.maxPoints
    }

    var canWrite: Bool {
        self.isComplete && self.canAfford && self.writing != .writing
    }

    /// The button's way in: a write the page can stop by leaving.
    func start() {
        guard self.canWrite else { return }
        self.writeTask = Task { await self.write() }
    }

    func write() async {
        guard self.canWrite, let payload = self.payload() else { return }
        self.writing = .writing
        let language = self.language.learningDirection.targetLanguage
        do {
            let events = try await self.repository.writeStory(payload)
            for try await event in events {
                switch event {
                case let .opening(title, intro):
                    self.storyLanguage = language
                    self.story = Story(title: title, intro: intro, segments: [], wordNotes: nil)
                case let .segment(segment):
                    self.story?.segments.append(segment)
                case let .done(result):
                    self.finish(result)
                    return
                }
            }
            // Left on purpose: `stop()` already reset everything.
            if Task.isCancelled { return }
            // The answer ended without the whole story.
            self.writing = .failed(.failed)
            await self.refreshBalance()
        } catch {
            if Task.isCancelled { return }
            self.writing = .failed(self.failure(for: error))
            await self.refreshBalance()
        }
    }

    /// A failure does not say what is left, and some are charged. The choices
    /// stay as they are; if this read fails too, the server still checks the
    /// balance before it charges.
    private func refreshBalance() async {
        guard let offer = try? await self.offerCache.load(uiLanguage: self.uiLanguage, using: self.repository)
        else { return }
        self.offer = offer
        self.balanceKnown = true
    }

    private func finish(_ result: StoryResult) {
        self.pending = nil
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
        if let offer {
            self.balanceKnown = true
            self.offerCache.store(offer, uiLanguage: self.uiLanguage)
        }
    }

    /// Back to the choices, kept as they were, for another story. A story
    /// still being written is stopped; the server finishes and charges it as
    /// it would a lost answer, so the next tap is a new request.
    func closeStory() {
        self.stop()
        self.story = nil
    }

    /// Leaving the page: drop a write in flight.
    func stop() {
        guard let writeTask else { return }
        writeTask.cancel()
        self.writeTask = nil
        if self.writing == .writing {
            self.writing = .idle
            self.pending = nil
            // The server finishes it and charges it: the kept balance is behind.
            self.offerCache.balanceChanged()
        }
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
        case let interrupted as StoryInterrupted where interrupted.code == "rate_limited":
            .busy
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
