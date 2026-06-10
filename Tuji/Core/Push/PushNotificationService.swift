// Push notification permission + APNs token lifecycle.
//
// Flow:
//   1. PushPermissionView calls `requestAuthorization()`
//   2. On grant → calls `UIApplication.registerForRemoteNotifications`
//   3. PushAppDelegate captures the APNs token → invokes
//      `handleAPNsToken` which POSTs it to the backend
//   4. Sign-out calls `unregister()` to drop the device's row
//
// "Already prompted" is tracked in UserDefaults so RootView can decide
// whether to show PushPermissionView again.

import Foundation
import OSLog
import UIKit
import UserNotifications

@MainActor
@Observable
final class PushNotificationService {
    static let shared = PushNotificationService()

    enum Authorization: String { case undetermined, granted, denied }

    private(set) var authorization: Authorization = .undetermined

    private let log = Logger(subsystem: "app.tuji.ios", category: "push")
    private let promptedKey = "tuji.push.prompted"
    private let deviceIdKey = "tuji.push.deviceId"

    private init() {}

    /// Has the user been through the in-app permission prompt yet?
    /// RootView reads this to decide whether to show PushPermissionView.
    var hasBeenPrompted: Bool {
        UserDefaults.standard.bool(forKey: promptedKey)
    }

    func markPrompted() {
        UserDefaults.standard.set(true, forKey: promptedKey)
    }

    /// Stable per-install identifier sent with the APNs token. Survives
    /// app restarts but resets if the user deletes + reinstalls the app
    /// (which is the desired behaviour — that device is a fresh one for
    /// our purposes).
    var deviceId: String {
        if let existing = UserDefaults.standard.string(forKey: deviceIdKey) {
            return existing
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: deviceIdKey)
        return new
    }

    /// Reads current system permission state. Call on app launch to keep
    /// `authorization` in sync.
    func refreshAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorization = mapStatus(settings.authorizationStatus)
        log.info("authorization status=\(self.authorization.rawValue, privacy: .public)")
    }

    /// Requests notification permission. If granted, also triggers APNs
    /// registration which calls back through PushAppDelegate.
    @discardableResult
    func requestAuthorization() async -> Authorization {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            authorization = granted ? .granted : .denied
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
            log.info("requestAuthorization → \(self.authorization.rawValue, privacy: .public)")
        } catch {
            authorization = .denied
            log.error("requestAuthorization failed: \(error.localizedDescription, privacy: .public)")
        }
        markPrompted()
        return authorization
    }

    /// Called by PushAppDelegate when APNs returns the token.
    func handleAPNsToken(_ token: String) async {
        do {
            try await APIClient.shared.post(
                .usersPushToken,
                body: PushTokenPayload(token: token, deviceId: deviceId, platform: "ios"),
                as: AckResponse.self
            )
            log.info("APNs token uploaded for device=\(self.deviceId, privacy: .public)")
        } catch {
            log.error("APNs token upload failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Called by AuthService.signOut so the device stops receiving push
    /// for the previous account. Best-effort — failures are logged only.
    func unregister() async {
        do {
            try await APIClient.shared.delete(.usersPushTokenDelete(deviceId: deviceId))
            log.info("APNs token unregistered for device=\(self.deviceId, privacy: .public)")
        } catch {
            log.info("unregister dropped: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func mapStatus(_ status: UNAuthorizationStatus) -> Authorization {
        switch status {
        case .notDetermined: .undetermined
        case .authorized, .provisional, .ephemeral: .granted
        case .denied: .denied
        @unknown default: .undetermined
        }
    }
}

private struct PushTokenPayload: Encodable, Sendable {
    let token: String
    let deviceId: String
    let platform: String
}

private struct AckResponse: Decodable, Sendable {
    let ok: Bool?
}
