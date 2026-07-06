// Tracks whether the user has been through the marketing intro pages,
// the per-account Setup picker, and the first-run feature tour. All are
// persisted in UserDefaults.
//
// introDone is device-global (it's marketing for any user).
// tourDone is device-global (the tour explains the UI, not the account).
// setupDone is per-user (each new account gets its own picker).

import Foundation
import Observation

@MainActor
@Observable
final class OnboardingState {
    static let shared = OnboardingState()

    private let introKey = "tuji.onboarding.introDone"
    private let tourKey = "tuji.onboarding.tourDone"
    private let learningDirectionKey = "tuji.learning.direction"

    var introDone: Bool {
        didSet { UserDefaults.standard.set(introDone, forKey: introKey) }
    }

    var tourDone: Bool {
        didSet { UserDefaults.standard.set(tourDone, forKey: tourKey) }
    }

    var learningDirection: LearningDirection? {
        didSet {
            if let learningDirection {
                UserDefaults.standard.set(
                    learningDirection.rawValue,
                    forKey: self.learningDirectionKey
                )
            } else {
                UserDefaults.standard.removeObject(forKey: self.learningDirectionKey)
            }
        }
    }

    /// Per-user: ".setupDone.<uuid>". Reading via setupDone(for:) avoids
    /// mixing accounts on the same device.
    private(set) var setupDoneByUser: [String: Bool] = [:]

    private init() {
        introDone = UserDefaults.standard.bool(forKey: introKey)
        tourDone = UserDefaults.standard.bool(forKey: tourKey)
        learningDirection = UserDefaults.standard.string(forKey: learningDirectionKey)
            .flatMap(LearningDirection.init(rawValue:))
    }

    func setupDone(for userId: UUID) -> Bool {
        let key = "tuji.onboarding.setupDone.\(userId.uuidString)"
        if let cached = setupDoneByUser[key] { return cached }
        let stored = UserDefaults.standard.bool(forKey: key)
        setupDoneByUser[key] = stored
        return stored
    }

    func markSetupDone(for userId: UUID) {
        let key = "tuji.onboarding.setupDone.\(userId.uuidString)"
        UserDefaults.standard.set(true, forKey: key)
        setupDoneByUser[key] = true
    }
}
