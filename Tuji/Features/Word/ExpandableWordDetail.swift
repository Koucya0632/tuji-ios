// Shared "drag up to reveal full details" pieces for the expandable peek /
// review sheets.
//
// `PullUpHint` is the affordance shown in the resting-detent whitespace.
// `ExpandableWordDetail` swaps that hint for the full WordDetailSections once
// the sheet is expanded, lazy-loading the Word the first time so a user who
// never pulls up doesn't trigger a network call.
//
// The load goes through `WordDetailVM`, which is the thing that knows an
// `atlas:`-prefixed id is a 自製圖鑑 item and not a catalogue word. This view
// used to hold a second loader that called the catalogue route unconditionally
// — so pulling this sheet up on a custom card during 複習 or 學新字 asked
// `/api/words/atlas:…` for a word that route has never heard of and rendered
// 「詳情載入失敗」. Custom cards are in both study flows: `ReviewFlowView`
// guards `card.id.hasPrefix("atlas:")` for exactly that reason.
//
// **The prefix is the routing decision, so it lives with the routing** — the
// sentence `WordDetailVM` already carried, with one caller that ignored it.

import SwiftUI

/// Affordance hinting the sheet can be dragged up to reveal full details.
struct PullUpHint: View {
    var body: some View {
        VStack(spacing: Space.s1) {
            Image(systemName: "chevron.up")
                .font(.tujiIcon(14, weight: .semibold))
                .symbolEffect(.bounce, options: .repeating)
            Text("向上拉看完整詳情")
                .font(.tujiLabel)
        }
        .foregroundStyle(.tujiInk3)
        .frame(maxWidth: .infinity)
    }
}

/// Shows `PullUpHint` while collapsed; once `expanded`, lazy-loads the full
/// Word and renders `WordDetailSections`. Used by both the study peek sheet
/// and the review reveal sheet.
struct ExpandableWordDetail: View {
    let wordId: String
    let expanded: Bool

    @Environment(SettingsStore.self) private var settings
    @State private var vm = WordDetailVM()

    var body: some View {
        Group {
            if self.expanded {
                if let fullWord = vm.word {
                    WordDetailSections(word: fullWord)
                } else if self.vm.error != nil {
                    Text("詳情載入失敗")
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s4)
                } else {
                    TujiImagePlaceholder()
                        .tint(.tujiCurrent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s4)
                }
            } else {
                PullUpHint()
            }
        }
        .task(id: self.expanded) {
            if self.expanded { await self.load() }
        }
    }

    /// No analytics: the sheet is a peek inside a study session, and the return
    /// value `WordDetailVM.load` offers exists for 圖鑑詳情's page view.
    private func load() async {
        let current = self.settings.current
        await self.vm.load(
            id: self.wordId,
            lang: current.uiLanguage.contentLanguageCode,
            learning: current.learningDirection.rawValue
        )
    }
}
