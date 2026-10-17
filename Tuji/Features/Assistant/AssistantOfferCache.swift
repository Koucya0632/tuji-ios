// AI 查詞 and AI 語法 — the offer, kept so entering the page does not ask the
// server for the balance again.
//
// One read per launch: 助手 or the page itself, whichever comes first, and the
// two share one request. After that the balance is read again only when it is
// known to have moved — a card was generated or refused (the page asks), or a
// purchase was delivered (`balanceChanged`). The last answer is also kept on
// disk, so the first visit after a launch shows the prices at once; what comes
// off the disk is not `current`, so the page shows it but does not let it decide
// whether a card can be paid for.
//
// The balance can still move elsewhere (another feature spending, the monthly
// grant) without this cache hearing of it. The server checks the balance before
// it charges, and a refusal reads it again here, so nothing is overspent.
//
// Unlike the story offer these carry no interface-language labels, so there is
// one entry per cache, tagged with the account it was read for.

import Foundation

/// The type-safe face. A struct on purpose: Swift 6.3.3 crashes in
/// `EarlyPerfInliner` on a *generic* class's `deinit` under the release build's
/// `-O -whole-module-optimization` (see `LoadFlights`), so the class that owns
/// the state, `OfferShelf`, has no type parameter and keeps the offer as JSON.
@MainActor
struct AssistantOfferCache<Offer: Codable & Equatable> {
    struct Entry: Equatable {
        let offer: Offer
        /// Read from the server since launch: its balance can be trusted.
        let current: Bool
    }

    private let shelf: OfferShelf

    /// Not private: a test that shares a live cache would leak into the next one.
    init(defaultsKey: String, defaults: UserDefaults = .standard) {
        self.shelf = OfferShelf(defaultsKey: defaultsKey, defaults: defaults)
    }

    /// Bumped when the kept balance stops being trusted, so an open page knows
    /// to read it again.
    var revision: Int {
        self.shelf.revision
    }

    func entry(owner: String) -> Entry? {
        guard let kept = self.shelf.entry(owner: owner),
              let offer = try? JSONDecoder().decode(Offer.self, from: kept.data)
        else { return nil }
        return Entry(offer: offer, current: kept.current)
    }

    /// Asks the server, or joins the ask already on its way for the same account.
    func load(owner: String, using fetch: @escaping @MainActor () async throws -> Offer) async throws -> Offer {
        let data = try await self.shelf.load(owner: owner) { try await JSONEncoder().encode(fetch()) }
        return try JSONDecoder().decode(Offer.self, from: data)
    }

    /// For a page that leads to the feature: reads only what is not already in
    /// hand. A failure is left for the feature's own page to meet and explain.
    func prefetch(owner: String?, using fetch: @escaping @MainActor () async throws -> Offer) async {
        guard let owner, self.entry(owner: owner)?.current != true else { return }
        _ = try? await self.load(owner: owner, using: fetch)
    }

    /// Points were bought or a membership began: the kept balance is behind.
    func balanceChanged() {
        self.shelf.balanceChanged()
    }

    func reset() {
        self.shelf.reset()
    }
}

/// The state behind `AssistantOfferCache`, with the offer as encoded JSON.
@MainActor
@Observable
private final class OfferShelf {
    struct Kept {
        let data: Data
        let current: Bool
    }

    private struct Remembered: Codable {
        let owner: String
        let offer: Data
    }

    /// One read on its way. Its task returns nothing: the answer stays on the
    /// main actor, in `result`.
    private final class Ask {
        let owner: String
        var task: Task<Void, Never>?
        var result: Result<Data, Error>?
        init(owner: String) {
            self.owner = owner
        }
    }

    private(set) var revision = 0
    @ObservationIgnored private let defaultsKey: String
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var read: Remembered?
    /// The balance in `read` has moved since it was read.
    @ObservationIgnored private var stale = false
    @ObservationIgnored private var inFlight: Ask?
    /// Bumped by `reset`, so an answer that lands after a sign-out is dropped.
    @ObservationIgnored private var generation = 0

    init(defaultsKey: String, defaults: UserDefaults) {
        self.defaultsKey = defaultsKey
        self.defaults = defaults
    }

    func entry(owner: String) -> Kept? {
        if let read = self.read, read.owner == owner {
            return Kept(data: read.offer, current: !self.stale)
        }
        guard let data = self.defaults.data(forKey: self.defaultsKey),
              let remembered = try? JSONDecoder().decode(Remembered.self, from: data),
              remembered.owner == owner
        else { return nil }
        return Kept(data: remembered.offer, current: false)
    }

    func load(owner: String, using fetch: @escaping @MainActor () async throws -> Data) async throws -> Data {
        if let ask = self.inFlight, ask.owner == owner {
            await ask.task?.value
            guard let result = ask.result else { throw CancellationError() }
            return try result.get()
        }
        let ask = Ask(owner: owner)
        let generation = self.generation
        self.inFlight = ask
        ask.task = Task {
            do { ask.result = try await .success(fetch()) }
            catch { ask.result = .failure(error) }
        }
        await ask.task?.value
        guard generation == self.generation, let result = ask.result else { throw CancellationError() }
        if self.inFlight === ask { self.inFlight = nil }
        let data = try result.get()
        self.store(data, owner: owner)
        return data
    }

    func balanceChanged() {
        guard self.read != nil else { return }
        self.stale = true
        self.revision += 1
    }

    private func store(_ offer: Data, owner: String) {
        let remembered = Remembered(owner: owner, offer: offer)
        self.read = remembered
        self.stale = false
        self.defaults.set(try? JSONEncoder().encode(remembered), forKey: self.defaultsKey)
    }

    func reset() {
        self.generation += 1
        self.read = nil
        self.stale = false
        self.inFlight?.task?.cancel()
        self.inFlight = nil
        self.defaults.removeObject(forKey: self.defaultsKey)
    }
}

@MainActor
enum AssistantOfferCaches {
    static let vocabulary = AssistantOfferCache<VocabularyOffer>(defaultsKey: "tuji.vocabulary.offer.v1")
    static let grammar = AssistantOfferCache<GrammarOffer>(defaultsKey: "tuji.grammar.offer.v1")

    static func balanceChanged() {
        self.vocabulary.balanceChanged()
        self.grammar.balanceChanged()
    }
}
