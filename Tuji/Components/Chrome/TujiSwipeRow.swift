// Swipe-to-reveal for rows that no longer live in a `List`.
//
// `.swipeActions` is a `List` modifier. Outside one it does not warn, it does not
// fail to compile — it simply does nothing, so replacing the list would have
// silently taken swipe-to-delete away from 圖鑑管理.
//
// The revealed action is a full-height ink block, matching the way every other
// "this is the committed choice" surface in the system looks. Destructive
// actions use `tujiAlert` for the same reason a destructive row inverts on press:
// that tap has weight.

import SwiftUI

struct TujiSwipeRow<Content: View>: View {
    let actionLabel: LocalizedStringKey
    let systemImage: String
    var destructive: Bool = true
    let action: () -> Void
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static var actionWidth: CGFloat {
        96
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                self.close()
                self.action()
            } label: {
                VStack(spacing: Space.s1) {
                    Image(systemName: self.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                    Text(self.actionLabel)
                        .font(.tujiLabel)
                        .tracking(0.5)
                }
                .foregroundStyle(.tujiPaper)
                .frame(width: Self.actionWidth)
                .frame(maxHeight: .infinity)
                .background(self.destructive ? Color.tujiAlert : .tujiInk)
            }
            .accessibilityHidden(true)

            self.content
                .background(.tujiPaper)
                .offset(x: self.offset)
                .gesture(self.swipe)
        }
        .clipped()
        // The gesture is a shortcut, never the only route: VoiceOver users and
        // anyone who does not discover it reach the same action from the row's
        // detail screen and from multi-select.
        .accessibilityAction(named: Text(self.actionLabel)) { self.action() }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let base = self.revealed ? -Self.actionWidth : 0
                self.offset = min(0, max(-Self.actionWidth, base + value.translation.width))
            }
            .onEnded { _ in
                let shouldReveal = self.offset < -Self.actionWidth / 2
                withAnimation(self.reduceMotion ? nil : Motion.ease(Motion.d2)) {
                    self.offset = shouldReveal ? -Self.actionWidth : 0
                    self.revealed = shouldReveal
                }
            }
    }

    private func close() {
        withAnimation(self.reduceMotion ? nil : Motion.ease(Motion.d2)) {
            self.offset = 0
            self.revealed = false
        }
    }
}
