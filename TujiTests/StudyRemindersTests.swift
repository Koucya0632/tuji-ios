// 每日提醒: which days are laid out, what today's entry knows, and the service's
// rules around permission, re-layout and sign-out. Decisions only — the
// notification text is localized, so it is not asserted here.

import Foundation
import Testing
@testable import Tuji

private func taipeiCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .gmt
    return calendar
}

private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    let calendar = taipeiCalendar()
    return calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute)) ?? Date()
}

struct StudyReminderPlanTests {
    @Test
    func beforeTheTimeTodayIsTheFirstOfSevenDays() {
        let entries = StudyReminderPlan.entries(
            now: date(28, 9),
            calendar: taipeiCalendar(),
            time: .default,
            due: 12,
            studiedToday: false
        )
        #expect(entries.count == StudyReminderPlan.horizonDays)
        #expect(entries.first?.fireDate.day == 28)
        #expect(entries.first?.fireDate.hour == 20)
        #expect(entries.last?.fireDate.day == 4) // 10月4日
    }

    @Test
    func onlyTodayCarriesTheDueCount() {
        let entries = StudyReminderPlan.entries(
            now: date(28, 9),
            calendar: taipeiCalendar(),
            time: .default,
            due: 12,
            studiedToday: false
        )
        #expect(entries.first?.dueCount == 12)
        #expect(entries.dropFirst().allSatisfy { $0.dueCount == nil })
    }

    @Test
    func nothingDueOrUnknownIsTheGenericReminder() {
        for due in [0, nil] as [Int?] {
            let entries = StudyReminderPlan.entries(
                now: date(28, 9),
                calendar: taipeiCalendar(),
                time: .default,
                due: due,
                studiedToday: false
            )
            #expect(entries.first?.dueCount == nil)
            #expect(entries.first?.fireDate.day == 28)
        }
    }

    @Test
    func studiedTodaySkipsTodayOnly() {
        let entries = StudyReminderPlan.entries(
            now: date(28, 9),
            calendar: taipeiCalendar(),
            time: .default,
            due: 12,
            studiedToday: true
        )
        #expect(entries.count == StudyReminderPlan.horizonDays - 1)
        #expect(entries.first?.fireDate.day == 29)
    }

    @Test
    func pastTheTimeTodayStartsTomorrow() {
        let entries = StudyReminderPlan.entries(
            now: date(28, 20, 1),
            calendar: taipeiCalendar(),
            time: .default,
            due: 12,
            studiedToday: false
        )
        #expect(entries.count == StudyReminderPlan.horizonDays - 1)
        #expect(entries.first?.fireDate.day == 29)
        #expect(entries.first?.dueCount == nil)
    }

    @Test
    func identifiersAreOnePerDayAndOurs() {
        let entries = StudyReminderPlan.entries(
            now: date(28, 9),
            calendar: taipeiCalendar(),
            time: ReminderTime(hour: 7, minute: 30),
            due: nil,
            studiedToday: false
        )
        #expect(Set(entries.map(\.identifier)).count == entries.count)
        #expect(entries.allSatisfy { $0.identifier.hasPrefix(StudyReminderPlan.identifierPrefix) })
        // 07:30 is already past at 09:00, so the plan starts tomorrow.
        #expect(entries.first?.identifier == "tuji.reminder.2026-09-29")
        #expect(entries.first?.fireDate.minute == 30)
    }
}

// MARK: - Service

private final class FakeScheduler: ReminderScheduling, @unchecked Sendable {
    var granted = true
    var systemAuthorization: PushNotificationService.Authorization = .granted
    private(set) var requestCount = 0
    /// identifier → dueCount, standing in for the pending notification list.
    private(set) var pending: [String: Int?] = [:]

    func authorization() async -> PushNotificationService.Authorization {
        self.systemAuthorization
    }

    func requestAuthorization() async -> Bool {
        self.requestCount += 1
        return self.granted
    }

    func pendingIdentifiers() async -> [String] {
        Array(self.pending.keys)
    }

    func removePending(identifiers: [String]) {
        for id in identifiers {
            self.pending[id] = nil
        }
    }

    func add(_ entry: StudyReminderPlan.Entry, title _: String, body _: String) async throws {
        self.pending[entry.identifier] = .some(entry.dueCount)
    }

    func seedForeign(_ id: String) {
        self.pending[id] = .some(nil)
    }
}

