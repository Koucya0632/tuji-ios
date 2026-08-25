import Foundation
import Testing
@testable import Tuji

@MainActor
struct LaunchCoordinatorCatalogTests {
    @Test
    func speculativePreloadCannotReleaseASignedInCatalog() async {
        let catalog = LaunchTestGate()
        let userID = UUID()
        var preloadCompletions = 0
        var finalizationStarts = 0
        let coordinator = LaunchCoordinator(
            minimumSplashDuration: .milliseconds(0),
            resolveAuthentication: { .signedIn(userID: userID) },
            hydrateProfile: {},
            catalog: FakeCatalogWarmer.splitting(
                guest: { preloadCompletions += 1 },
                signedIn: { finalizedUserID in
                    #expect(finalizedUserID == userID)
                    finalizationStarts += 1
                    await catalog.wait()
                }
            ),
            replayOutbox: {},
            trackAppOpen: {}
        )
        let context = LaunchDestinationContext(
            account: .signedIn(userID: userID, setupDone: true),
            learningDirectionSelected: true,
            introDone: true
        )

        let start = Task { await coordinator.start() }
        await self.yieldUntil {
            preloadCompletions == 1 && finalizationStarts == 1
        }
        await start.value

        #expect(coordinator.state == .ready)
        #expect(!coordinator.guestCatalogReady)
        #expect(!coordinator.catalogReady(for: context.account))
        #expect(LaunchDestination.resolve(
            launchReady: coordinator.launchReady,
            catalogReady: coordinator.catalogReady(for: context.account),
            context: context
        ) == .splash)

        catalog.open()
        await coordinator.waitForBackgroundWork()

        #expect(coordinator.state == .ready)
        #expect(coordinator.catalogReady(for: context.account))
        #expect(LaunchDestination.resolve(
            launchReady: coordinator.launchReady,
            catalogReady: coordinator.catalogReady(for: context.account),
            context: context
        ) == .main)
    }

    @Test
    func signedInSetupDoesNotWaitForCatalogFinalization() async {
        let catalog = LaunchTestGate()
        let userID = UUID()
        var finalizationStarts = 0
        let coordinator = LaunchCoordinator(
            minimumSplashDuration: .milliseconds(0),
            resolveAuthentication: { .signedIn(userID: userID) },
            hydrateProfile: {},
            catalog: FakeCatalogWarmer.splitting(
                signedIn: { _ in
                    finalizationStarts += 1
                    await catalog.wait()
                }
            ),
            replayOutbox: {},
            trackAppOpen: {}
        )

        await coordinator.start()
        await self.yieldUntil { finalizationStarts == 1 }
        let context = LaunchDestinationContext(
            account: .signedIn(userID: userID, setupDone: false),
            learningDirectionSelected: true,
            introDone: true
        )

        #expect(coordinator.launchReady)
        #expect(!coordinator.catalogReady(for: context.account))
        #expect(LaunchDestination.resolve(
            launchReady: coordinator.launchReady,
            catalogReady: coordinator.catalogReady(for: context.account),
            context: context
        ) == .setup(userID: userID))

        catalog.open()
        await coordinator.waitForBackgroundWork()
    }

    @Test
    func aCompletedFailedCatalogAttemptStillReleasesMain() async {
        let userID = UUID()
        var attemptedCatalogLoad = false
        let coordinator = LaunchCoordinator(
            minimumSplashDuration: .milliseconds(0),
            resolveAuthentication: { .signedIn(userID: userID) },
            hydrateProfile: {},
            catalog: FakeCatalogWarmer.splitting(
                signedIn: { _ in
                    attemptedCatalogLoad = true
                }
            ),
            replayOutbox: {},
            trackAppOpen: {}
        )

        await coordinator.start()
        await coordinator.waitForBackgroundWork()
        let context = LaunchDestinationContext(
            account: .signedIn(userID: userID, setupDone: true),
            learningDirectionSelected: true,
            introDone: true
        )

        #expect(attemptedCatalogLoad)
        #expect(coordinator.catalogReady(for: context.account))
        #expect(LaunchDestination.resolve(
            launchReady: coordinator.launchReady,
            catalogReady: coordinator.catalogReady(for: context.account),
            context: context
        ) == .main)
    }

    @Test
    func interactiveSignInFinalizationIsPerUserAndIdempotent() async {
        let catalog = LaunchTestGate()
        let userID = UUID()
        var finalizations = 0
        var profileHydrations = 0
        var outboxReplays = 0
        let coordinator = LaunchCoordinator(
            minimumSplashDuration: .milliseconds(0),
            resolveAuthentication: { .signedOut },
            hydrateProfile: { profileHydrations += 1 },
            catalog: FakeCatalogWarmer.splitting(
                signedIn: { finalizedUserID in
                    #expect(finalizedUserID == userID)
                    finalizations += 1
                    await catalog.wait()
                }
            ),
            replayOutbox: { outboxReplays += 1 },
            trackAppOpen: {}
        )

        await coordinator.start()

        let first = Task {
            await coordinator.prepareSignedInSession(userID: userID)
        }
        let second = Task {
            await coordinator.prepareSignedInSession(userID: userID)
        }
        await self.yieldUntil { finalizations == 1 }

        #expect(!coordinator.catalogReady(for: .signedIn(
            userID: userID,
            setupDone: true
        )))

        catalog.open()
        await first.value
        await second.value
        await coordinator.waitForBackgroundWork()

        #expect(finalizations == 1)
        #expect(profileHydrations == 1)
        #expect(outboxReplays == 1)
        #expect(coordinator.catalogReady(for: .signedIn(
            userID: userID,
            setupDone: true
        )))
    }

    @Test
    func setupContextRefreshRevokesOldReadinessUntilReplacementFinishes() async {
        let replacement = LaunchTestGate()
        let userID = UUID()
        var finalizations = 0
        let coordinator = LaunchCoordinator(
            minimumSplashDuration: .milliseconds(0),
            resolveAuthentication: { .signedIn(userID: userID) },
            hydrateProfile: {},
            catalog: FakeCatalogWarmer.splitting(
                signedIn: { _ in
                    finalizations += 1
                    if finalizations == 2 {
                        await replacement.wait()
                    }
                }
            ),
            replayOutbox: {},
            trackAppOpen: {}
        )
        let account = LaunchAccountState.signedIn(
            userID: userID,
            setupDone: true
        )

        await coordinator.start()
        await coordinator.waitForBackgroundWork()
        #expect(finalizations == 1)
        #expect(coordinator.catalogReady(for: account))

        let refresh = coordinator.refreshSignedInCatalog(userID: userID)
        await self.yieldUntil { finalizations == 2 }

        #expect(!coordinator.catalogReady(for: account))
        #expect(LaunchDestination.resolve(
            launchReady: coordinator.launchReady,
            catalogReady: coordinator.catalogReady(for: account),
            context: LaunchDestinationContext(
                account: account,
                learningDirectionSelected: true,
                introDone: true
            )
        ) == .splash)

        replacement.open()
        await refresh.value
        #expect(coordinator.catalogReady(for: account))
    }

    @Test
    func aStaleAccountFinalizationCannotReplaceTheCurrentCatalog() async {
        let firstUserGate = LaunchTestGate()
        let firstUserID = UUID()
        let secondUserID = UUID()
        let coordinator = LaunchCoordinator(
            minimumSplashDuration: .milliseconds(0),
            resolveAuthentication: { .signedIn(userID: firstUserID) },
            hydrateProfile: {},
            catalog: FakeCatalogWarmer.splitting(
                signedIn: { userID in
                    if userID == firstUserID {
                        await firstUserGate.wait()
                    }
                }
            ),
            replayOutbox: {},
            trackAppOpen: {}
        )

        await coordinator.start()
        await coordinator.prepareSignedInSession(userID: secondUserID)

        #expect(coordinator.catalogReady(for: .signedIn(
            userID: secondUserID,
            setupDone: true
        )))

        firstUserGate.open()
        await coordinator.waitForBackgroundWork()

        #expect(!coordinator.catalogReady(for: .signedIn(
            userID: firstUserID,
            setupDone: true
        )))
        #expect(coordinator.catalogReady(for: .signedIn(
            userID: secondUserID,
            setupDone: true
        )))
    }

    @Test
    func switchingToGuestReactivatesTheAnonymousCatalog() async {
        let userID = UUID()
        var anonymousLoads = 0
        let coordinator = LaunchCoordinator(
            minimumSplashDuration: .milliseconds(0),
            resolveAuthentication: { .signedIn(userID: userID) },
            hydrateProfile: {},
            catalog: FakeCatalogWarmer.splitting(
                guest: { anonymousLoads += 1 }
            ),
            replayOutbox: {},
            trackAppOpen: {}
        )

        await coordinator.start()
        await coordinator.waitForBackgroundWork()
        #expect(coordinator.catalogReady(for: .signedIn(
            userID: userID,
            setupDone: true
        )))

        await coordinator.prepareGuestSession()

        #expect(anonymousLoads == 2)
        #expect(coordinator.guestCatalogReady)
        #expect(!coordinator.catalogReady(for: .signedIn(
            userID: userID,
            setupDone: true
        )))
    }

    private func yieldUntil(
        _ condition: @MainActor () -> Bool
    ) async {
        for _ in 0..<20 {
            if condition() { return }
            await Task.yield()
        }
    }
}
