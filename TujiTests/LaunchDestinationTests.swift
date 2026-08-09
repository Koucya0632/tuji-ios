import Foundation
import Testing
@testable import Tuji

@MainActor
struct LaunchDestinationTests {
    @Test
    func destinationRoutingCoversEveryTopLevelBranch() {
        let userID = UUID()

        #expect(self.resolve(.signedOut, learning: false) == .learningDirection)
        #expect(self.resolve(.signedOut, learning: true, introDone: false) == .onboarding)
        #expect(self.resolve(.signedOut, learning: true, introDone: true) == .welcome)
        #expect(self.resolve(.guest, learning: true) == .main)
        #expect(self.resolve(
            .signedIn(userID: userID, setupDone: false),
            learning: true
        ) == .setup(userID: userID))
        #expect(self.resolve(
            .signedIn(userID: userID, setupDone: true),
            learning: true
        ) == .main)
        #expect(self.resolve(.checking, learning: true) == .splash)
    }

    @Test
    func signedOutAndSetupRoutesDoNotWaitForCatalog() {
        let userID = UUID()

        #expect(self.resolve(
            .signedOut,
            learning: true,
            catalogReady: false
        ) == .welcome)
        #expect(self.resolve(
            .signedIn(userID: userID, setupDone: false),
            learning: true,
            catalogReady: false
        ) == .setup(userID: userID))
    }

    @Test
    func guestAndCompletedSetupWaitForCatalog() {
        let userID = UUID()

        #expect(self.resolve(
            .guest,
            learning: true,
            catalogReady: false
        ) == .splash)
        #expect(self.resolve(
            .signedIn(userID: userID, setupDone: true),
            learning: true,
            catalogReady: false
        ) == .splash)
    }

    @Test
    func launchGateAlwaysWinsBeforeRouting() {
        let context = LaunchDestinationContext(
            account: .signedOut,
            learningDirectionSelected: true,
            introDone: true
        )

        #expect(LaunchDestination.resolve(
            launchReady: false,
            catalogReady: true,
            context: context
        ) == .splash)
    }

    @Test
    func reduceMotionRemovesOnlyTheOpacityTransition() {
        #expect(LaunchTransitionPolicy.opacityDuration(reduceMotion: true) == nil)
        #expect(LaunchTransitionPolicy.opacityDuration(reduceMotion: false) == 0.18)
    }

    private func resolve(
        _ account: LaunchAccountState,
        learning: Bool,
        introDone: Bool = true,
        catalogReady: Bool = true
    )
        -> LaunchDestination
    {
        LaunchDestination.resolve(
            launchReady: true,
            catalogReady: catalogReady,
            context: LaunchDestinationContext(
                account: account,
                learningDirectionSelected: learning,
                introDone: introDone
            )
        )
    }
}
