// Reusable "字詞資料 · DETAILS" + "例句 · EXAMPLE" block for a loaded Word.
//
// Extracted from WordDetailPage so the same section rendering can be reused
// inline inside WordPeekSheet (drag-to-expand reveals full details without
// pushing a new page). Owns the section-tab selection; renders nothing for
// fields a word doesn't have.

import SwiftUI

struct WordDetailSections: View {
    let word: Word

    @Environment(SettingsStore.self) private var settings
    @State private var selectedDetailTab: WordDetailTab

    init(word: Word) {
        self.word = word
        // `.definition` is a safe default — body clamps it to the tabs actually
        // available for this word.
        _selectedDetailTab = State(initialValue: .definition)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            let tabs = self.currentTabs
            // Keep the shown tab valid when availability shifts (e.g. showZh
            // toggling the 譯義 tab) so the switch never renders a card whose
            // pill isn't present.
            let selected = tabs.contains(self.selectedDetailTab)
                ? self.selectedDetailTab
                : (tabs.first ?? .definition)
            if !tabs.isEmpty {
                self.sectionTitle("字詞資料 · DETAILS")
                if tabs.count > 1 {
                    self.tabPills(tabs, selected: selected)
                }
                Group {
                    switch selected {
                    case .definition:
                        self.definitionCard(
                            word,
                            targetDef: word.targetDefinition,
                            chineseDef: word.chineseDefinition
                        )
                    case .forms:
                        if let forms = word.forms, !forms.isEmpty {
                            self.formsCard(forms)
                        }
                    case .origin:
                        if let etymology = word.etymology, !etymology.isEmpty {
                            self.etymologyCard(etymology)
                        }
                    case .collocations:
                        if let collocations = word.collocations, !collocations.isEmpty {
                            self.collocationsRow(collocations, zh: word.collocationsZh)
                        }
                    }
                }
            }
            if let examples = word.examples, !examples.isEmpty {
                self.sectionTitle("例句 · EXAMPLE")
                self.examplesCard(examples)
            }
        }
    }

    private func tabPills(_ tabs: [WordDetailTab], selected: WordDetailTab) -> some View {
        HStack(spacing: Space.s2) {
            ForEach(tabs, id: \.self) { tab in
                let active = tab == selected
                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        self.selectedDetailTab = tab
                    }
                } label: {
                    Text(tab.label)
                        .font(.system(size: 13, weight: .semibold))
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

    /// Tabs to show. `.definition` appears whenever the definition card would
    /// render anything — a target-language definition, or (when 中文 is shown)
    /// the 中文 name / 中文 釋義 — so a card with only Chinese content (e.g. a
    /// custom word whose JA definition is missing) still shows its meaning
    /// instead of collapsing to just the headword.
    private var currentTabs: [WordDetailTab] {
        var tabs: [WordDetailTab] = []
        if self.definitionHasVisibleContent(self.word) { tabs.append(.definition) }
        if let forms = word.forms, !forms.isEmpty { tabs.append(.forms) }
        if let ety = word.etymology, !ety.isEmpty { tabs.append(.origin) }
        if let cols = word.collocations, !cols.isEmpty { tabs.append(.collocations) }
        return tabs
    }

    private func definitionHasVisibleContent(_ w: Word) -> Bool {
        if let target = w.targetDefinition, !target.isEmpty { return true }
        guard self.settings.current.showZh else { return false }
        if let zh = w.chineseDefinition, !zh.isEmpty { return true }
        return !w.chinese.isEmpty
    }

    // MARK: - Sections

    private func sectionTitle(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.tujiOverline)
            .tracking(2)
            .foregroundStyle(.tujiTeal)
            .padding(.top, Space.s2)
    }

    private func definitionCard(_ w: Word, targetDef: String?, chineseDef: String?) -> some View {
        // Monolingual mode (UI language == target language): the gloss and the
        // target definition are the same string. Show it once, via targetDef
        // (which is ungated), and drop the duplicate headline.
        let glossDupesTarget = targetDef.map { $0 == w.chinese } ?? false
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                if self.settings.current.showZh, !glossDupesTarget {
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
            if let targetDef, !targetDef.isEmpty {
                Text(targetDef)
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk)
            }
            if self.settings.current.showZh,
               let chineseDef,
               !chineseDef.isEmpty
            {
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
                    // Grammar labels (單數/複數/過去式…) come from the model as
                    // zh-Hant; localize the known set, pass anything else through.
                    Text(tujiLocalized(String.LocalizationValue(form.label)))
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
                let sentence = ex.target ?? (word.wordLanguage == .ja ? "" : ex.en)
                VStack(alignment: .leading, spacing: Space.s1) {
                    HStack(alignment: .top, spacing: Space.s2) {
                        Text(sentence)
                            .font(.tujiBodyLg)
                            .foregroundStyle(.tujiInk)
                        Spacer(minLength: Space.s2)
                        PronunciationButton(
                            text: sentence,
                            language: word.wordLanguage,
                            size: 32
                        )
                    }
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
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tujiTeal)
                    if let zhText, !zhText.isEmpty {
                        Text(zhText)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tujiTealDark)
                    }
                }
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s2)
                .background(.tujiTealSoft, in: .rect(cornerRadius: Radius.md))
            }
        }
    }
}

enum WordDetailTab: Hashable, CaseIterable {
    case definition
    case forms
    case origin
    case collocations

    var label: LocalizedStringKey {
        switch self {
        case .definition: "譯義"
        case .forms: "詞形"
        case .origin: "來源"
        case .collocations: "搭配"
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
