// Step 1 of NewFlow: the teach-then-rate card. Presents the word with image,
// auto-played audio, 中文, and — when the prefetched detail has them — a
// definition line and one example sentence, then asks whether the user
// already knows it. All three buttons write SRS (the only step that does):
// "第一次見" = .again, "有點印象" = .hard, "已經認識" = .good.
// Three options because this is the *new words* flow — not knowing the
// word is the expected answer, so it must have a button (the old 知道/熟悉
// pair were both positive and left first-timers guessing).

import SwiftUI

struct RecognizeView: View {
    let coord: NewFlowCoordinator
    let item: StudyQueueItem
    /// Prefetched full detail (definition + examples) from NewFlowTeachLoader.
    /// nil while loading or when enrichment is missing — the card renders
    /// without the teach sections rather than showing a spinner.
    var detail: Word?

    /// Where the catalogue's recordings come from, and the service that plays
    /// them. Defaulted `.shared` per ADR-0001.
    var catalogue: WordClipReading = CatalogueClips()
    var speech: SpeechService = .shared

    @Environment(SettingsStore.self) private var settings
    @Environment(WordsStore.self) private var words
    @Environment(\.targetLanguage) private var session

    var body: some View {
        VStack(spacing: Space.s3) {
            ScrollView {
                self.card
            }
            .scrollBounceBehavior(.basedOnSize)
            self.buttons
                .padding(.horizontal, Space.s4)
        }
        .padding(.bottom, Space.s4)
        // Hosts the 詞塊 card for the teach example. On the root rather than on
        // the sentence: the sentence is inside the `ScrollView`, and a card
        // hosted there would scroll away with the card content.
        .glossCard()
        // The flow view keys this view per presentation, so the task fires
        // once per card — recognize never requeues, so once per word.
        .task { await self.autoPlay() }
    }

    /// The prefetched detail carries the server tag the queue payload may lack,
    /// so it answers first; either way the session settles an untagged word.
    private var wordLanguage: TargetLanguage {
        self.detail?.taggedLanguage
            ?? self.item.word.language(in: self.session)
    }

    /// The first example that has a sentence in the learning language — JA
    /// entries missing `target` teach nothing, so they're skipped.
    private var teachExample: (sentence: String, zh: String?, spans: [GlossSpan]?)? {
        for ex in self.detail?.examples ?? [] {
            let sentence = ex.target ?? (self.wordLanguage == .ja ? "" : ex.en)
            if !sentence.isEmpty {
                return (sentence, ex.zh, ex.spans)
            }
        }
        return nil
    }

    /// This card's headword, and where to find its recording.
    ///
    /// The prefetched detail answers before the catalogue: it carries the
    /// server tag the queue payload may lack, and it may hold clips the
    /// catalogue has not merged. The auto-play and the speaker button below it
    /// both read this — they used to resolve it separately, and only one of
    /// them consulted the detail at all.
    private var spokenHeadword: SpokenWord {
        SpokenWord(self.item.word, clips: self.detail?.audioUrls)
    }

    /// Hearing the word is the cheapest teach signal, so play it as the card
    /// settles (the delay keeps the transition from swallowing the clip).
    ///
    /// The beat stays in the view rather than moving to a module: it is
    /// `.task`'s, so SwiftUI cancels it when the card goes — unlike the
    /// unstructured `Task {}` that `AnswerBeat` exists to replace.
    private func autoPlay() async {
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let voice = SpeechService.Voice.preferred(
            for: self.settings.current,
            language: self.wordLanguage
        )
        self.speech.play(
            urlString: self.spokenHeadword.clip(voice: voice, catalogue: self.catalogue),
            fallbackText: self.item.word.word,
            voice: voice
        )
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            self.hero
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(alignment: .firstTextBaseline) {
                    // This screen's whole job is "here is a new word", so the
                    // word used to be set at display size. It no longer is: a
                    // size only short words could keep was not a hierarchy, it
                    // was a lottery — 長い外来語 arrived a third of the size of
                    // 洗剤. The picture and the empty page around it carry the
                    // emphasis instead. See `TujiHeadword`.
                    TujiHeadword(word: self.item.word)
                        // Beside a `Spacer` the headword is offered half the row
                        // unless it is prioritised; see WordDetailView.titleRow.
                        .layoutPriority(1)
                    Spacer(minLength: Space.s2)
                    PronunciationButton(
                        subject: self.spokenHeadword,
                        size: 48
                    )
                }
                // One line, not two. These used to be separate `pronunciation`
                // and `reading` checks guarded against each other, which only
                // ever mattered while the two could differ — the server sends
                // the same string for both on every Japanese word.
                TujiReadingLine(word: self.item.word, ink: .tujiInk3)
                // In monolingual mode (UI language == target) the gloss equals
                // the target definition below — show it once, keeping the
                // ungated definition and dropping the duplicate gloss chip.
                if self.settings.current.showZh,
                   self.item.word.chinese != self.detail?.targetDefinition
                {
                    Text(self.item.word.chinese)
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk2)
                }
                if let definition = self.detail?.targetDefinition, !definition.isEmpty {
                    Text(definition)
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk3)
                        .lineLimit(2)
                }
                if let example = self.teachExample {
                    self.exampleBlock(example)
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.bottom, Space.s3)
        }
    }

    private func exampleBlock(_ example: (sentence: String, zh: String?, spans: [GlossSpan]?)) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(alignment: .top, spacing: Space.s2) {
                InteractiveSentenceText(
                    sentence: example.sentence,
                    spans: example.spans,
                    language: self.wordLanguage
                )
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s2)
                PronunciationButton(
                    subject: .sentence(example.sentence, language: self.wordLanguage),
                    size: 32
                )
            }
            if self.settings.current.showZh, let zh = example.zh, !zh.isEmpty {
                Text(zh)
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiPaper2)
    }

    private var hero: some View {
        Color.tujiPaper2
            .frame(height: 220)
            .overlay {
                WordPicture(
                    url: self.item.word.imageURL,
                    kind: self.item.word.imageKind,
                    glyphSize: 32
                )
            }
            .clipped()
    }

    /// Three buttons, not the one 知道了 the spec draws: these send three
    /// different SRS ratings (again / hard / good), and collapsing them would
    /// change what the server schedules — the one thing this redesign may not
    /// touch. What changes is that they stop being three different *kinds* of
    /// button (red tint, teal-on-paper, solid ink) sitting in a row pretending
    /// to be a set. One ground, one text colour, and a 3pt edge that says which
    /// end of the scale each one is — the same mark the rating panel uses.
    private var buttons: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("這個字你認識嗎？")
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiInk3)
            HStack(spacing: Space.s2) {
                self.rateButton("沒見過", rating: .again)
                self.rateButton("有印象", rating: .hard)
                self.rateButton("已認識", rating: .good)
            }
        }
    }

    private func rateButton(_ title: LocalizedStringKey, rating: SRSRating) -> some View {
        Button { self.rate(rating) } label: {
            Text(title)
                .font(.tujiH3)
                .foregroundStyle(.tujiInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(alignment: .leading) {
                    HStack(spacing: 0) {
                        Rectangle().fill(rating.edge).frame(width: Border.bw3)
                        Rectangle().fill(.tujiPaper2)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(self.coord.recLocked)
    }

    private func rate(_ r: SRSRating) {
        // Synchronous: the beat is the coordinator's, tracked in `pendingBeats`
        // so 先離開 can cancel it. This used to spawn a Task the view dropped,
        // around a sleep nothing could reach.
        self.coord.recognizeAnswer(rating: r)
    }
}
