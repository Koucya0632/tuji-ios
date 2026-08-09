import Foundation

/// The account facts that decide which top-level screen owns the window.
/// Keeping this independent of `AuthService` makes the routing table a pure,
/// exhaustively testable function.
enum LaunchAccountState: Equatable {
    case checking
    case signedOut
    case guest
    case signedIn(userID: UUID, setupDone: Bool)
}

struct LaunchDestinationContext: Equatable {
    let account: LaunchAccountState
    let learningDirectionSelected: Bool
    let introDone: Bool
}

/// The coordinator's render contract. RootView either keeps the single static
/// brand surface mounted or renders exactly one interactive destination.
enum LaunchPresentation: Equatable {
    case showingBrand
    case ready(LaunchDestination)
}

enum LaunchTransitionPolicy {
    static func opacityDuration(reduceMotion: Bool) -> TimeInterval? {
        reduceMotion ? nil : 0.18
    }
}

/// A single top-level destination. In particular, `.splash` is rendered in
/// exactly one place; it is no longer both the root content and an overlay.
enum LaunchDestination: Hashable {
    case splash
    case learningDirection
    case onboarding
    case welcome
    case setup(userID: UUID)
    case main

    static func resolve(
        launchReady: Bool,
        catalogReady: Bool,
        context: LaunchDestinationContext
    )
        -> LaunchDestination
    {
        guard launchReady else { return .splash }

        switch context.account {
        case .checking:
            return .splash

        case .signedOut:
            guard context.learningDirectionSelected else {
                return .learningDirection
            }
            return context.introDone ? .welcome : .onboarding

        case .guest:
            guard context.learningDirectionSelected else {
                return .learningDirection
            }
            return catalogReady ? .main : .splash

        case let .signedIn(userID, setupDone):
            guard context.learningDirectionSelected else {
                return .learningDirection
            }
            guard setupDone else { return .setup(userID: userID) }
            return catalogReady ? .main : .splash
        }
    }

    /// Offline chrome belongs to an interactive destination, never to launch.
    var isReady: Bool {
        self != .splash
    }
}
