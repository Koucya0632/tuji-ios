import Foundation
import Observation
import OSLog

/// Owns the one-time work that determines when launch can hand the window to
/// normal navigation. All effects are injected so timing and concurrency stay
/// deterministic in tests.
@MainActor
@Observable
final class LaunchCoordinator {
    enum State: Equatable {
        case idle
        case splash
        case ready
    }

    enum SessionResolution: Equatable {
        case signedOut
        case signedIn(userID: UUID)
    }

    private enum CatalogOwner: Equatable {
        case guest
        case signedIn(userID: UUID)
    }

    private struct CatalogRequest {
        let id: UUID
        let owner: CatalogOwner
        let task: Task<Void, Never>
    }

    typealias ResolveAuthentication = @MainActor () async -> SessionResolution
    typealias AsyncWork = @MainActor () async -> Void
    typealias FinalizeSignedIn = @MainActor (UUID) async -> Void
    typealias TrackAppOpen = @MainActor () -> Void
    typealias Sleep = (Duration) async -> Void

    private(set) var state: State = .idle

    var guestCatalogReady: Bool {
        self.activeCatalogOwner == .guest
    }

    var launchReady: Bool {
        self.state == .ready
    }

    private let minimumSplashDuration: Duration
    private let resolveAuthentication: ResolveAuthentication
    private let hydrateProfile: AsyncWork
    private let preloadCatalog: AsyncWork
    private let finalizeSignedIn: FinalizeSignedIn
    private let replayOutbox: AsyncWork
    private let trackAppOpen: TrackAppOpen
    private let sleep: Sleep
    private let signposter = OSSignposter(
        subsystem: "app.tuji.ios",
        category: "launch"
    )

    @ObservationIgnored private var startTask: Task<Void, Never>?
    private var activeCatalogOwner: CatalogOwner?
    @ObservationIgnored private var latestCatalogRequest: CatalogRequest?
    @ObservationIgnored private var catalogTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var profileTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var outboxTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var didTrackAppOpen = false
    @ObservationIgnored private var launchToReadyInterval: OSSignpostIntervalState?

    init(
        minimumSplashDuration: Duration = .milliseconds(600),
        resolveAuthentication: @escaping ResolveAuthentication,
        hydrateProfile: @escaping AsyncWork,
        preloadCatalog: @escaping AsyncWork,
        finalizeSignedIn: @escaping FinalizeSignedIn,
        replayOutbox: @escaping AsyncWork,
        trackAppOpen: @escaping TrackAppOpen,
        sleep: @escaping Sleep = { duration in
            try? await Task.sleep(for: duration)
        }
    ) {
        self.minimumSplashDuration = minimumSplashDuration
        self.resolveAuthentication = resolveAuthentication
        self.hydrateProfile = hydrateProfile
        self.preloadCatalog = preloadCatalog
        self.finalizeSignedIn = finalizeSignedIn
        self.replayOutbox = replayOutbox
        self.trackAppOpen = trackAppOpen
        self.sleep = sleep
    }

    /// Safe to call from repeated SwiftUI `.task` lifetimes. Every caller joins
    /// the same task, so analytics and launch side effects still happen once.
    func start() async {
        if let startTask {
            await startTask.value
            return
        }

        self.state = .splash
        self.trackAppOpenOnce()
        self.startLaunchToReadyIntervalOnce()
        self.startPreloadOnce()

        let task = Task { [weak self] in
            guard let self else { return }
            await self.runLaunchGate()
        }
        self.startTask = task
        await task.value
    }

    /// A deterministic seam for tests. Production launch never waits for these
    /// tasks: speculative catalog hydration, profile refresh, and outbox replay
    /// stay off the critical route-resolution path.
    func waitForBackgroundWork() async {
        let catalogTasks = Array(self.catalogTasks.values)
        for task in catalogTasks {
            await task.value
        }
        for task in self.profileTasks.values {
            await task.value
        }
        for task in self.outboxTasks.values {
            await task.value
        }
    }

    /// Interactive sign-in can happen after the one-time launch gate opened.
    /// RootView calls this for the current user; repeated calls join the same
    /// finalization task, and readiness is tracked per account.
    func prepareSignedInSession(userID: UUID) async {
        self.startSignedInWorkOnce(userID: userID)
        await self.requestCatalog(
            owner: .signedIn(userID: userID),
            intervalName: "catalog-finalize"
        ) { [finalizeSignedIn = self.finalizeSignedIn] in
            await finalizeSignedIn(userID)
        }.value
    }

    /// Restores the anonymous aggregate after sign-out. This matters when the
    /// same process previously published personalized words for an account.
    func prepareGuestSession() async {
        await self.requestCatalog(
            owner: .guest,
            intervalName: "catalog-preload",
            work: self.preloadCatalog
        ).value
    }

    /// A choice made before Main is first presented (for example learning
    /// direction or first-run Setup) creates a new catalog generation for the
    /// same account. Clear readiness synchronously so RootView cannot render
    /// Main for one frame with the previous context, then start the replacement
    /// request. Store-level context/flight IDs keep the superseded work from
    /// publishing if it finishes late.
    @discardableResult
    func refreshGuestCatalog() -> Task<Void, Never> {
        self.replaceCatalogRequest(
            owner: .guest,
            intervalName: "catalog-preload",
            work: self.preloadCatalog
        )
    }

