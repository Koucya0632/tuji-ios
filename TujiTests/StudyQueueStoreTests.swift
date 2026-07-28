// Pins the queue cache's dependence on live study state now that it reads
// through the injected StudyQueueInputs seam: a learning-direction switch must
// bust a warm entry (else the launcher would serve the previous language's
// queue within the TTL), while an unchanged context keeps it warm.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct StudyQueueStoreTests {
    @Test
    func directionSwitchBustsWarmEntry() async {
        let inputs = StubQueueInputs() // starts at .zhEn
        let store = StudyQueueStore(repository: StubQueueRepository(), inputs: inputs)

        // Warm the .new entry for the current direction.
        await store.prefetch(mode: .new)

        // Switching direction changes the signature, so the warm entry no longer
        // matches and take() must miss.
        inputs.learningDirection = .zhJa
        #expect(store.take(mode: .new) == nil)
    }

    @Test
    func unchangedContextKeepsWarmEntry() async {
        let inputs = StubQueueInputs()
        let store = StudyQueueStore(repository: StubQueueRepository(), inputs: inputs)
        await store.prefetch(mode: .new)
        // Nothing changed → the warm entry is served (control for the test above).
        #expect(store.take(mode: .new) != nil)
    }
}

@MainActor
private final class StubQueueInputs: StudyQueueInputs {
    var learningDirection: LearningDirection = .zhEn
    var dailyGoal: Int = 10
    var studyCategories: [String] = []
    var due: Int = 5
}

@MainActor
private struct StubQueueRepository: StudyRepository {
    struct NotImplemented: Error {}

    func loadQueue(mode _: StudyMode, limit _: Int, newCount _: Int, categories _: [String]) async throws
        -> StudyQueueResponse
    {
        StudyQueueResponse(queue: [], stats: nil)
    }

    func loadStats() async throws -> StudyStatsResponse {
        throw NotImplemented()
    }

    func submitAnswer(_: StudyAnswerPayload) async throws -> StudyAnswerResponse {
        throw NotImplemented()
    }

    func submitReport(_: StudyReportPayload) async throws {
        throw NotImplemented()
    }
}
