import Foundation
import Testing
@testable import Tuji

@MainActor
struct LaunchCoordinatorTests {
    @Test
    func splashWaitsForTheSixHundredMillisecondGate() async {
        let clock = LaunchTestClock()
        let coordinator = LaunchCoordinator(
            resolveAuthentication: { .signedOut },
            hydrateProfile: {},
            catalog: FakeCatalogWarmer(),
            replayOutbox: {},
            trackAppOpen: {},
            sleep: { duration in
                await clock.sleep(for: duration)
            }
        )

        let start = Task { await coordinator.start() }
        await self.yieldUntil {
            coordinator.state == .splash && !clock.requestedDurations.isEmpty
        }

        #expect(coordinator.state == .splash)
        #expect(clock.requestedDurations == [.milliseconds(600)])

        clock.advance(by: .milliseconds(599))
        await Task.yield()
        #expect(coordinator.state == .splash)

        clock.advance(by: .milliseconds(1))
        await start.value

        #expect(coordinator.state == .ready)
    }

    @Test
    func concurrentStartsShareEveryOneTimeEffect() async {
        var authResolutions = 0
        var catalogPreloads = 0
        var signedInFinalizations = 0
        var profileHydrations = 0
        var outboxReplays = 0
        var appOpens = 0
        let userID = UUID()
        let coordinator = LaunchCoordinator(
            minimumSplashDuration: .milliseconds(0),
            resolveAuthentication: {
                authResolutions += 1
                return .signedIn(userID: userID)
            },
            hydrateProfile: { profileHydrations += 1 },
            catalog: FakeCatalogWarmer.splitting(
                guest: { catalogPreloads += 1 },
                signedIn: { finalizedUserID in
                    #expect(finalizedUserID == userID)
                    signedInFinalizations += 1
                }
            ),
            replayOutbox: { outboxReplays += 1 },
            trackAppOpen: { appOpens += 1 }
        )

        let first = Task { await coordinator.start() }
        let second = Task { await coordinator.start() }
        await first.value
        await second.value
        await coordinator.waitForBackgroundWork()

        #expect(authResolutions == 1)
        #expect(catalogPreloads == 1)
        #expect(signedInFinalizations == 1)
        #expect(profileHydrations == 1)
        #expect(outboxReplays == 1)
        #expect(appOpens == 1)
    }

    @Test
    func cancellingTheCallingViewTaskDoesNotRestartOrAbortColdLaunch() async {
        let authentication = LaunchTestGate()
        var authResolutions = 0
        var appOpens = 0
        let coordinator = LaunchCoordinator(
            minimumSplashDuration: .milliseconds(0),
            resolveAuthentication: {
                authResolutions += 1
                await authentication.wait()
                return .signedOut
            },
            hydrateProfile: {},
            catalog: FakeCatalogWarmer(),
            replayOutbox: {},
            trackAppOpen: { appOpens += 1 }
        )

        let caller = Task { await coordinator.start() }
        await self.yieldUntil { coordinator.state == .splash }
        caller.cancel()
        authentication.open()
        await caller.value
        await coordinator.start()

        #expect(coordinator.state == .ready)
        #expect(authResolutions == 1)
        #expect(appOpens == 1)
    }

    @Test
    func signedInProfileAndOutboxWorkDoesNotBlockReady() async {
        let profile = LaunchTestGate()
        let outbox = LaunchTestGate()
        var profileStarts = 0
        var outboxStarts = 0
        let userID = UUID()
        let coordinator = LaunchCoordinator(
            minimumSplashDuration: .milliseconds(0),
            resolveAuthentication: { .signedIn(userID: userID) },
            hydrateProfile: {
                profileStarts += 1
                await profile.wait()
            },
            catalog: FakeCatalogWarmer(),
            replayOutbox: {
                outboxStarts += 1
                await outbox.wait()
            },
            trackAppOpen: {}
        )

        await coordinator.start()
        await self.yieldUntil { profileStarts == 1 && outboxStarts == 1 }

        // Both background operations are still suspended, but routing is open.
        #expect(coordinator.state == .ready)
        #expect(profileStarts == 1)
        #expect(outboxStarts == 1)

        profile.open()
        outbox.open()
        await coordinator.waitForBackgroundWork()
    }

    @Test
    func signedOutLaunchSkipsProfileAndOutboxWork() async {
        var profileHydrations = 0
        var outboxReplays = 0
        var signedInFinalizations = 0
        let coordinator = LaunchCoordinator(
            minimumSplashDuration: .milliseconds(0),
            resolveAuthentication: { .signedOut },
            hydrateProfile: { profileHydrations += 1 },
            catalog: FakeCatalogWarmer.splitting(
                signedIn: { _ in signedInFinalizations += 1 }
            ),
            replayOutbox: { outboxReplays += 1 },
            trackAppOpen: {}
        )

        await coordinator.start()
        await coordinator.waitForBackgroundWork()

        #expect(profileHydrations == 0)
        #expect(outboxReplays == 0)
        #expect(signedInFinalizations == 0)
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

@MainActor
final class LaunchTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !self.isOpen else { return }
        await withCheckedContinuation { continuation in
            self.waiters.append(continuation)
        }
    }

    func open() {
        guard !self.isOpen else { return }
        self.isOpen = true
        let waiters = self.waiters
        self.waiters = []
        for waiter in waiters {
            waiter.resume()
        }
    }
}

@MainActor
private final class LaunchTestClock {
    private struct Waiter {
        let deadline: Duration
        let continuation: CheckedContinuation<Void, Never>
    }

    private(set) var requestedDurations: [Duration] = []
    private var elapsed: Duration = .zero
    private var waiters: [Waiter] = []

    func sleep(for duration: Duration) async {
        self.requestedDurations.append(duration)
        let deadline = self.elapsed + duration
        guard self.elapsed < deadline else { return }
        await withCheckedContinuation { continuation in
            self.waiters.append(Waiter(
                deadline: deadline,
                continuation: continuation
            ))
        }
    }

    func advance(by duration: Duration) {
        self.elapsed += duration
        let ready = self.waiters.filter { $0.deadline <= self.elapsed }
        self.waiters.removeAll { $0.deadline <= self.elapsed }
        for waiter in ready {
            waiter.continuation.resume()
        }
    }
}
