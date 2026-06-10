// UIApplicationDelegate adapter for APNs registration callbacks. SwiftUI
// has no direct hook for `didRegisterForRemoteNotifications`, so we
// bridge via @UIApplicationDelegateAdaptor in TujiApp.

import Foundation
import OSLog
import UIKit

final class PushAppDelegate: NSObject, UIApplicationDelegate, Sendable {
    private static let log = Logger(subsystem: "app.tuji.ios", category: "push")

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    )
        -> Bool
    {
        true
    }

    func application(
        _: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Self.log.info("APNs token received len=\(token.count, privacy: .public)")
        Task { @MainActor in
            await PushNotificationService.shared.handleAPNsToken(token)
        }
    }

    func application(
        _: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Self.log.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }
}
