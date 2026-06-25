// Shared "drag up to reveal full details" pieces for the expandable peek /
// review sheets.
//
// `PullUpHint` is the affordance shown in the resting-detent whitespace.
// `ExpandableWordDetail` swaps that hint for the full WordDetailSections once
// the sheet is expanded, lazy-loading the Word the first time so a user who
// never pulls up doesn't trigger a network call.

import SwiftUI

/// Affordance hinting the sheet can be dragged up to reveal full details.
struct PullUpHint: View {
    var body: some View {
        VStack(spacing: Space.s1) {
            Image(systemName: "chevron.up")
                .font(.system(size: 14, weight: .heavy))
                .symbolEffect(.bounce, options: .repeating)
            Text("向上拉看完整詳情")
                .font(.system(size: 13, weight: .heavy))
        }
        .foregroundStyle(.tujiInk4)
        .frame(maxWidth: .infinity)
    }
}

/// Shows `PullUpHint` while collapsed; once `expanded`, lazy-loads the full
/// Word and renders `WordDetailSections`. Used by both the study peek sheet
/// and the review reveal sheet.
struct ExpandableWordDetail: View {
    let wordId: String
    let expanded: Bool

    @State private var fullWord: Word?
    @State private var loading = false
    @State private var error: Error?

    var body: some View {
        Group {
            if self.expanded {
                if let fullWord {
                    WordDetailSections(word: fullWord)
                } else if self.error != nil {
                    Text("詳情載入失敗")
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiInk3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s6)
                } else {
                    ProgressView()
                        .tint(.tujiTeal)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s6)
                }
            } else {
                PullUpHint()
            }
        }
        .task(id: self.expanded) {
            if self.expanded { await self.load() }
        }
    }

    private func load() async {
        guard self.fullWord == nil, !self.loading else { return }
        self.loading = true
        defer { self.loading = false }
        do {
            let settings = SettingsStore.shared.current
            self.fullWord = try await APIClient.shared.get(
                .word(
                    id: self.wordId,
                    lang: settings.uiLang,
                    learning: settings.learningDirection.rawValue
                )
            )
        } catch {
            self.error = error
        }
    }
}
