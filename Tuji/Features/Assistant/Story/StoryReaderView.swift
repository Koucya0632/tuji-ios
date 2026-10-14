// 情境故事 — reading one. Narration sits on the paper; 助手貓's lines sit beside
// its face, the person's on the right, each with its kana reading (Japanese)
// and its translation under it. The picked items follow the story, one tap
// from their own pages.

import SwiftUI

struct StoryReaderView: View {
    let story: Story
    let picked: [CardWord]
    let close: () -> Void

    private static let faceSize: CGFloat = 32

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text(verbatim: self.story.title)
                    .font(.tujiH2)
                    .foregroundStyle(.tujiInk)
                Text(verbatim: self.story.intro)
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk2)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(self.story.segments.enumerated()), id: \.offset) { _, segment in
                    self.segment(segment)
                }
                self.words
                BBtn(title: "換個情境再寫一個", bg: .tujiPaper2, fullWidth: true, action: self.close)
                    .padding(.top, Space.s2)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s4)
        }
    }

    @ViewBuilder
    private func segment(_ segment: Story.Segment) -> some View {
        switch segment.speaker {
        case .narrator:
            Text(verbatim: segment.text)
                .font(.tujiBodySm)
                .italic()
                .foregroundStyle(.tujiInk3)
                .fixedSize(horizontal: false, vertical: true)
        case .cat:
            HStack(alignment: .top, spacing: Space.s2) {
                Mascot(pose: .face, size: Self.faceSize)
                    .accessibilityLabel(Text("助手貓"))
                self.line(segment)
                Spacer(minLength: Space.s5)
            }
        case .you:
            HStack {
                Spacer(minLength: Space.s5 + Self.faceSize)
                self.line(segment)
                    .accessibilityLabel(Text("你：\(segment.text)"))
            }
        }
    }

    private func line(_ segment: Story.Segment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: segment.text)
                .font(.tujiBody(.strong))
                .foregroundStyle(.tujiInk)
            if let reading = segment.reading {
                Text(verbatim: reading)
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
            }
            if let translation = segment.translation {
                Text(verbatim: translation)
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk2)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .background(segment.speaker == .cat ? Color.tujiPaper2 : .tujiBrandPrimary.opacity(0.35))
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("故事裡的單字")
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiInk3)
                .padding(.bottom, Space.s1)
            ForEach(self.picked) { word in
                NavigationLink(value: NavRoute.wordDetail(id: word.id)) {
                    HStack(spacing: Space.s3) {
                        Text(verbatim: word.word)
                            .font(.tujiBody(.strong))
                            .foregroundStyle(.tujiInk)
                        Text(verbatim: word.chinese)
                            .font(.tujiBodySm)
                            .foregroundStyle(.tujiInk3)
                        Spacer(minLength: Space.s2)
                        TujiRowAccessory()
                    }
                    .frame(minHeight: 52)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Rectangle().fill(.tujiRule).frame(height: Border.bw1)
            }
        }
        .padding(.top, Space.s3)
    }
}
