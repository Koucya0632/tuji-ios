// Centralized, privacy-safe Crashlytics boundary.
//
// Feature code can only attach values from the fixed enums below. Raw error
// descriptions, user IDs, email addresses, search text, and learning content
// must never cross this boundary.

import FirebaseCore
import FirebaseCrashlytics
import Foundation

enum CrashReporting {
    enum Flow: String {
        case appLaunch = "app_launch"
        case authentication
        case cards
        case favorites
        case onboarding
        case progress
        case pushNotifications = "push_notifications"
        case search
        case settings
        case study
        case wordDetail = "word_detail"
    }

    enum Step: String {
        case complete
        case fetch
        case initialize
        case load
        case persist
        case present
        case submit
        case sync
    }

    enum Category: String {
        case dataDecoding = "data_decoding"
        case integrationTest = "integration_test"
        case localPersistence = "local_persistence"
        case stateInvariant = "state_invariant"

        fileprivate var code: Int {
            switch self {
            case .dataDecoding: 1001
            case .localPersistence: 1002
            case .stateInvariant: 1003
            case .integrationTest: 1099
            }
        }
    }

    static func configure() {
        #if TUJI_DEV
        // Debug must not create a Firebase installation or send reports.
        return
        #else
        guard FirebaseApp.app() == nil else { return }

        FirebaseApp.configure()

        let crashlytics = Crashlytics.crashlytics()
        crashlytics.setCrashlyticsCollectionEnabled(true)
        crashlytics.setCustomValue(Self.buildChannel, forKey: "build_channel")
        crashlytics.setCustomValue(Self.appVersion, forKey: "app_version")
        crashlytics.setCustomValue(Self.buildNumber, forKey: "build_number")
        Self.setContext(flow: .appLaunch, step: .initialize)

        #if TUJI_BETA
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-CrashlyticsTestNonFatal") {
            Self.record(
                error: IntegrationTestError(),
                category: .integrationTest
            )
        }
        if arguments.contains("-CrashlyticsTestCrash") {
            fatalError("Crashlytics integration test")
        }
        #endif
        #endif
    }

    static func setContext(flow: Flow, step: Step) {
        #if !TUJI_DEV
        guard FirebaseApp.app() != nil else { return }
        let crashlytics = Crashlytics.crashlytics()
        crashlytics.setCustomValue(flow.rawValue, forKey: "flow")
        crashlytics.setCustomValue(step.rawValue, forKey: "step")
        #endif
    }

    /// Records only a fixed category. The original Error is intentionally not
    /// forwarded because its message or userInfo can contain personal data.
    static func record(error: Error, category: Category) {
        #if !TUJI_DEV
        guard FirebaseApp.app() != nil else { return }
        _ = error
        let sanitized = NSError(
            domain: "app.tuji.crash-reporting",
            code: category.code,
            userInfo: [NSLocalizedDescriptionKey: category.rawValue]
        )
        Crashlytics.crashlytics().record(error: sanitized)
        #else
        _ = error
        _ = category
        #endif
    }

    #if !TUJI_DEV
    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "unknown"
    }

    private static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "unknown"
    }

    private static var buildChannel: String {
        #if TUJI_BETA
        "testflight"
        #else
        "release"
        #endif
    }
    #endif
}

private struct IntegrationTestError: Error {}
