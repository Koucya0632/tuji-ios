import Foundation

/// A study queue drawn from one 景點 — what `StudyLauncherView` asks when a
/// session starts from a spot page.
///
/// Never warm, for the reason `WordListStudyQueue` gives: the shared prefetch
/// is keyed by mode and themes, and a spot session must not be served a queue
/// built for 今天.
@MainActor
struct SpotStudyQueue: StudyQueueProviding {
    let spotId: String
    var repository: TravelRepository = LiveTravelRepository.shared

    func take(mode _: StudyMode) -> [StudyQueueItem]? {
        nil
    }

    func fetch(mode: StudyMode) async throws -> [StudyQueueItem] {
        let response = try await self.repository.queue(spotId: self.spotId, mode: mode, limit: Self.limit)
        // One item per word, the same rule StudyQueueStore applies.
        var seen = Set<String>()
        return response.queue.filter { seen.insert($0.word.id).inserted }
    }

    /// A spot is a handful of words, learned in one sitting — the daily goal
    /// that paces 今天 would split eight words over several visits.
    static let limit = 30
}
