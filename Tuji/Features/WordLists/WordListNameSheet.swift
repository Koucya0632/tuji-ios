// 建立詞表 / 重新命名 — one text field and one button. What happens after is
// the presenting screen's business, so it hands back the name and an outcome.

import SwiftUI

struct WordListNameSheet: View {
    let title: LocalizedStringKey
    let actionTitle: LocalizedStringKey
    var initialName: String = ""
    /// Returns nil when done (the sheet closes), or a sentence to show under
    /// the field.
    let submit: (String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var working = false
    @State private var error: String?

    static let maxLength = 40

    private var trimmed: String {
        self.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !self.working && !self.trimmed.isEmpty && self.trimmed.count <= Self.maxLength
    }

    var body: some View {
        TujiSheetShell(title: self.title, height: 280) {
            VStack(alignment: .leading, spacing: Space.s5) {
                TujiField(label: "名稱", footer: "最多 40 個字") {
                    TujiTextField(placeholder: "例如：廚房用品", text: self.$name, errorMessage: self.error)
                }
                BBtn(title: self.actionTitle, fullWidth: true) {
                    Task { await self.run() }
                }
                .disabled(!self.canSubmit)
                .padding(.horizontal, Space.s4)
            }
            .padding(.top, Space.s4)
        }
        .onAppear { self.name = self.initialName }
    }

    private func run() async {
        let name = self.trimmed
        self.working = true
        self.error = await self.submit(name)
        self.working = false
        if self.error == nil { self.dismiss() }
    }
}
