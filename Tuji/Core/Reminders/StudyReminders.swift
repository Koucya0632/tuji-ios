// 每日提醒 — the preference, the permission, and laying out the plan.
//
// Device-local on purpose: a reminder belongs to the phone that rings, and the
// server has nothing to send it with (no `aps-environment`, see
// PushNotificationService). Free for every signed-in account — it is not a
// membership benefit, so it has no v1/v2 split and no lock.
//
// `StudyReminderPlan` decides *what* to schedule; this owns *when* to lay it out
// again and talks to the notification center through `ReminderScheduling`, so
// the rules are testable without a device.

import Foundation
import Observation
import OSLog
import UserNotifications

/// What today's reminder needs to know about the account.
@MainActor
protocol StudyReminderInputs {
    /// `nil` until study stats have loaded.
    var due: Int? { get }
    var studiedToday: Bool { get }
}

@MainActor
struct LiveStudyReminderInputs: StudyReminderInputs {
    var stats: StudyStatsStore = .shared
    var progress: ProgressStore = .shared

    var due: Int? {
        self.stats.stats?.due
    }

    var studiedToday: Bool {
        (self.progress.streak?.todayCount ?? 0) > 0
    }
}

/// What the app watches to know today's reminder is out of date.
struct StudyReminderSignature: Equatable {
    let due: Int?
    let studiedToday: Bool
    let uiLanguage: UILanguage
}

/// The slice of `UNUserNotificationCenter` the reminders use.
protocol ReminderScheduling: Sendable {
    func authorization() async -> PushNotificationService.Authorization
    /// Asks the system; `true` when notifications may be shown.
    func requestAuthorization() async -> Bool
    func pendingIdentifiers() async -> [String]
    func removePending(identifiers: [String])
    func add(_ entry: StudyReminderPlan.Entry, title: String, body: String) async throws
}

struct LiveReminderScheduler: ReminderScheduling {
    func authorization() async -> PushNotificationService.Authorization {
        await PushNotificationService.shared.refreshAuthorization()
        return PushNotificationService.shared.authorization
    }

    func requestAuthorization() async -> Bool {
        await PushNotificationService.shared.requestAuthorization(registeringForRemote: false) == .granted
    }

    func pendingIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }

    func removePending(identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func add(_ entry: StudyReminderPlan.Entry, title: String, body: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: entry.fireDate, repeats: false)
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: entry.identifier, content: content, trigger: trigger)
        )
    }
}

@MainActor
@Observable
final class StudyReminders {
    static let shared = StudyReminders()

    private(set) var isEnabled: Bool
    private(set) var time: ReminderTime
    /// The system's answer. `.denied` while `isEnabled` is the case the
    /// settings row has to explain: the person wants it, iOS will not show it.
    private(set) var authorization: PushNotificationService.Authorization = .undetermined

    private let scheduler: any ReminderScheduling
    private let inputs: any StudyReminderInputs
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    /// Layouts run one at a time. Two overlapping ones could each clear, then
    /// each add — and the first one's today survives a second one that meant
    /// to drop it.
    private var layout: Task<Void, Never>?
    private let log = Logger(subsystem: "app.tuji.ios", category: "reminders")

    private static let enabledKey = "tuji.reminder.enabled"
    private static let hourKey = "tuji.reminder.hour"
    private static let minuteKey = "tuji.reminder.minute"

    init(
        scheduler: any ReminderScheduling = LiveReminderScheduler(),
        inputs: any StudyReminderInputs = LiveStudyReminderInputs(),
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.scheduler = scheduler
        self.inputs = inputs
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        self.isEnabled = defaults.bool(forKey: Self.enabledKey)
        if defaults.object(forKey: Self.hourKey) != nil {
            self.time = ReminderTime(
                hour: defaults.integer(forKey: Self.hourKey),
                minute: defaults.integer(forKey: Self.minuteKey)
            )
        } else {
            self.time = .default
        }
    }

    /// Turning it on asks for permission first; a refusal leaves it off, so the
    /// checkbox never claims a reminder iOS will not deliver.
    func setEnabled(_ on: Bool) async {
        if on {
            let granted = await self.scheduler.requestAuthorization()
            self.authorization = granted ? .granted : .denied
            guard granted else {
                self.log.info("reminder not enabled: permission denied")
                return
            }
        }
        self.isEnabled = on
        self.defaults.set(on, forKey: Self.enabledKey)
        await self.reschedule()
    }

    /// Re-reads the system permission — it can be turned off in iOS 設定
    /// while the app is away.
    func refreshAuthorization() async {
        self.authorization = await self.scheduler.authorization()
    }

    func setTime(_ time: ReminderTime) async {
        self.time = time
        self.defaults.set(time.hour, forKey: Self.hourKey)
        self.defaults.set(time.minute, forKey: Self.minuteKey)
        await self.reschedule()
    }

    /// Lays the plan out again from what is known now. Call when the app comes
    /// to the foreground, when due counts or today's study change, and when the
    /// interface language changes (the text is resolved at scheduling time).
    func reschedule() async {
        let previous = self.layout
        let task = Task { @MainActor in
            await previous?.value
            await self.layOut()
        }
        self.layout = task
        await task.value
    }

    private func layOut() async {
        await self.clearPending()
        guard self.isEnabled else { return }
        self.authorization = await self.scheduler.authorization()
        guard self.authorization == .granted else { return }
        let entries = StudyReminderPlan.entries(
            now: self.now(),
            calendar: self.calendar,
            time: self.time,
            due: self.inputs.due,
            studiedToday: self.inputs.studiedToday
        )
        for entry in entries {
            let text = Self.text(for: entry)
            do {
                try await self.scheduler.add(entry, title: text.title, body: text.body)
            } catch {
                self.log.error("reminder add failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        self.log.info("reminders laid out count=\(entries.count, privacy: .public)")
    }

    private func clearPending() async {
        let ours = await self.scheduler.pendingIdentifiers()
            .filter { $0.hasPrefix(StudyReminderPlan.identifierPrefix) }
        if !ours.isEmpty {
            self.scheduler.removePending(identifiers: ours)
        }
    }

    static func text(for entry: StudyReminderPlan.Entry) -> (title: String, body: String) {
        if let due = entry.dueCount {
            return (tujiLocalized("今天有 \(due) 個字要複習"), tujiLocalized("花幾分鐘複習，記得更牢。"))
        }
        return (tujiLocalized("今天學一點吧"), tujiLocalized("花幾分鐘複習，記得更牢。"))
    }

    /// The account changed: the next account on this phone did not ask to be
    /// reminded.
    func reset() {
        self.isEnabled = false
        self.time = .default
        self.defaults.removeObject(forKey: Self.enabledKey)
        self.defaults.removeObject(forKey: Self.hourKey)
        self.defaults.removeObject(forKey: Self.minuteKey)
        let previous = self.layout
        self.layout = Task { @MainActor in
            await previous?.value
            await self.clearPending()
        }
    }
}
