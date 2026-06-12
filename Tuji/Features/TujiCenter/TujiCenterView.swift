// Center "Tuji" tab — quick-action launcher. Full study landing comes in
// W4, so v1 surfaces a 隨機翻一張 shortcut and stub buttons for the
// upcoming new / review flows.

import SwiftUI

struct TujiCenterView: View {
    @Environment(WordsStore.self) private var words

    @State private var randomPick: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                self.hero
                self.actions
                self.upcoming
            }
            .padding(.horizontal, Space.s6)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s24)
        }
        .background(.tujiBg)
        .navigationDestination(item: self.$randomPick) { id in
            WordDetailView(id: id)
        }
        .task { await self.words.loadIfNeeded() }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Mascot(pose: .cheer, size: 96)
            Text("Tuji 探險")
                .font(.tujiH1)
                .foregroundStyle(.white)
            Text("挑一張卡開始今天的小驚喜")
                .font(.tujiBody)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s6)
        .background(.tujiBgInk, in: .rect(cornerRadius: Radius.xl))
    }

    private var actions: some View {
        VStack(spacing: Space.s3) {
            BBtn(
                title: "隨機翻一張",
                bg: .tujiYellow,
                fg: .tujiInk,
                fullWidth: true,
                icon: "shuffle",
                action: self.pickRandom
            )
            .disabled(self.words.words.isEmpty)
            NavigationLink(value: NavRoute.studyLanding(mode: .new)) {
                Text("開始學新字")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(StudyPillStyle(fg: .tujiInk, bg: .tujiTealSoft))
            NavigationLink(value: NavRoute.studyLanding(mode: .review)) {
                Text("今日復習")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(StudyPillStyle(fg: .white, bg: .tujiTeal))
        }
    }

    private var upcoming: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("即將推出")
                .font(.tujiOverline)
                .tracking(2)
                .foregroundStyle(.tujiTeal)
            Text("新字三步微課程、SRS 復習、答錯彈窗 — 全部都會回到這個 Tuji 中心。")
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s5)
        .background(.tujiCard, in: .rect(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(.tujiInk4.opacity(0.2), lineWidth: 1)
        )
    }

    private func pickRandom() {
        guard let pick = self.words.words.randomElement() else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        self.randomPick = pick.id
    }
}

private struct StudyPillStyle: ButtonStyle {
    let fg: Color
    let bg: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .heavy))
            .foregroundStyle(self.fg)
            .padding(.vertical, Space.s4)
            .padding(.horizontal, Space.s6)
            .background(self.bg, in: .rect(cornerRadius: Radius.lg))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

#Preview {
    NavigationStack {
        TujiCenterView()
            .environment(WordsStore.shared)
    }
}
