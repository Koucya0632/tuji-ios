// The travel map, as last answered for one interface language and learning
// direction. Loaded when 物見 appears, not at launch: it is one screen's entry,
// and the app opens without it.
//
// An empty answer is an answer — it is what the server says to everyone not
// learning 日文, and what hides the entry. A failed load keeps whatever was
// shown and is asked again the next time 物見 appears.

import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class TravelStore {
    static let shared = TravelStore()

    private(set) var destinations: [TravelDestination] = []
    private(set) var phase: LoadPhase = .idle

    private let repository: TravelRepository
    private let log = Logger(subsystem: "app.tuji.ios", category: "travel")

    /// What `destinations` was loaded for; a different key means reload.
    @ObservationIgnored private var loadedKey: Key?
    /// The newest request. A slower, older one must not overwrite its answer.
    @ObservationIgnored private var wanted: Key?

    struct Key: Hashable {
        let lang: String
        let learning: String
    }

    init(repository: TravelRepository = LiveTravelRepository.shared) {
        self.repository = repository
    }

    func loadIfNeeded(settings: LanguageContext = SettingsStore.shared) async {
        let key = Key(lang: settings.contentLanguageCode, learning: settings.learningDirection.rawValue)
        guard self.loadedKey != key || self.phase != .loaded else { return }
        await self.load(key)
    }

    func reload(settings: LanguageContext = SettingsStore.shared) async {
        await self.load(Key(lang: settings.contentLanguageCode, learning: settings.learningDirection.rawValue))
    }

    private func load(_ key: Key) async {
        self.wanted = key
        // Another language's map is not this one's "old answer": drop it
        // rather than show Japanese names under an English interface.
        if self.loadedKey != key {
            self.destinations = []
            self.loadedKey = nil
            self.phase = .loading
        } else {
            self.phase = self.phase.reloading
        }
        do {
            let response = try await self.repository.destinations(lang: key.lang, learning: key.learning)
            guard self.wanted == key else { return }
            self.destinations = response.destinations
            self.loadedKey = key
            self.phase = .loaded
        } catch {
            guard self.wanted == key else { return }
            self.phase = self.phase.afterFailure
            self.log.error("travel load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func destination(_ id: String) -> TravelDestination? {
        self.destinations.first { $0.id == id }
    }

    func city(_ id: String, in destinationId: String) -> TravelCity? {
        self.destination(destinationId)?.city(id)
    }

    func spot(_ id: String) -> TravelSpot? {
        self.destinations.lazy.flatMap(\.cities).flatMap(\.spots).first { $0.id == id }
    }
}
