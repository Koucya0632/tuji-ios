import SwiftUI

/// Long word notes scroll independently, leaving both ending actions reachable.
struct StoryEndingPanel: View {
    let story: Story?
    let picked: [CardWord]
    let writing: StoryBuilderModel.Writing
    let maxHeight: CGFloat
    let restart: () -> Void
    let close: () -> Void

    var body: some View {
        StoryDialogue(name: nil, isReader: false, maxHeight: self.maxHeight, contentKey: -1) {
            VStack(alignment: .leading, spacing: Space.s2) {
                if case let .failed(failure) = self.writing {
                    Text(verbatim: StoryBuilderView.sentence(for: failure))
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !self.picked.isEmpty {
                    Text("故事裡的單字")
                        .font(.tujiLabel)
                        .tracking(0.5)
                        .foregroundStyle(.tujiInk3)
                    ForEach(self.picked) { word in
                        NavigationLink(value: NavRoute.wordDetail(id: word.id)) {
                            HStack(spacing: Space.s3) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: word.word)
                                        .font(.tujiBody(.strong))
                                        .foregroundStyle(.tujiInk)
                                    Text(verbatim: self.story?.wordNotes?.first { $0.id == word.id }?.note ?? word
                                        .chinese)
                                        .font(.tujiBodySm)
                                        .foregroundStyle(.tujiInk3)
                                }
                                Spacer(minLength: Space.s2)
                                TujiRowAccessory()
                            }
                            .frame(minHeight: 48)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } controls: {
            HStack(spacing: Space.s2) {
                BBtn(title: "再看一次", bg: .tujiPaper2, fullWidth: true, action: self.restart)
                BBtn(title: "換個情境", fullWidth: true, action: self.close)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}
