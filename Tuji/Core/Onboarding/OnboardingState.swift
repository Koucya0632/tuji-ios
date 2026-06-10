// Tracks whether the user has been through the marketing intro pages and
// the per-account Setup picker. Both are persisted in UserDefaults.
//
// introDone is device-global (it's marketing for any user).
// setupDone is per-user (each new account gets its own picker).

import Foundation
import Observation

@MainActor
@Observable
final class OnboardingState {
    static let shared = OnboardingState()

    private let introKey = "tuji.onboarding.introDone"

    var introDone: Bool {
        didSet { UserDefaults.standard.set(introDone, forKey: introKey) }
    }

    /// Per-user: ".setupDone.<uuid>". Reading via setupDone(for:) avoids
    /// mixing accounts on the same device.
    private(set) var setupDoneByUser: [String: Bool] = [:]

    private init() {
        self.introDone = UserDefaults.standard.bool(forKey: introKey)
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
