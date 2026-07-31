// One policy boundary for reconciling client learning data after a confirmed
// community-atlas mutation. Mutations remain successful even when WordsStore's
// best-effort reload records an internal error.

import Foundation

@MainActor
protocol CommunityLearningRefreshing {
    func refreshAfterLearningMutation() async
}

/// Stateless live adapter. It deliberately has no shared lifecycle of its own;
/// only this boundary knows which existing app stores implement the policy.
@MainActor
struct LiveCommunityLearningRefresher: CommunityLearningRefreshing {
    private let invalidateQueue: @MainActor () -> Void
    private let reloadWords: @MainActor () async -> Void

    init(
        invalidateQueue: @escaping @MainActor () -> Void = {
            StudyQueueStore.shared.invalidate()
        },
        reloadWords: @escaping @MainActor () async -> Void = {
            await WordsStore.shared.reload()
        }
    ) {
        self.invalidateQueue = invalidateQueue
        self.reloadWords = reloadWords
    }

    func refreshAfterLearningMutation() async {
        self.invalidateQueue()
        await self.reloadWords()
    }
}
