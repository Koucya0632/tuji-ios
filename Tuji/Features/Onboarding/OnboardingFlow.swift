// 3-page marketing intro shown before Welcome on first launch. User can
// swipe or tap "下一步"; either "跳過" or "開始使用" on the last page
// marks introDone and lets RootView swap to Welcome.
//
// Visual scope kept minimal — placeholder artwork is SF Symbols. The
// final design will swap in real Tuji tiles + heatmap art when the
// design files land.

import SwiftUI

struct OnboardingFlow: View {
    @Environment(OnboardingState.self) private var state

    @State private var page: Int = 0

    private let pages: [Page] = [
        Page(
            artwork: .grid,
            title: "用圖學英文",
            lines: ["看一張圖，記住一個字", "生活中看到 → 立刻想起來"]
        ),
        Page(
            artwork: .srs,
            title: "每天 3 分鐘",
            lines: ["SRS 智能複習", "快忘了才出現 → 一次記牢"]
        ),
        Page(
            artwork: .streak,
            title: "看見自己變強",
            lines: ["每天進步一點", "累積成自己的圖鑑"]
        )
    ]

    var body: some View {
        ZStack(alignment: .top) {
            Color.tujiBg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { idx, p in
                        PageView(page: p)
                            .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: page)

                indicator

                BBtn(
                    title: page == pages.count - 1 ? "開始使用" : "下一步",
                    bg: .tujiTeal,
                    fg: .white,
                    fullWidth: true,
                    action: advance
                )
                .padding(.horizontal, Space.s6)
                .padding(.bottom, Space.s8)
                .padding(.top, Space.s4)
            }
        }
    }

    // MARK: - Bits

    private var topBar: some View {
        HStack {
            Spacer()
            if page < pages.count - 1 {
                Button {
                    state.introDone = true
                } label: {
                    Text("跳過")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.tujiInk3)
                        .padding(.vertical, Space.s2)
                        .padding(.horizontal, Space.s4)
                }
            }
        }
        .padding(.top, Space.s4)
        .padding(.horizontal, Space.s4)
    }

    private var indicator: some View {
        HStack(spacing: Space.s2) {
            ForEach(0..<pages.count, id: \.self) { i in
                Capsule()
                    .fill(i == page ? Color.tujiTeal : .tujiInk4.opacity(0.4))
                    .frame(width: i == page ? 22 : 7, height: 7)
                    .animation(.easeOut(duration: 0.25), value: page)
            }
        }
        .padding(.vertical, Space.s4)
    }

    private func advance() {
        if page < pages.count - 1 {
            withAnimation(.easeInOut(duration: 0.3)) { page += 1 }
        } else {
            state.introDone = true
        }
    }
}

// MARK: - Page

struct Page: Identifiable {
    let id = UUID()
    let artwork: Artwork
    let title: String
    let lines: [String]

    enum Artwork { case grid, srs, streak }
}

private struct PageView: View {
    let page: Page

    var body: some View {
        VStack(spacing: 0) {
            artwork
                .frame(maxWidth: .infinity)
                .padding(Space.s6)
                .background(.tujiCard, in: .rect(cornerRadius: Radius.xl))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl)
                        .stroke(.tujiInk4.opacity(0.25), lineWidth: 1)
                )
                .tujiCardShadow()
                .padding(.horizontal, Space.s6)
                .padding(.top, Space.s6)

            VStack(spacing: Space.s2) {
                Text(page.title)
                    .font(.tujiH2)
                    .foregroundStyle(.tujiInk)
                    .padding(.top, Space.s6)

                VStack(spacing: 2) {
                    ForEach(page.lines, id: \.self) { line in
                        Text(line)
                            .font(.tujiBodyLg)
                            .foregroundStyle(.tujiInk2)
                    }
                }
                .padding(.top, Space.s2)
                .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        switch page.artwork {
        case .grid:
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: Space.s3), GridItem(.flexible(), spacing: Space.s3)],
                spacing: Space.s3
            ) {
                ForEach(0..<4, id: \.self) { i in
                    TileStub(systemImage: ["fork.knife", "cup.and.saucer.fill", "leaf.fill", "carrot.fill"][i])
                }
            }
            .frame(height: 220)
        case .srs:
            VStack(spacing: Space.s3) {
                TileStub(systemImage: "carrot.fill").frame(height: 120)
                VStack(spacing: Space.s2) {
                    OptionRow(text: "lettuce", state: .idle)
                    OptionRow(text: "carrot", state: .selected)
                    OptionRow(text: "cucumber", state: .idle)
                }
            }
            .frame(height: 250)
        case .streak:
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill").foregroundStyle(.tujiCoral)
                    Text("連勝").font(.tujiCaption).foregroundStyle(.white.opacity(0.7))
                }
                HStack(alignment: .lastTextBaseline, spacing: Space.s2) {
                    Text("23").font(.system(size: 52, weight: .heavy)).foregroundStyle(.white)
                    Text("天").font(.tujiH4).foregroundStyle(.white.opacity(0.7))
                }
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7),
                    spacing: 5
                ) {
                    ForEach(0..<21, id: \.self) { i in
                        let strength = (i * 7 + 3) % 10
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.white.opacity(strength < 3 ? 0.12 : strength < 6 ? 0.35 : 0.85))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
                .padding(.top, Space.s2)
            }
            .padding(Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tujiInk, in: .rect(cornerRadius: Radius.xl))
        }
    }
}

private struct TileStub: View {
    let systemImage: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(.tujiTealSoft)
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.tujiTeal)
        }
    }
}

private struct OptionRow: View {
    let text: String
    let state: State

    enum State { case idle, selected }

    var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(state == .selected ? .tujiTeal : .tujiInk2)
            Spacer()
            if state == .selected {
                Image(systemName: "checkmark").foregroundStyle(.tujiTeal)
            }
        }
        .padding(.vertical, Space.s3)
        .padding(.horizontal, Space.s4)
        .background(
            state == .selected ? Color.tujiTealSoft : Color.tujiCard,
            in: .rect(cornerRadius: Radius.md)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(.tujiInk4.opacity(state == .selected ? 0 : 0.25), lineWidth: 1)
        )
    }
}

#Preview {
    OnboardingFlow().environment(OnboardingState.shared)
}
