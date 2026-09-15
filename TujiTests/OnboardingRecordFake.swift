import Foundation
@testable import Tuji

/// Stands in for `OnboardingState.shared`, which `SettingsStore` reached from
/// inside four methods before it was injected — so a settings test wrote the
/// real device's first-run answers.
@MainActor
final class OnboardingRecordFake: OnboardingRecord {
    private(set) var learningDirection: LearningDirection?
    private(set) var recorded: [LearningDirection] = []
    var setupDoneUsers: Set<UUID> = []

    init(learningDirection: LearningDirection? = nil) {
        self.learningDirection = learningDirection
    }

    func recordLearningDirection(_ direction: LearningDirection) {
        self.recorded.append(direction)
        self.learningDirection = direction
    }

    func setupDone(for userId: UUID) -> Bool {
        self.setupDoneUsers.contains(userId)
    }
}