    @discardableResult
    func refreshSignedInCatalog(userID: UUID) -> Task<Void, Never> {
        self.startSignedInWorkOnce(userID: userID)
        return self.replaceCatalogRequest(
            owner: .signedIn(userID: userID),
            intervalName: "catalog-finalize"
        ) { [finalizeSignedIn = self.finalizeSignedIn] in
            await finalizeSignedIn(userID)
        }
    }

    func catalogReady(for account: LaunchAccountState) -> Bool {
        switch account {
        case .guest:
            self.activeCatalogOwner == .guest
        case let .signedIn(userID, _):
            self.activeCatalogOwner == .signedIn(userID: userID)
        case .checking, .signedOut:
            true
        }
    }

    func presentation(for context: LaunchDestinationContext) -> LaunchPresentation {
        let destination = LaunchDestination.resolve(
            launchReady: self.launchReady,
            catalogReady: self.catalogReady(for: context.account),
            context: context
        )
        return destination == .splash
            ? .showingBrand
            : .ready(destination)
    }

    /// RootView calls this when the first non-brand destination is actually
    /// renderable. Keeping the interval open through a slow catalog makes
    /// `launch-to-ready` describe the visible Splash duration, not merely the
    /// auth + 600ms coordinator gate. Repeated destination changes are ignored.
    func destinationDidBecomeReady() {
        guard let interval = self.launchToReadyInterval else { return }
        self.signposter.endInterval("launch-to-ready", interval)
        self.launchToReadyInterval = nil
    }

    private func runLaunchGate() async {
        let sleep = self.sleep
        let minimumSplashDuration = self.minimumSplashDuration

        let authenticationTask = Task { [weak self] in
            guard let self else { return SessionResolution.signedOut }
            return await self.resolveAuthenticationWithSignpost()
        }
        let minimumDurationTask = Task {
            await sleep(minimumSplashDuration)
        }

        let resolution = await authenticationTask.value
        switch resolution {
        case .signedOut:
            break
        case let .signedIn(userID):
            self.startSignedInWorkOnce(userID: userID)
            _ = self.requestCatalog(
                owner: .signedIn(userID: userID),
                intervalName: "catalog-finalize"
            ) { [finalizeSignedIn = self.finalizeSignedIn] in
                await finalizeSignedIn(userID)
            }
        }

        await minimumDurationTask.value
        self.state = .ready
    }

    private func trackAppOpenOnce() {
        guard !self.didTrackAppOpen else { return }
        self.didTrackAppOpen = true
        self.trackAppOpen()
    }

    private func startLaunchToReadyIntervalOnce() {
        guard self.launchToReadyInterval == nil else { return }
        self.launchToReadyInterval = self.signposter.beginInterval(
            "launch-to-ready"
        )
    }

    private func startPreloadOnce() {
        guard self.latestCatalogRequest == nil else { return }
        _ = self.requestCatalog(
            owner: .guest,
            intervalName: "catalog-preload",
            work: self.preloadCatalog
        )
    }

    private func replaceCatalogRequest(
        owner: CatalogOwner,
        intervalName: StaticString,
        work: @escaping AsyncWork
    )
        -> Task<Void, Never>
    {
        self.latestCatalogRequest = nil
        self.activeCatalogOwner = nil
        return self.requestCatalog(
            owner: owner,
            intervalName: intervalName,
            work: work
        )
    }

    /// Only the latest account request can publish readiness. Older network
    /// work may finish, but cannot route a new session with stale ownership.
    private func requestCatalog(
        owner: CatalogOwner,
        intervalName: StaticString,
        work: @escaping AsyncWork
    )
        -> Task<Void, Never>
    {
        if let request = self.latestCatalogRequest,
           request.owner == owner
        {
            return request.task
        }

        self.activeCatalogOwner = nil
        let requestID = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            let signpostID = self.signposter.makeSignpostID()
            let interval = self.signposter.beginInterval(
                intervalName,
                id: signpostID
            )
            await work()
            if self.latestCatalogRequest?.id == requestID {
                self.activeCatalogOwner = owner
            }
            self.signposter.endInterval(intervalName, interval)
            self.catalogTasks[requestID] = nil
        }
        let request = CatalogRequest(id: requestID, owner: owner, task: task)
        self.latestCatalogRequest = request
        self.catalogTasks[requestID] = task
        return task
    }

    private func startSignedInWorkOnce(userID: UUID) {
        if self.profileTasks[userID] == nil {
            let hydrateProfile = self.hydrateProfile
            self.profileTasks[userID] = Task {
                await hydrateProfile()
            }
        }

        if self.outboxTasks[userID] == nil {
            let replayOutbox = self.replayOutbox
            self.outboxTasks[userID] = Task {
                await replayOutbox()
            }
        }
    }

    private func resolveAuthenticationWithSignpost() async -> SessionResolution {
        let signpostID = self.signposter.makeSignpostID()
        let interval = self.signposter.beginInterval(
            "auth-resolution",
            id: signpostID
        )
        let resolution = await self.resolveAuthentication()
        self.signposter.endInterval("auth-resolution", interval)
        return resolution
    }
}
