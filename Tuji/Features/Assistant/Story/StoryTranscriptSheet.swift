import SwiftUI

struct StoryTranscriptSheet: View {
    let story: Story?
    let shown: Int
    let isSupermarket: Bool
    let close: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s3) {
                    if let story {
                        Text(verbatim: story.title).font(.tujiH3).foregroundStyle(.tujiInk)
                        Text(verbatim: story.intro).font(.tujiBodySm).foregroundStyle(.tujiInk2)
                    }
                    ForEach(
                        Array((self.story?.segments ?? []).prefix(self.shown).enumerated()),
                        id: \.offset
                    ) { _, segment in
                        VStack(alignment: .leading, spacing: 2) {
                            switch segment.speaker {
                            case .narrator:
                                Text(verbatim: segment.text).font(.tujiBodySm).italic().foregroundStyle(.tujiInk3)
                            case .cat, .you:
                                Text(verbatim: segment.speaker == .cat ? "Moira" : tujiLocalized("你"))
                                    .font(.tujiLabel)
                                    .foregroundStyle(.tujiInk3)
                                Text(verbatim: segment.text).font(.tujiBody(.strong)).foregroundStyle(.tujiInk)
                                if let translation = segment.translation {
                                    Text(verbatim: translation).font(.tujiBodySm).foregroundStyle(.tujiInk2)
                                }
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.tujiPaper)
            .navigationTitle(self.isSupermarket ? Text("紀錄") : Text("履歷"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("關閉") { self.close() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
