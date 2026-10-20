// A tab introducing itself the first time it is opened after the tour.
//
// The tour used to point at the tab bar and read every tab's purpose out in
// one breath, before the reader had been to any of them. Now each tab says
// what it is for when the reader arrives: one line from the cat, no dimming,
// gone on a tap. 今天 has none — the tour itself happened there.

import SwiftUI

enum TabTip {
    /// Stored in `OnboardingState.tabTipsSeen`; spelled once, here.
    static func key(for tab: MainTab) -> String? {
        switch tab {
        case .today: nil
        case .cards: "cards"
        case .community: "community"
        case .me: "me"
        }
    }

    static func text(for tab: MainTab) -> LocalizedStringKey? {
        switch tab {
        case .today: nil
        case .cards: "單字都收在這裡，上面可以切換官方主題、你拍的和收藏。"
        case .community: "看看大家都拍了什麼，喜歡的可以收進自己的圖鑑。"
        case .me: "連續天數、學習成果和設定都在這裡。"
        }
    }

    /// Only at a tab's root — a tip about the tab is noise over a pushed word
    /// page — and never over the tour or a study session.
    static func shows(
        on tab: MainTab,
        armed: Bool,
        seen: Set<String>,
        atRoot: Bool,
        tourRunning: Bool,
        studyFocusActive: Bool
    )
        -> Bool
    {
        guard let key = self.key(for: tab) else { return false }
        return armed && !seen.contains(key) && atRoot && !tourRunning && !studyFocusActive
    }
}

struct TabTipBubble: View {
    let text: LocalizedStringKey
    let onDismiss: () -> Void

    var body: some View {
        Button(action: self.onDismiss) {
            MascotSpeechBubble(pose: .face, text: self.text)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
                .frame(maxWidth: .infinity)
                .background(.tujiPaper)
                .overlay(alignment: .top) {
                    Rectangle().fill(.tujiRule.opacity(0.2)).frame(height: Border.bw1)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("點一下關閉"))
    }
}
