// Picks the daily-reminder time. Two wheels — hour (0–23) and minute in
// 15-minute steps (0/15/30/45) — matching the backend cron's 15-min bucket.
// Writes straight into SettingsStore via update(_:), which applies the change
// immediately and auto-persists.

import SwiftUI

struct ReminderTimePickerView: View {
    @Environment(SettingsStore.self) private var store

    private static let hours = Array(0...23)
    private static let minutes = [0, 15, 30, 45]

    var body: some View {
        List {
            Section {
                HStack(spacing: 0) {
                    Picker("時", selection: self.hourBinding) {
                        ForEach(Self.hours, id: \.self) { h in
                            Text(String(format: "%02d", h)).tag(h)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    Text(":")
                        .font(.tujiH3)
                        .foregroundStyle(.tujiInk2)

                    Picker("分", selection: self.minuteBinding) {
                        ForEach(Self.minutes, id: \.self) { m in
                            Text(String(format: "%02d", m)).tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
            } footer: {
                Text("每天到這個時間，如果還沒學習就會收到提醒。分鐘以 15 分鐘為單位。")
                    .foregroundStyle(.tujiInk3)
            }
        }
        .scrollContentBackground(.hidden)
        .background(.tujiBg)
        .navigationTitle("提醒時間")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hourBinding: Binding<Int> {
        Binding(
            get: { self.store.current.reminderHour },
            set: { newValue in self.store.update { $0.reminderHour = newValue } }
        )
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: {
                // Snap any persisted out-of-step value onto the wheel so the
                // selection stays valid.
                let m = self.store.current.reminderMinute
                return Self.minutes.contains(m) ? m : (m / 15) * 15
            },
            set: { newValue in self.store.update { $0.reminderMinute = newValue } }
        )
    }
}

#Preview {
    NavigationStack {
        ReminderTimePickerView()
            .environment(SettingsStore.shared)
    }
}
