// 情境故事 — the offer, kept so the page opens on its choices instead of a
// loading bar.
//
// 助手 asks for it as it appears, so by the time 情境故事 is tapped it has
// usually arrived; the page asks again either way and the two share one
// request. The last one is also kept on disk, so even the first visit after a
// launch shows the places and levels at once. What comes off the disk is not
// `current`: its balance belonged to an earlier read, maybe another account's,
// so the page does not let it decide whether a story can be paid for.

import Foundation

@MainActor
final class StoryOfferCache {
    static let shared = StoryOfferCache()

    struct Entry: Equatable {
        let offer: StoryOffer
        /// Read from the server since launch, for this account: its balance
        /// can be trusted.
        let current: Bool
    }

    private static let defaultsKey = "tuji.story.offer.v1"

    private let defaults: UserDefaults
    /// By interface language: the labels are in it.
    private var read: [String: StoryOffer] = [:]
    private var inFlight: [String: Task<StoryOffer, Error>] = [:]
    /// Bumped by `reset`, so an answer that lands after a sign-out is dropped.
    private var generation = 0

    /// Not private: a test that shares `.shared` would leak into the next one.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func entry(uiLanguage: String) -> Entry? {
        if let offer = self.read[uiLanguage] {
            return Entry(offer: offer, current: true)
        }
        guard let data = self.remembered[uiLanguage],
              let offer = try? JSONDecoder().decode(StoryOffer.self, from: data) else { return nil }
        return Entry(offer: offer, current: false)
    }

    /// Asks the server, or joins the ask already on its way.
    func load(uiLanguage: String, using repository: AssistantStoryWriting) async throws -> StoryOffer {
        if let task = self.inFlight[uiLanguage] {
            return try await task.value
        }
        let task = Task { try await repository.storyOffer(uiLanguage: uiLanguage) }
        let generation = self.generation
        self.inFlight[uiLanguage] = task
        let result = await task.result
        guard generation == self.generation else { throw CancellationError() }
        self.inFlight[uiLanguage] = nil
        let offer = try result.get()
        self.store(offer, uiLanguage: uiLanguage)
        return offer
    }

    /// For a page that leads to 情境故事. A failure is left for the story page
    /// to meet and explain.
    func prefetch(uiLanguage: String, using repository: AssistantStoryWriting = LiveAssistantStoryRepository()) async {
        _ = try? await self.load(uiLanguage: uiLanguage, using: repository)
    }

    /// A written story comes back with the balance after it.
    func store(_ offer: StoryOffer, uiLanguage: String) {
        self.read[uiLanguage] = offer
        var remembered = self.remembered
        remembered[uiLanguage] = try? JSONEncoder().encode(offer)
        self.defaults.set(remembered, forKey: Self.defaultsKey)
    }

    func reset() {
        self.generation += 1
        self.read = [:]
        self.inFlight.values.forEach { $0.cancel() }
        self.inFlight = [:]
        self.defaults.removeObject(forKey: Self.defaultsKey)
    }

    private var remembered: [String: Data] {
        self.defaults.dictionary(forKey: Self.defaultsKey) as? [String: Data] ?? [:]
    }
}
