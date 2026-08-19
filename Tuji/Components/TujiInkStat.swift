// One number on an ink block — 作者主頁's 公開項目/被收藏 and 合集詳情's
// 內容/被收藏.
//
// Two screens that share a visual language ("it also mirrors the ink block on
// 今天: one is 'you', this one is 'them'") drew the same ten lines twice, and
// gave two different answers to *who localises the label*:
//
//   作者主頁:  stat(value: String, label: String)         → Text(verbatim:), caller calls tujiLocalized
//   合集詳情:  stat(title: LocalizedStringKey, value: Int) → Text(title), SwiftUI resolves
//
// Both render correctly today, but they are the two halves of the trap this
// project has already been bitten by: a `String`-typed label skips the uiLang
// switch unless the caller remembers `tujiLocalized`, while a
// `LocalizedStringKey` follows the environment locale on its own. One of those
// is a rule; the other is a thing to remember.

import SwiftUI

/// A count and its caption, set on an ink block.
struct TujiInkStat: View {
    /// A key, not a resolved `String`: it is rendered by a `Text` inside a view
    /// whose environment locale already follows uiLang.
    let label: LocalizedStringKey
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(self.value)")
                .font(.tujiMono)
                .foregroundStyle(.tujiPaper)
            Text(self.label)
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiPaper.opacity(0.6))
                .lineLimit(1)
                .fixedSize()
        }
    }
}

#Preview {
    HStack(spacing: Space.s4) {
        TujiInkStat(label: "公開項目", value: 12)
        TujiInkStat(label: "被收藏", value: 348)
    }
    .padding(Space.s4)
    .background(.tujiInk)
}
