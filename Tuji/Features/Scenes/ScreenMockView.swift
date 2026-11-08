// A drawn register or ordering screen. The Japanese on it is the machine's, so
// it is never translated; the caption under it says real screens differ.

import SwiftUI

struct ScreenMockView: View {
    let screen: ScreenMock
    /// Buttons already tried and wrong.
    var tried: Set<String> = []
    /// Set once answered, to mark the right button.
    var correctId: String?
    var onTap: ((String) -> Void)?

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: self.screen.heading)
                .font(.tujiBodySm(.strong))
                .foregroundStyle(.tujiMachineFace)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.tujiMachineBar)
            VStack(alignment: .leading, spacing: 10) {
                if let detail = self.screen.detail {
                    Text(verbatim: detail)
                        .font(.tujiBody(.strong))
                        .foregroundStyle(.tujiMachineBezel)
                }
                LazyVGrid(columns: self.columns, spacing: 10) {
                    ForEach(self.screen.buttons, id: \.choiceId) { button in
                        self.machineButton(button)
                    }
                }
            }
            .padding(14)
        }
        .background(.tujiMachineFace)
        .padding(12)
        .background(.tujiMachineBezel)
    }

    private func machineButton(_ button: ScreenMock.Button) -> some View {
        let isCorrect = self.correctId == button.choiceId
        let isTried = self.tried.contains(button.choiceId)
        return Button {
            self.onTap?(button.choiceId)
        } label: {
            Text(verbatim: button.ja)
                .font(.tujiBody(.strong))
                .foregroundStyle(isCorrect ? .tujiPaper : .tujiMachineBezel)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 64)
                .padding(.horizontal, Space.s1)
                .background(isCorrect ? .tujiInk : .tujiMachineFace)
                .overlay(Rectangle().strokeBorder(.tujiMachineEdge, lineWidth: 1))
                .overlay(Rectangle().strokeBorder(
                    isTried ? .tujiAlert : isCorrect ? .tujiAccumulation : .clear,
                    lineWidth: 3
                ))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(self.onTap != nil && !isTried && self.correctId == nil)
        .accessibilityLabel(Text(verbatim: button.ja))
        .accessibilityValue(isTried ? Text("答錯") : isCorrect ? Text("正確") : Text(verbatim: ""))
    }
}

/// The same screen at a glance, for 進店前看一眼: the heading and the buttons,
/// the right one outlined.
struct ScreenMockThumbnail: View {
    let screen: ScreenMock
    let correctId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: self.screen.heading)
                .font(.scene(11))
                .foregroundStyle(.tujiMachineFace)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, Space.s1)
                .background(.tujiMachineBar)
            VStack(alignment: .leading, spacing: Space.s2) {
                if let detail = self.screen.detail {
                    Text(verbatim: detail)
                        .font(.scene(13))
                        .foregroundStyle(.tujiMachineBezel)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(self.screen.buttons, id: \.choiceId) { button in
                        let isCorrect = button.choiceId == self.correctId
                        Text(verbatim: button.ja)
                            .font(.scene(12))
                            .foregroundStyle(isCorrect ? .tujiInk : .tujiMachineBar)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .overlay(Rectangle().strokeBorder(
                                isCorrect ? .tujiInk : .tujiMachineEdge,
                                lineWidth: isCorrect ? 2 : 1
                            ))
                    }
                }
            }
            .padding(Space.s2)
        }
        .background(.tujiMachineFace)
        .padding(6)
        .background(.tujiMachineBezel)
        .frame(width: 220, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
