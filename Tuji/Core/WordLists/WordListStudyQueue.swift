import Foundation

/// A study queue drawn from one 個人詞表 — what `StudyLauncherView` asks when a
/// session starts from a list rather than from 首頁.
///
/// Never warm: the shared prefetch is keyed by mode and themes, and a list
/// session must not be served a queue built for 首頁 (or vice versa).
@MainActor
struct WordListStudyQueue: StudyQueueProviding {
    let listId: String
    var repository: WordListRepository = LiveWordListRepository.shared
    var dailyGoal: () -> Int = { SettingsStore.shared.current.dailyGoal }

    func take(mode _: StudyMode) -> [StudyQueueItem]? {
        nil
    }

    func fetch(mode: StudyMode) async throws -> [StudyQueueItem] {
        let response = try await self.repository.queue(listId: self.listId, mode: mode, limit: self.limit(for: mode))
        // One item per word, the same rule StudyQueueStore applies.
        var seen = Set<String>()
        return response.queue.filter { seen.insert($0.word.id).inserted }
    }

    /// New words follow the daily goal, as 學新字 on 首頁 does; a review batch
    /// is capped at the size 首頁 uses.
    func limit(for mode: StudyMode) -> Int {
        switch mode {
        case .new: max(1, self.dailyGoal())
        case .review: 30
        }
    }
}
