// Top-level state switcher. LaunchCoordinator owns the one-time 600ms/auth/
// catalog gate; LaunchDestination owns the pure routing table. RootView only
// renders one destination, so Splash is never duplicated under an overlay.

import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var auth
    @Environment(OnboardingState.self) private var onboarding
    @Environment(NetworkMonitor.self) private var network
    @Environment(LaunchCoordinator.self) private var launch
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let destination = self.destination

        ZStack(alignment: .top) {
            self.content(for: destination)
                .id(destination)
                .transition(.opacity)

            if destination.isReady,
               self.network.hasStatus,
               !self.network.isConnected
            {
                OfflineBanner()
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(5)
            }
        }
        .task { await self.launch.start() }
        .task(id: self.catalogSession) {
            switch self.catalogSession {
            case .some(.guest):
                await self.launch.prepareGuestSession()
            case let .some(.signedIn(userID)):
                await self.launch.prepareSignedInSession(userID: userID)
            case .none:
                break
            }
        }
        .onChange(of: self.onboarding.learningDirection) { oldValue, newValue in
            guard oldValue != newValue, newValue != nil else { return }
            // Direction selection happens before an interactive Main exists.
            // Replace any speculative/default-context readiness immediately;
            // Settings changes made from an already-mounted Main keep their
            // existing no-empty-flash reload behavior instead.
            switch self.auth.state {
            case .signedOut:
                self.launch.refreshGuestCatalog()
            case let .signedIn(user)
                where !self.onboarding.setupDone(for: user.id):
                self.launch.refreshSignedInCatalog(userID: user.id)
            case .checking, .guest, .signedIn:
                break
            }
        }
        .onChange(of: destination, initial: true) { _, newDestination in
            guard newDestination.isReady else { return }
            self.launch.destinationDidBecomeReady()
        }
        .animation(
            LaunchTransitionPolicy.opacityDuration(reduceMotion: self.reduceMotion)
                .map { .easeOut(duration: $0) },
            // `.isReady` changes only when the single brand surface hands off
            // to the first interactive destination. Later top-level route
            // changes stay outside this cold-launch opacity transaction.
            value: destination.isReady
        )
        .animation(.easeInOut(duration: 0.25), value: network.isConnected)
    }

    @ViewBuilder
    private func content(for destination: LaunchDestination) -> some View {
        switch destination {
        case .splash:
            SplashView()

        case .learningDirection:
            LearningDirectionOnboardingView()

        case .onboarding:
            OnboardingFlow()

        case .welcome:
            WelcomeView()

        case let .setup(userID):
            SetupView(
                userId: userID,
                onDone: {
                    // SetupView adopts the newly persisted language/direction
                    // immediately before this callback. Invalidate the older
                    // readiness in the same MainActor turn so Main waits for
                    // that exact final load attempt without flashing stale UI.
                    let refresh = self.launch.refreshSignedInCatalog(
                        userID: userID
                    )
                    await refresh.value
                }
            )

        case .main:
            switch self.auth.state {
            case .guest:
                MainTabsView(user: nil)
            case let .signedIn(user):
                MainTabsView(user: user)
            case .checking, .signedOut:
                // Destination is recomputed from the same observable state, so
                // this is only a defensive fallback for an interrupted update.
                SplashView()
            }
        }
    }

    private var destination: LaunchDestination {
        let presentation = self.launch.presentation(
            for: LaunchDestinationContext(
                account: self.launchAccount,
                learningDirectionSelected: self.onboarding.learningDirection != nil,
                introDone: self.onboarding.introDone
            )
        )
        switch presentation {
        case .showingBrand:
            return .splash
        case let .ready(destination):
            return destination
        }
    }

    private var launchAccount: LaunchAccountState {
        switch self.auth.state {
        case .checking:
            .checking
        case .signedOut:
            .signedOut
        case .guest:
            .guest
        case let .signedIn(user):
            .signedIn(
                userID: user.id,
                setupDone: self.onboarding.setupDone(for: user.id)
            )
        }
    }

    private var catalogSession: CatalogSession? {
        switch self.auth.state {
        case .guest:
            .guest
        case let .signedIn(user):
            .signedIn(userID: user.id)
        case .checking, .signedOut:
            nil
        }
    }

    private enum CatalogSession: Hashable {
        case guest
        case signedIn(userID: UUID)
    }
}

/// Pinned above interactive destinations whenever NWPathMonitor reports no
/// connectivity. Launch itself stays visually stable; request-level errors
/// remain responsible for explaining failures while Splash is visible.
private struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(.white)
            Text("目前沒有網路連線")
                .font(.tujiIcon(14, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .background(.tujiAlert, in: .rect(cornerRadius: Radius.r0))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }
}

#Preview {
    RootView()
        .environment(AuthService.shared)
        .environment(OnboardingState.shared)
        .environment(WordsStore.shared)
        .environment(CategoriesStore.shared)
        .environment(MasteryStore.shared)
        .environment(NetworkMonitor.shared)
        .environment(
            LaunchCoordinator(
                minimumSplashDuration: .milliseconds(0),
                resolveAuthentication: { .signedOut },
                hydrateProfile: {},
                preloadCatalog: {},
                finalizeSignedIn: { _ in },
                replayOutbox: {},
                trackAppOpen: {}
            )
        )
}
