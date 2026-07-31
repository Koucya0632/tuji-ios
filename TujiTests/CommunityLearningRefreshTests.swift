import Testing
@testable import Tuji

@MainActor
struct CommunityLearningRefreshTests {
    @Test
    func livePolicyInvalidatesQueueBeforeReloadingWords() async {
        var calls: [String] = []
        let refresher = LiveCommunityLearningRefresher(
            invalidateQueue: {
                calls.append("invalidateQueue")
            },
            reloadWords: {
                calls.append("reloadWords")
            }
        )

        await refresher.refreshAfterLearningMutation()

        #expect(calls == ["invalidateQueue", "reloadWords"])
    }
}
