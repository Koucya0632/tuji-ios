// 場面練習 — every 場面. Up to six it is one plain list; past that it groups
// by where on the trip they happen, with chips that jump to a group.

import SwiftUI

struct SceneListView: View {
    let user: SessionUser?
    var catalog: SceneCatalog = .bundled

    @Environment(SettingsStore.self) private var settings
    @State private var jumpedTo: String?
    private let store = SceneProgressStore.shared

    private var grouped: Bool {
        self.catalog.scenes.count > 6
    }

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text("場面練習")
                            .font(.tujiH2)
                            .foregroundStyle(.tujiInk)
                        Text("結帳、點餐時，店員會問你的話。")
                            .font(.tujiBodySm)
                            .foregroundStyle(.tujiInk2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.s4)
                    .padding(.top, 12)
                    .id(Self.top)
                    if self.grouped {
                        self.chips(proxy)
                        ForEach(self.catalog.groups) { group in
                            Text(verbatim: group.title.resolved(self.language))
                                .font(.tujiLabel)
                                .tracking(1)
                                .foregroundStyle(.tujiInk2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Space.s4)
                                .padding(.top, 28)
                                .padding(.bottom, Space.s2)
                                .id(group.id)
                            self.rows(group.scenes, compact: true)
                        }
                    } else {
                        self.rows(self.catalog.scenes, compact: false).padding(.top, Space.s4)
                    }
                    Label("不用網路也能看、能播。", systemImage: "airplane")
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, Space.s4)
                }
            }
        }
        .background(.tujiPaper)
        .navigationTitle("場面練習")
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if let user { self.store.use(account: user.id) }
        }
    }

    private var language: UILanguage {
        self.settings.current.uiLanguage
    }

    private static let top = "top"

    /// Jumps to a group; 全部 goes back to the top. The tag last tapped is
    /// filled, 全部 until one is.
    private func chips(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                self.chip(Text("全部"), selected: self.jumpedTo == nil) {
                    self.jumpedTo = nil
                    withAnimation { proxy.scrollTo(Self.top, anchor: .top) }
                }
                ForEach(self.catalog.groups) { group in
                    self
                        .chip(
                            Text(verbatim: group.title.resolved(self.language)),
                            selected: self.jumpedTo == group.id
                        ) {
                            self.jumpedTo = group.id
                            withAnimation { proxy.scrollTo(group.id, anchor: .top) }
                        }
                }
            }
            .padding(.horizontal, Space.s4)
        }
        .padding(.top, 20)
    }

    private func chip(_ title: Text, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title
                .font(.tujiLabel)
                .foregroundStyle(selected ? .tujiPaper : .tujiInk2)
                .padding(.horizontal, Space.s3)
                .frame(height: 36)
                .background(selected ? Color.tujiInk : Color.clear, in: .capsule)
                .overlay(Capsule().strokeBorder(selected ? Color.clear : Color.tujiRule, lineWidth: 1))
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func rows(_ scenes: [PracticeScene], compact: Bool) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(.tujiRule).frame(height: 1)
            ForEach(scenes) { scene in
                NavigationLink(value: NavRoute.sceneDetail(id: scene.id)) {
                    if compact { self.compactRow(scene) } else { self.row(scene) }
                }
                .buttonStyle(.plain)
                Rectangle().fill(.tujiRule).frame(height: 1)
            }
        }
    }

    /// A grouped list's row: the title, then progress, or the question count
    /// for a scene not started; a lock in place of the chevron when this
    /// account cannot practise it.
    private func compactRow(_ scene: PracticeScene) -> some View {
        let today = LocalDay(Date(), calendar: .current)
        let status = ScenePractice.status(scene, book: self.store.book, today: today)
        let locked = !scene.canPractise(LiveEffectiveEntitlement.shared.tier)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: status == .notStarted ? 2 : 4) {
                Text(verbatim: scene.title.resolved(self.language))
                    .font(.tujiBody(.strong))
                    .foregroundStyle(.tujiInk)
                if status == .notStarted {
                    Text("\(scene.questions.count) 句")
                        .font(.scene(13, bold: false))
                        .foregroundStyle(.tujiInk3)
                } else {
                    HStack(spacing: 10) {
                        SceneSegments(practised: scene.practised(in: self.store.book), height: 3, spacing: 2)
                            .frame(width: 64)
                        SceneStatusText(scene: scene, status: status, cursor: self.store.book.cursors[scene.id])
                            .font(.scene(13, bold: false))
                            .foregroundStyle(.tujiInk2)
                    }
                }
            }
            Spacer(minLength: 0)
            if locked {
                HStack(spacing: 4) {
                    Image(systemName: "lock").font(.tujiIcon(12, weight: .bold))
                    Text("永久會員").font(.scene(12))
                }
                .foregroundStyle(.tujiInk3)
            } else {
                Image(systemName: "chevron.right")
                    .font(.tujiIcon(14, weight: .bold))
                    .foregroundStyle(.tujiInk3)
            }
        }
        .padding(.vertical, Space.s2)
        .padding(.leading, Space.s4)
        .padding(.trailing, Space.s3)
        .frame(minHeight: 56)
        .contentShape(.rect)
    }

    private func row(_ scene: PracticeScene) -> some View {
        let today = LocalDay(Date(), calendar: .current)
        let status = ScenePractice.status(scene, book: self.store.book, today: today)
        let locked = !scene.canPractise(LiveEffectiveEntitlement.shared.tier)
        return HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: scene.title.resolved(self.language))
                    .font(.tujiH3)
                    .foregroundStyle(.tujiInk)
                Text(verbatim: scene.questions.compactMap { $0.lookLine?.text }.joined(separator: " · "))
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
                    .lineLimit(1)
                HStack(spacing: Space.s3) {
                    if status != .notStarted {
                        SceneSegments(practised: scene.practised(in: self.store.book))
                            .frame(width: 120)
                    }
                    SceneStatusText(scene: scene, status: status, cursor: self.store.book.cursors[scene.id])
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk2)
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
            if locked {
                Text("永久會員")
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.tujiPaper2)
            }
            Image(systemName: "chevron.right")
                .font(.tujiIcon(14, weight: .bold))
                .foregroundStyle(.tujiInk3)
        }
        .padding(.vertical, 18)
        .padding(.leading, Space.s4)
        .padding(.trailing, Space.s3)
        .contentShape(.rect)
    }
}

/// The one line a list row and 今天's card say about where a scene stands.
struct SceneStatusText: View {
    let scene: PracticeScene
    let status: SceneStatus
    let cursor: Int?

    var body: some View {
        switch self.status {
        case .notStarted:
            Text("\(self.scene.questions.count) 句 · 約 \(self.scene.minutes) 分鐘")
        case let .inProgress(practised, _):
            Text("練到第 \((self.cursor ?? practised) + 1) 句")
        case .reviewDue:
            Text("今天複習")
        case .reviewLater:
            Text("明天複習")
        case .complete:
            Text("複習完了")
        }
    }
}
