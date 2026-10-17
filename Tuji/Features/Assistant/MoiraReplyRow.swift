import SwiftUI

/// Moira's side of an AI 查詞 or AI 語法 conversation: her face, and the words
/// beside it rather than in a bubble — a card is far longer than a bubble can hold.
struct MoiraReplyRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Mascot(pose: .face, size: 36)
            VStack(alignment: .leading, spacing: Space.s3) { self.content }
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }
}
