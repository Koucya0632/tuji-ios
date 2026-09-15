// Tracks whether the user has been through the marketing intro pages,
// the per-account Setup picker, and the first-run feature tour. All are
// persisted in UserDefaults.
//
// introDone is device-global (it's marketing for any user).
// tourDone is device-global (the tour explains the UI, not the account).
// setupDone is per-user (each new account gets its own picker).

import Foundation
import Observation

/// What `SettingsStore` needs from onboarding: where the device stands on the
/// first-run questions. A seam because the store reached `OnboardingState.shared`
/// from inside four methods, so its loading tests quietly wrote the real
/// UserDefaults.
@MainActor
protocol OnboardingRecord: AnyObject {
    /// The learning direction chosen on this device, or nil before the picker.
    var learningDirection: LearningDirection? { get }
    /// Mirror a direction the settings store decided. Only the store calls this.
    func recordLearningDirection(_ direction: LearningDirection)
    func setupDone(for userId: UUID) -> Bool
}

@MainActor
@Observable
final class OnboardingState: OnboardingRecord {
    static let shared = OnboardingState()

    private let introKey = "tuji.onboarding.introDone"
    private let tourKey = "tuji.onboarding.tourDone"
    private let reviewHintKey = "tuji.study.reviewHintTaught"
    private let learningDirectionKey = "tuji.learning.direction"

    var introDone: Bool {
        didSet { UserDefaults.standard.set(introDone, forKey: introKey) }
    }

    var tourDone: Bool {
        didSet { UserDefaults.standard.set(tourDone, forKey: tourKey) }
    }

    /// The 複習 hero carries no visible affordance, so a stalled item offers
    /// 「想不起來？點一下圖片」 once. Set when the user actually flips — someone
    /// who ignored the line has not learned it and should see it again.
    /// Device-global like `tourDone`: it teaches the UI, not the account.
    var reviewHintTaught: Bool {
        didSet { UserDefaults.standard.set(reviewHintTaught, forKey: reviewHintKey) }
    }

    /// Read here — launch routing asks it before any settings exist — but
    /// written by `SettingsStore` alone, through `recordLearningDirection`. Both
    /// pickers used to set this *and* call the store, two writers of one
    /// UserDefaults key agreeing only because every call site remembered to.
    private(set) var learningDirection: LearningDirection?

    func recordLearningDirection(_ direction: LearningDirection) {
        guard self.learningDirection != direction else { return }
        self.learningDirection = direction
    }

    /// Per-user: ".setupDone.<uuid>". Reading via setupDone(for:) avoids
    /// mixing accounts on the same device.
    private(set) var setupDoneByUser: [String: Bool] = [:]

    private init() {
        introDone = UserDefaults.standard.bool(forKey: introKey)
        tourDone = UserDefaults.standard.bool(forKey: tourKey)
        reviewHintTaught = UserDefaults.standard.bool(forKey: reviewHintKey)
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
