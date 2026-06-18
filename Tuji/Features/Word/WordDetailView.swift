// Per-word detail page (§III.H).
//
// Loads the full Word from GET /api/words/{id} the first time it appears.
// Sections render conditionally — etymology / examples / forms /
// collocations may all be empty for some words.

import Nuke
import NukeUI
import SwiftUI

struct WordDetailView: View {
    let id: String

    @Environment(\.dismiss) private var dismiss
    @Environment(StudyFocus.self) private var studyFocus
    @Environment(SettingsStore.self) private var settings

    @State private var word: Word?
    @State private var loading = false
    @State private var error: Error?
    @State private var selectedDetailTab: WordDetailTab = .definition

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                if let word {
                    self.content(word, width: geo.size.width)
                } else if let error {
                    self.errorState(error)
                        .frame(width: geo.size.width)
                } else {
                    ProgressView()
                        .tint(.tujiTeal)
                        .padding(.top, Space.s16)
                        .frame(width: geo.size.width)
                }
            }
        }
        .background(.tujiBg)
        .toolbar(.hidden, for: .navigationBar)
        // Hide the custom TujiTabBar on this full-screen detail page by
        // entering study-focus (MainTabsView watches this flag). While the
        // bar is hidden there's nothing to reserve space for, so the local
        // bottom inset collapses to 0; the 78pt fallback only applies if
        // the bar were ever visible here.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: self.studyFocus.active ? 0 : 78)
        }
        .onAppear { self.studyFocus.enter() }
        .onDisappear { self.studyFocus.exit() }
        .task { await self.load() }
        .onChange(of: self.word?.id) { _, _ in
            guard let new = self.word else { return }
            let tabs = Self.availableTabs(for: new)
            if !tabs.contains(self.selectedDetailTab), let first = tabs.first {
                self.selectedDetailTab = first
            }
        }
    }

    // MARK: - States

    private func content(_ w: Word, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            self.hero(w)
            self.titleRow(w)
            let tabs = Self.availableTabs(for: w)
            if !tabs.isEmpty {
                self.sectionTitle("字詞資料 · DETAILS")
                if tabs.count > 1 {
                    self.tabPills(tabs)
                }
                Group {
                    switch self.selectedDetailTab {
                    case .definition:
                        if let chineseDef = w.chineseDefinition, !chineseDef.isEmpty {
                            self.definitionCard(w, chineseDef: chineseDef)
                        }
                    case .forms:
                        if let forms = w.forms, !forms.isEmpty {
                            self.formsCard(forms)
                        }
                    case .origin:
                        if let etymology = w.etymology, !etymology.isEmpty {
                            self.etymologyCard(etymology)
                        }
                    case .collocations:
                        if let collocations = w.collocations, !collocations.isEmpty {
                            self.collocationsRow(collocations, zh: w.collocationsZh)
                        }
                    }
                }
            }
            if let examples = w.examples, !examples.isEmpty {
                self.sectionTitle("例句 · EXAMPLE")
                self.examplesCard(examples)
            }
        }
        .padding(.horizontal, Space.s6)
        .padding(.top, Space.s2)
        .padding(.bottom, Space.s8)
        .frame(width: width, alignment: .leading)
    }

    private func tabPills(_ tabs: [WordDetailTab]) -> some View {
        HStack(spacing: Space.s2) {
            ForEach(tabs, id: \.self) { tab in
                let active = tab == self.selectedDetailTab
                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        self.selectedDetailTab = tab
                    }
                } label: {
                    Text(tab.label)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(active ? .white : .tujiTeal)
                        .padding(.horizontal, Space.s3)
                        .padding(.vertical, Space.s2)
                        .background(active ? Color.tujiTeal : Color.tujiTealSoft)
                        .clipShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private static func availableTabs(for w: Word) -> [WordDetailTab] {
        var tabs: [WordDetailTab] = []
        if let zh = w.chineseDefinition, !zh.isEmpty { tabs.append(.definition) }
        if let forms = w.forms, !forms.isEmpty { tabs.append(.forms) }
        if let ety = w.etymology, !ety.isEmpty { tabs.append(.origin) }
        if let cols = w.collocations, !cols.isEmpty { tabs.append(.collocations) }
        return tabs
    }
}

private enum WordDetailTab: Hashable, CaseIterable {
    case definition
    case forms
    case origin
    case collocations

    var label: String {
        switch self {
        case .definition: "譯義"
        case .forms: "詞形"
        case .origin: "來源"
        case .collocations: "搭配"
        }
    }
}

extension WordDetailView {
    private func errorState(_ err: Error) -> some View {
        VStack(spacing: Space.s4) {
            Spacer().frame(height: Space.s16)
            Mascot(pose: .think, size: 80)
            Text("找不到這個字")
                .font(.tujiH3)
                .foregroundStyle(.tujiInk)
            Text(err.localizedDescription)
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk3)
                .multilineTextAlignment(.center)
            BBtn(title: "返回", fullWidth: false, action: { self.dismiss() })
        }
        .padding(.horizontal, Space.s6)
    }

    // MARK: - Sections

    /// Fixed image-card height so every word — wide, tall, square — gets an
    /// identically sized hero. The image always fits inside (never cropped),
    /// so layout stays neat and consistent across the dictionary.
    private static let imageCardHeight: CGFloat = 220

    private func hero(_ w: Word) -> some View {
        VStack(spacing: Space.s4) {
            // Controls live in their own row above the image so the back
            // button and favourite toggle are always fully visible, never
            // clipped by the notch or overlapping the artwork.
            HStack {
                self.circleControl(systemImage: "chevron.left") { self.dismiss() }
                Spacer()
                FavoriteButton(wordId: w.id)
            }

            // Consistent white image card. The picture is shown .fit with
            // padding, so the whole subject is visible regardless of its
            // aspect ratio or baked-in background.
            ZStack {
                RoundedRectangle(cornerRadius: Radius.xl)
                    .fill(.tujiCard)
                LazyImage(url: w.imageURL) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fit)
                            .padding(Space.s4)
                    } else if state.error != nil {
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                            .foregroundStyle(.tujiInk4)
                    } else {
                        ProgressView().tint(.tujiTeal)
                    }
                }
                .pipeline(.shared)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.imageCardHeight)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl)
                    .stroke(.tujiInk4.opacity(0.25), lineWidth: 1)
            )
        }
    }

    private func titleRow(_ w: Word) -> some View {
        HStack(alignment: .top, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(w.word)
                    .font(.tujiH1)
                    .foregroundStyle(.tujiInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack(spacing: Space.s2) {
                    if let pron = w.pronunciation {
                        Text(pron)
                            .font(.tujiMono)
                            .foregroundStyle(.tujiInk2)
                    }
                    if let pos = w.partOfSpeech, !pos.isEmpty {
                        Text(pos)
                            .font(.tujiCaption)
                            .italic()
                            .foregroundStyle(.tujiInk3)
                    }
                    if let cefr = w.cefrLevel {
                        Text(cefr)
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.tujiTeal)
                            .padding(.horizontal, Space.s2)
                            .padding(.vertical, 2)
                            .background(.tujiTealSoft, in: .capsule)
                    }
                }
            }
            Spacer()
            PronunciationButton(text: w.word, size: 48)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.tujiOverline)
            .tracking(2)
            .foregroundStyle(.tujiTeal)
            .padding(.top, Space.s2)
    }

    private func definitionCard(_ w: Word, chineseDef: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                if self.settings.current.showZh {
                    Text(w.chinese)
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(.tujiInk)
                }
                if let pos = w.partOfSpeech {
                    Text(pos)
                        .font(.tujiCaption)
                        .italic()
                        .foregroundStyle(.tujiInk3)
                }
            }
            // `englishDefinition` is the convenience field the server pre-fills
            // from the en row; `definitions` itself is lang-filtered server-side
            // so we can't pull it from there on a zh-Hant request.
            if let en = w.englishDefinition, !en.isEmpty {
                Text(en)
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk)
            }
            if self.settings.current.showZh {
                Text(chineseDef)
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiCard, in: .rect(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(.tujiInk4.opacity(0.25), lineWidth: 1)
        )
    }

    private func formsCard(_ forms: [WordForm]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(forms.enumerated()), id: \.offset) { idx, form in
                HStack {
                    Text(form.label)
                        .font(.tujiBody)
                        .foregroundStyle(.tujiInk2)
                    Spacer()
                    Text(form.value)
                        .font(.tujiMono)
                        .foregroundStyle(.tujiInk)
                }
                .padding(.vertical, Space.s3)
                .padding(.horizontal, Space.s4)
                if idx < forms.count - 1 {
                    Divider().background(.tujiInk4.opacity(0.2))
                }
            }
        }
        .background(.tujiCard, in: .rect(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(.tujiInk4.opacity(0.25), lineWidth: 1)
        )
    }

    private func etymologyCard(_ etymology: String) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(.tujiTeal)
                .frame(width: 3)
            Text(etymology)
                .font(.tujiBody)
                .foregroundStyle(.tujiTealDark)
                .padding(.vertical, Space.s4)
                .padding(.leading, Space.s5)
                .padding(.trailing, Space.s4)
        }
        .background(.tujiTealSoft, in: .rect(cornerRadius: Radius.lg))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func examplesCard(_ examples: [WordExample]) -> some View {
        VStack(spacing: Space.s3) {
            ForEach(Array(examples.prefix(3).enumerated()), id: \.offset) { _, ex in
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(ex.en)
                        .font(.tujiBodyLg)
                        .foregroundStyle(.tujiInk)
                    if let zh = ex.zh, !zh.isEmpty {
                        Text(zh)
                            .font(.tujiCaption)
                            .foregroundStyle(.tujiInk3)
                    }
                }
                .padding(Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.tujiCard, in: .rect(cornerRadius: Radius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .stroke(.tujiInk4.opacity(0.25), lineWidth: 1)
                )
            }
        }
    }

    private func collocationsRow(_ collocations: [String], zh: [String]?) -> some View {
        FlowLayout(spacing: Space.s2) {
            ForEach(Array(collocations.enumerated()), id: \.element) { idx, c in
                let zhText = (zh != nil && idx < (zh?.count ?? 0)) ? zh?[idx] : nil
                VStack(alignment: .leading, spacing: 2) {
                    Text(c)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.tujiTeal)
                    if let zhText, !zhText.isEmpty {
                        Text(zhText)
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.tujiTealDark)
                    }
                }
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s2)
                .background(.tujiTealSoft, in: .rect(cornerRadius: Radius.md))
            }
        }
    }

    private func circleControl(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.tujiCard)
                    .overlay(Circle().stroke(.tujiInk4.opacity(0.3), lineWidth: 1.5))
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.tujiInk)
            }
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Load

    private func load() async {
        guard self.word == nil, !self.loading else { return }
        self.loading = true
        defer { self.loading = false }
        do {
            self.word = try await APIClient.shared.get(.word(id: self.id))
        } catch {
            self.error = error
        }
    }
}

/// Simple flow layout for collocation chips. SwiftUI's grid isn't great
/// for variable-width items, so we implement minimal Layout protocol.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        return self.layout(in: maxWidth, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = self.layout(in: bounds.width, subviews: subviews)
        for (index, place) in result.placements.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + place.x, y: bounds.minY + place.y),
                proposal: .unspecified
            )
        }
    }

    private struct LayoutResult {
        var size: CGSize
        var placements: [CGPoint]
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> LayoutResult {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        var maxX: CGFloat = 0
        var placements: [CGPoint] = []
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowH + self.spacing
                rowH = 0
            }
            placements.append(CGPoint(x: x, y: y))
            x += size.width + self.spacing
            maxX = max(maxX, x)
            rowH = max(rowH, size.height)
        }
        return LayoutResult(size: CGSize(width: maxX, height: y + rowH), placements: placements)
    }
}

#Preview {
    NavigationStack {
        WordDetailView(id: "tomato")
            .environment(LocalCache.shared)
            .environment(AuthService.shared)
            .environment(StudyFocus.shared)
    }
}
