import SwiftUI

/// Controls occupy their own hit targets; none is a story-advance surface.
struct StoryStageControls: View {
    let segment: Story.Segment?
    @Binding var translating: Bool
    let waiting: Bool
    let replay: () -> Void
    let practice: () -> Void
    let advance: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicType

    private var compact: Bool {
        self.dynamicType >= .xxLarge
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s3) {
                self.learningControls
                if self.compact {
                    Spacer(minLength: 0)
                    self.advanceControl
                }
            }
            if !self.compact {
                HStack {
                    Spacer(minLength: 0)
                    self.advanceControl
                }
            }
        }
        .foregroundStyle(.tujiInk)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var learningControls: some View {
        if let segment = self.segment, segment.speaker != .narrator {
            Button(action: self.replay) { self.label("發音", icon: "speaker.wave.2") }
            if segment.translation?.isEmpty == false {
                Button { self.translating.toggle() } label: {
                    self.label("譯", icon: "character.bubble")
                }
                .accessibilityLabel(self.translating ? Text("隱藏翻譯") : Text("顯示翻譯"))
                .foregroundStyle(self.translating ? Color.tujiBrandSecondary : .tujiInk)
            }
            Button(action: self.practice) { self.label("跟讀", icon: "mic") }
        }
    }

    @ViewBuilder
    private var advanceControl: some View {
        if self.waiting {
            if self.compact {
                ProgressView().accessibilityLabel(Text("Moira 正在寫故事…"))
            } else {
                Text("Moira 正在寫故事…").font(.tujiBodySm)
            }
        } else {
            Button(action: self.advance) {
                Group {
                    if self.compact {
                        Image(systemName: "arrowtriangle.right.fill").font(.tujiIcon(20))
                    } else {
                        HStack(spacing: Space.s1) {
                            Text("點擊繼續")
                            Image(systemName: "arrowtriangle.right.fill").font(.tujiIcon(9))
                        }
                        .font(.tujiLabel)
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
            }
            .accessibilityLabel(Text("點擊繼續"))
        }
    }

    private func label(_ title: LocalizedStringKey, icon: String) -> some View {
        Group {
            if self.compact {
                Image(systemName: icon).font(.tujiIcon(20))
            } else {
                Label(title, systemImage: icon).font(.tujiBodySm(.strong))
            }
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(.rect)
        .accessibilityLabel(Text(title))
    }
}
