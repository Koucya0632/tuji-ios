// What to read aloud, and where its recording comes from.
//
// A word's pre-generated clips live on the catalogue row (`CardWord`) and on a
// fetched `Word` detail. They do **not** live on `StudyQueueWord`: the queue
// payload is deliberately lean, so every study screen that wants a word spoken
// has to go sideways into the catalogue for them.
//
// That lookup — `words.find(id:)?.audioUrls` — was written out at eight call
// sites, and the two that sit twenty-eight lines apart on the same card did not
// agree: `RecognizeView.autoPlay` also consulted the prefetched detail, while
// the speaker button under it did not. Same card, same word, two answers about
// which recording it has.
//
// So the question moves behind one interface. A screen says *what* it wants
// said and hands over whatever it already holds; finding the rest is not its
// job.

import Foundation

/// The catalogue, as the only thing this needs from it.
///
/// A read seam rather than the store, because the whole question is one lookup
/// and a fake for it is one line — see ADR-0001 on preferring a narrow read
/// seam over the store it reads.
@MainActor
protocol WordClipReading {
    /// The pre-generated clips for a catalogue word, keyed by locale, or nil
    /// when the catalogue does not know this word or it has no recording.
    func clips(forWordId id: String) -> [String: String]?
}

struct CatalogueClips: WordClipReading {
    var words: WordsStore = .shared

    func clips(forWordId id: String) -> [String: String]? {
        self.words.find(id: id)?.audioUrls
    }
}

/// Something the app can read aloud.
struct SpokenWord: Hashable {
    /// What is spoken when there is no recording — `SpeechService` synthesises
    /// it — and what a recording is a recording *of*.
    let text: String
    /// The word's own language, which wins over the session direction when
    /// picking a voice. Nil follows 當前圖鑑語言 and the 發音口音 setting.
    let language: TargetLanguage?
    /// The catalogue id, when this is a word the catalogue may hold a recording
    /// for. Sentences have none.
    let wordId: String?
    /// Clips the caller already holds. A freshly fetched detail carries them
    /// before the catalogue has merged anything, so it answers first; the
    /// catalogue is the fallback, and is all a study card has.
    let clips: [String: String]?

    /// The recording `voice` should play, or nil to synthesise `text` instead.
    func clip(voice: SpeechService.Voice, catalogue: WordClipReading) -> String? {
        let urls = self.clips ?? self.wordId.flatMap { catalogue.clips(forWordId: $0) }
        return urls?[voice.rawValue]
    }
}

extension SpokenWord {
    /// A card in the study queue. Its payload carries no clips, so the
    /// catalogue answers.
    init(_ word: StudyQueueWord, clips: [String: String]? = nil) {
        self.init(
            text: word.word,
            language: word.taggedLanguage,
            wordId: word.id,
            clips: clips
        )
    }

    /// A catalogue row, which carries its own.
    init(_ word: CardWord) {
        self.init(
            text: word.word,
            language: word.taggedLanguage,
            wordId: word.id,
            clips: word.audioUrls
        )
    }

    /// A fetched detail, which carries its own and may have them before the
    /// catalogue does.
    init(_ word: Word) {
        self.init(
            text: word.word,
            language: word.taggedLanguage,
            wordId: word.id,
            clips: word.audioUrls
        )
    }

    /// A sentence. Nothing to look up: `word_example_media` clips reach the app
    /// on the payload that carries the sentence, and everything else is
    /// synthesised.
    static func sentence(
        _ text: String,
        language: TargetLanguage?,
        clips: [String: String]? = nil
    )
        -> SpokenWord
    {
        SpokenWord(text: text, language: language, wordId: nil, clips: clips)
    }

    /// A headword whose model is not one of the three above — 物見's public
    /// item, a 合集 member. It carries whatever the caller has.
    static func headword(
        _ text: String,
        language: TargetLanguage?,
        wordId: String? = nil,
        clips: [String: String]? = nil
    )
        -> SpokenWord
    {
        SpokenWord(text: text, language: language, wordId: wordId, clips: clips)
    }
}
