import Foundation

/// The slice of live study state `StudyQueueStore` folds into its queue params
/// and cache signature: the learning direction, the daily new-word goal, the
/// picked study categories, and the live `due` count. A narrow read seam over
/// settings + stats (per ADR-0001) so the cache-signature logic is testable with
/// a stub — e.g. asserting a direction switch busts a warm entry.
@MainActor
protocol StudyQueueInputs {
    var learningDirection: LearningDirection { get }
    var dailyGoal: Int { get }
    var studyCategories: [String] { get }
    var due: Int { get }
}

/// Live adapter reading the two stores the queue params depend on.
@MainActor
struct LiveStudyQueueInputs: StudyQueueInputs {
    var settings: SettingsStore = .shared
    var stats: StudyStatsStore = .shared

    var learningDirection: LearningDirection {
        self.settings.current.learningDirection
    }

    var dailyGoal: Int {
        self.settings.current.dailyGoal
    }

    var studyCategories: [String] {
        self.settings.current.studyCategories
    }

    var due: Int {
        self.stats.stats?.due ?? 0
    }
}
