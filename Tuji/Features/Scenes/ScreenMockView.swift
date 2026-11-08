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

    private let columns = [GridItem(.flexible(), spacing: Space.s2), GridItem(.flexible(), spacing: Space.s2)]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text(verbatim: self.screen.heading)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.tujiInk)
                if let detail = self.screen.detail {
                    Text(verbatim: detail)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tujiInk2)
                }
                LazyVGrid(columns: self.columns, spacing: Space.s2) {
                    ForEach(self.screen.buttons, id: \.choiceId) { button in
                        self.machineButton(button)
                    }
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tujiPaper)
            .padding(10)
            .background(.tujiInk)
            Text("畫面依店家不同")
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
        }
    }

    private func machineButton(_ button: ScreenMock.Button) -> some View {
        let isCorrect = self.correctId == button.choiceId
        let isTried = self.tried.contains(button.choiceId)
        return Button {
            self.onTap?(button.choiceId)
        } label: {
            Text(verbatim: button.ja)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isTried ? .tujiInk3 : .tujiInk)
                .strikethrough(isTried)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 56)
                .padding(.horizontal, Space.s1)
                .background(isCorrect ? .tujiBrandPrimary : .tujiAccumulationSoft)
                .overlay(
                    Rectangle().stroke(isCorrect ? .tujiInk : .tujiAccumulation, lineWidth: Border.bw2)
                )
        }
        .buttonStyle(.plain)
        .disabled(self.onTap == nil || isTried || self.correctId != nil)
        .accessibilityLabel(Text(verbatim: button.ja))
    }
}
