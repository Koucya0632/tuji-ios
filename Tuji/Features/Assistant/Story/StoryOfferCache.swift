// 情境故事 — the offer, kept so the page opens on its choices instead of a
// loading bar, and so entering it does not ask the server for the balance again.
//
// One read per launch and interface language: 助手 as it appears, or the page
// if it gets there first, and the two share one request. After that it is read
// again only when the balance is known to have moved — a purchase was delivered,
// or a story failed or was stopped (`balanceChanged`). A finished story brings
// its new balance with it. The last one is also kept on disk, so even the first
// visit after a launch shows the places and levels at once. What comes off the
// disk is not `current`: its balance belonged to an earlier read, maybe another
// account's, so the page does not let it decide whether a story can be paid for.

import Foundation

@MainActor
@Observable
final class StoryOfferCache {
    static let shared = StoryOfferCache()

    struct Entry: Equatable {
        let offer: StoryOffer
        /// Read from the server since launch, for this account: its balance
        /// can be trusted.
        let current: Bool
    }

    private static let defaultsKey = "tuji.story.offer.v1"

    /// Bumped when the kept balance stops being trusted, so an open page knows
    /// to read it again.
    private(set) var revision = 0
    @ObservationIgnored private let defaults: UserDefaults
    /// By interface language: the labels are in it.
    @ObservationIgnored private var read: [String: StoryOffer] = [:]
    /// The balance in `read` has moved since it was read.
    @ObservationIgnored private var stale = false
    @ObservationIgnored private var inFlight: [String: Task<StoryOffer, Error>] = [:]
    /// Bumped by `reset`, so an answer that lands after a sign-out is dropped.
    @ObservationIgnored private var generation = 0

    /// Not private: a test that shares `.shared` would leak into the next one.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func entry(uiLanguage: String) -> Entry? {
        if let offer = self.read[uiLanguage] {
            return Entry(offer: offer, current: !self.stale)
        }
        guard let data = self.remembered[uiLanguage],
              let offer = try? JSONDecoder().decode(StoryOffer.self, from: data)
        else { return nil }
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

    /// For a page that leads to 情境故事: reads only what is not already in
    /// hand. A failure is left for the story page to meet and explain.
    func prefetch(uiLanguage: String, using repository: AssistantStoryWriting = LiveAssistantStoryRepository()) async {
        guard self.entry(uiLanguage: uiLanguage)?.current != true else { return }
        _ = try? await self.load(uiLanguage: uiLanguage, using: repository)
    }

    /// The kept balance is behind: points were bought, or a story may have
    /// been charged without saying what is left.
    func balanceChanged() {
        guard !self.read.isEmpty else { return }
        self.stale = true
        self.revision += 1
    }

    /// A written story comes back with the balance after it. Another
    /// language's copy would hold an older balance, so only this one is kept.
    func store(_ offer: StoryOffer, uiLanguage: String) {
        self.stale = false
        self.read = [uiLanguage: offer]
        var remembered = self.remembered
        remembered[uiLanguage] = try? JSONEncoder().encode(offer)
        self.defaults.set(remembered, forKey: Self.defaultsKey)
    }

    func reset() {
        self.generation += 1
        self.read = [:]
        self.stale = false
        self.inFlight.values.forEach { $0.cancel() }
        self.inFlight = [:]
        self.defaults.removeObject(forKey: Self.defaultsKey)
    }

    private var remembered: [String: Data] {
        self.defaults.dictionary(forKey: Self.defaultsKey) as? [String: Data] ?? [:]
    }
}
