// 發音口音 picker. Updates SettingsStore via update(_:), applying the choice
// immediately and auto-persisting; SpeechService reads current settings at
// speak time.

import SwiftUI

struct AccentPickerView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private struct Option {
        let code: String
        let label: String
        let detail: String
    }

    private static let options: [Option] = [
        Option(code: "us", label: "美式", detail: "en-US · 預設"),
        Option(code: "uk", label: "英式", detail: "en-GB")
    ]

    var body: some View {
        List {
            Section {
                ForEach(Self.options, id: \.code) { opt in
                    Button {
                        self.store.update { $0.accent = opt.code }
                        self.dismiss()
                    } label: {
                        HStack(spacing: Space.s3) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(opt.label).foregroundStyle(.tujiInk)
                                Text(opt.detail)
                                    .font(.tujiCaption)
                                    .foregroundStyle(.tujiInk3)
                            }
                            Spacer()
                            if self.store.current.accent == opt.code {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tujiTeal)
                            }
                        }
                    }
                }
            } header: {
                Text("聽單字朗讀時用哪一種口音")
            }
        }
        .scrollContentBackground(.hidden)
        .background(.tujiBg)
        .navigationTitle("發音口音")
        .navigationBarTitleDisplayMode(.inline)
    }
}
