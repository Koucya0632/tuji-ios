// 設定 → 提醒. Device-local, so it reads StudyReminders rather than
// SettingsStore, and it is never inert while the account's settings load.

import SwiftUI

struct ReminderSettingsSection: View {
    @Environment(StudyReminders.self) private var reminders

    var body: some View {
        TujiSection(title: "提醒", footer: "今天已經學過就不會再提醒。") {
            TujiRow(
                leading: { TujiRowLabel(label: "每日提醒", subtitle: "在你選的時間提醒你回來複習") },
                trailing: {
                    TujiCheckbox(isOn: Binding(
                        get: { self.reminders.isEnabled },
                        set: { on in Task { await self.reminders.setEnabled(on) } }
                    ))
                }
            )
            if self.reminders.isEnabled {
                TujiRow(
                    leading: { TujiRowLabel(label: "提醒時間") },
                    trailing: {
                        DatePicker("提醒時間", selection: self.reminderTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                )
            }
            if self.reminders.authorization == .denied {
                // A refused prompt cannot be asked again from inside the app;
                // iOS 設定 is the only way back.
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    TujiRow("通知已關閉", subtitle: "到 iOS 設定允許 Tuji 傳送通知")
                }
                .tujiRowStyle()
            }
        }
        .task { await self.reminders.refreshAuthorization() }
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                let time = self.reminders.time
                return Calendar.current.date(
                    bySettingHour: time.hour,
                    minute: time.minute,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                let time = ReminderTime(hour: parts.hour ?? 20, minute: parts.minute ?? 0)
                Task { await self.reminders.setTime(time) }
            }
        )
    }
}
