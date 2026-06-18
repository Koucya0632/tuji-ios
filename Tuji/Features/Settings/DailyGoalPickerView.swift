// Picks the daily new-word goal. Writes straight into SettingsStore via
// update(_:), which applies the change immediately and auto-persists.

import SwiftUI

struct DailyGoalPickerView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private static let options: [Int] = [5, 10, 15, 20, 30, 50]

    var body: some View {
        List {
            Section {
                ForEach(Self.options, id: \.self) { n in
                    Button {
                        self.store.update { $0.dailyGoal = n }
                        self.dismiss()
                    } label: {
                        HStack {
                            Text("\(n) 題")
                                .foregroundStyle(.tujiInk)
                            Spacer()
                            if self.store.current.dailyGoal == n {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tujiTeal)
                            }
                        }
                    }
                }
            } header: {
                Text("每天想學的題數")
            } footer: {
                Text("這個數字會用來算今日新字額度與目標達成度")
                    .foregroundStyle(.tujiInk3)
            }
        }
        .scrollContentBackground(.hidden)
        .background(.tujiBg)
        .navigationTitle("每日目標題數")
        .navigationBarTitleDisplayMode(.inline)
    }
}
