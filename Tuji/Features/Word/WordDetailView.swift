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

    @State private var word: Word?
    @State private var loading = false
    @State private var error: Error?

    var body: some View {
        ScrollView {
            if let word {
                content(word)
            } else if let error {
                errorState(error)
            } else {
                ProgressView()
                    .tint(.tujiTeal)
                    .padding(.top, Space.s16)
            }
        }
        .background(.tujiBg)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .task { await self.load() }
    }

    // MARK: - States

    private func content(_ w: Word) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            self.hero(w)
            VStack(alignment: .leading, spacing: Space.s5) {
                self.titleRow(w)
                if let chineseDef = w.chineseDefinition, !chineseDef.isEmpty {
                    self.sectionTitle("譯義 · DEFINITION")
                    self.definitionCard(w, chineseDef: chineseDef)
                }
                if let forms = w.forms, !forms.isEmpty {
                    self.sectionTitle("詞形變化 · FORMS")
                    self.formsCard(forms)
                }
                if let etymology = w.etymology, !etymology.isEmpty {
                    self.sectionTitle("來源故事 · ORIGIN")
                    self.etymologyCard(etymology)
                }
                if let examples = w.examples, !examples.isEmpty {
                    self.sectionTitle("例句 · EXAMPLE")
                    self.examplesCard(examples)
                }
                if let collocations = w.collocations, !collocations.isEmpty {
                    self.sectionTitle("常見搭配 · COLLOCATIONS")
                    self.collocationsRow(collocations)
                }
            }
            .padding(.horizontal, Space.s6)
            .padding(.top, Space.s5)
            .padding(.bottom, Space.s12)
        }
    }

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

    private func hero(_ w: Word) -> some View {
        ZStack(alignment: .topLeading) {
            LazyImage(url: w.imageURL) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.tujiTealSoft
                }
            }
            .pipeline(.shared)
            .frame(height: 320)
            .clipped()

            HStack {
                self.circleControl(systemImage: "chevron.left") { self.dismiss() }
                Spacer()
                FavoriteButton(wordId: w.id)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s12)
        }
    }

    private func titleRow(_ w: Word) -> some View {
        HStack(alignment: .top, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(w.word)
                    .font(.tujiDisplay)
                    .foregroundStyle(.tujiInk)
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
                Text(w.chinese)
                    .font(.tujiH3)
                    .foregroundStyle(.tujiInk)
                    .padding(.top, Space.s1)
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
                Text(w.chinese)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(.tujiInk)
                if let pos = w.partOfSpeech {
                    Text(pos)
                        .font(.tujiCaption)
                        .italic()
                        .foregroundStyle(.tujiInk3)
                }
            }
            if let firstEn = w.definitions?.first(where: { $0.language == "en" }) {
                Text(firstEn.definition)
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk)
            }
            Text(chineseDef)
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk3)
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

    private func collocationsRow(_ collocations: [String]) -> some View {
        FlowLayout(spacing: Space.s2) {
            ForEach(collocations, id: \.self) { c in
                Text(c)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.tujiTeal)
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s2)
                    .background(.tujiTealSoft, in: .capsule)
            }
        }
    }

    private func circleControl(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(.tujiCard.opacity(0.92))
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.tujiInk)
            }
            .frame(width: 38, height: 38)
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
    }
}