@MainActor
private final class FakeInputs: StudyReminderInputs {
    var due: Int?
    var studiedToday = false
}

@MainActor
struct StudyRemindersTests {
    private struct Harness {
        let reminders: StudyReminders
        let scheduler: FakeScheduler
        let inputs: FakeInputs
        let defaults: UserDefaults
    }

    private func makeHarness(defaults: UserDefaults? = nil) -> Harness {
        let defaults = defaults ?? UserDefaults(suiteName: "reminders-\(UUID().uuidString)") ?? .standard
        let scheduler = FakeScheduler()
        let inputs = FakeInputs()
        let reminders = StudyReminders(
            scheduler: scheduler,
            inputs: inputs,
            defaults: defaults,
            now: { date(28, 9) },
            calendar: taipeiCalendar()
        )
        return Harness(reminders: reminders, scheduler: scheduler, inputs: inputs, defaults: defaults)
    }

    @Test
    func offByDefaultAndSchedulesNothing() async {
        let h = self.makeHarness()
        #expect(h.reminders.isEnabled == false)
        #expect(h.reminders.time == .default)
        await h.reminders.reschedule()
        #expect(h.scheduler.pending.isEmpty)
    }

    @Test
    func enablingAsksPermissionThenLaysOutTheWeek() async {
        let h = self.makeHarness()
        h.inputs.due = 5
        await h.reminders.setEnabled(true)
        #expect(h.scheduler.requestCount == 1)
        #expect(h.reminders.isEnabled)
        #expect(h.scheduler.pending.count == StudyReminderPlan.horizonDays)
        #expect(h.scheduler.pending["tuji.reminder.2026-09-28"] == .some(5))
    }

    @Test
    func aRefusedPromptLeavesItOff() async {
        let h = self.makeHarness()
        h.scheduler.granted = false
        await h.reminders.setEnabled(true)
        #expect(h.reminders.isEnabled == false)
        #expect(h.reminders.authorization == .denied)
        #expect(h.scheduler.pending.isEmpty)
    }

    @Test
    func studyingTodayDropsTodayOnReschedule() async {
        let h = self.makeHarness()
        await h.reminders.setEnabled(true)
        #expect(h.scheduler.pending["tuji.reminder.2026-09-28"] != nil)
        h.inputs.studiedToday = true
        await h.reminders.reschedule()
        #expect(h.scheduler.pending["tuji.reminder.2026-09-28"] == nil)
        #expect(h.scheduler.pending.count == StudyReminderPlan.horizonDays - 1)
    }

    @Test
    func permissionRevokedInSystemSettingsClearsThePlan() async {
        let h = self.makeHarness()
        await h.reminders.setEnabled(true)
        h.scheduler.systemAuthorization = .denied
        await h.reminders.reschedule()
        #expect(h.scheduler.pending.isEmpty)
        #expect(h.reminders.isEnabled)
        #expect(h.reminders.authorization == .denied)
    }

    @Test
    func turningOffClearsOnlyOurNotifications() async {
        let h = self.makeHarness()
        h.scheduler.seedForeign("someone.else")
        await h.reminders.setEnabled(true)
        await h.reminders.setEnabled(false)
        #expect(Array(h.scheduler.pending.keys) == ["someone.else"])
    }

    @Test
    func theChoiceSurvivesARelaunch() async {
        let h = self.makeHarness()
        await h.reminders.setEnabled(true)
        await h.reminders.setTime(ReminderTime(hour: 7, minute: 45))
        let relaunched = self.makeHarness(defaults: h.defaults)
        #expect(relaunched.reminders.isEnabled)
        #expect(relaunched.reminders.time == ReminderTime(hour: 7, minute: 45))
    }

    @Test
    func signOutForgetsTheChoiceAndClearsThePlan() async {
        let h = self.makeHarness()
        await h.reminders.setEnabled(true)
        await h.reminders.setTime(ReminderTime(hour: 7, minute: 45))
        h.reminders.reset()
        await h.reminders.reschedule() // queued behind reset's clear
        #expect(h.reminders.isEnabled == false)
        #expect(h.reminders.time == .default)
        #expect(h.scheduler.pending.isEmpty)
        let relaunched = self.makeHarness(defaults: h.defaults)
        #expect(relaunched.reminders.isEnabled == false)
    }
}
