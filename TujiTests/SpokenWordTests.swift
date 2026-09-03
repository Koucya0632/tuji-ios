// Which recording a word plays.
//
// The rule had no home and no test: `words.find(id:)?.audioUrls` was written at
// eight call sites, and the two twenty-eight lines apart on the 學新字 teach
// card disagreed — the auto-play consulted the prefetched detail as well as the
// catalogue, the speaker button under it consulted only the catalogue. Nothing
// could have caught that, because there was nothing to call.

import Foundation
import Testing
@testable import Tuji

@MainActor
private struct StubClips: WordClipReading {
    var byWordId: [String: [String: String]] = [:]
    func clips(forWordId id: String) -> [String: String]? {
        self.byWordId[id]
    }
}

@MainActor
struct SpokenWordTests {
    private let catalogue = StubClips(byWordId: [
        "w-fork": ["en-US": "catalogue-us.mp3", "en-GB": "catalogue-uk.mp3"]
    ])

    private func queueWord(id: String = "w-fork") throws -> StudyQueueWord {
        let json = """
        {
          "id": "\(id)", "word": "fork", "chinese": "叉子", "imageUrl": "",
          "pronunciation": "", "reading": null, "targetLanguage": "en", "category": "kitchen"
        }
        """
        return try JSONDecoder.tuji.decode(StudyQueueWord.self, from: Data(json.utf8))
    }

    /// The queue payload is lean and carries no clips, so a study card's word
    /// has to be looked up. This is the lookup the six study call sites were
    /// each writing out.
    @Test
    func aQueuedWordTakesItsRecordingFromTheCatalogue() throws {
        let subject = try SpokenWord(self.queueWord())
        #expect(subject.clips == nil)
        #expect(subject.clip(voice: .us, catalogue: self.catalogue) == "catalogue-us.mp3")
        #expect(subject.clip(voice: .uk, catalogue: self.catalogue) == "catalogue-uk.mp3")
    }

    /// The divergence this module exists to remove: the auto-play preferred the
    /// prefetched detail, the button beside it never saw it. One precedence,
    /// stated once — what the caller holds wins, because a freshly fetched
    /// detail may carry clips the catalogue has not merged.
    @Test
    func aCallerSuppliedClipWinsOverTheCatalogue() throws {
        let subject = try SpokenWord(
            self.queueWord(),
            clips: ["en-US": "detail-us.mp3"]
        )
        #expect(subject.clip(voice: .us, catalogue: self.catalogue) == "detail-us.mp3")
    }

    /// A voice the recording does not cover falls through to synthesis rather
    /// than to another accent's clip.
    @Test
    func aMissingVoiceHasNoRecordingRatherThanTheWrongOne() throws {
        let subject = try SpokenWord(self.queueWord())
        #expect(subject.clip(voice: .japanese, catalogue: self.catalogue) == nil)
    }

    /// A word the catalogue does not know — a just-captured 自製圖鑑 card whose
    /// row has not merged yet — is synthesised, not silent.
    @Test
    func anUnknownWordHasNoRecording() throws {
        let subject = try SpokenWord(self.queueWord(id: "atlas:brand-new"))
        #expect(subject.clip(voice: .us, catalogue: self.catalogue) == nil)
        #expect(subject.text == "fork", "and there is still something to say")
    }

    /// Sentences look nothing up: their clips arrive on the payload that
    /// carries the sentence, and a 詞塊 deliberately passes none — its `wordId`
    /// is matched on the 原形, so the catalogue's recording would say a
    /// different word than the one on screen.
    @Test
    func aSentenceLooksNothingUp() {
        let spoken = SpokenWord.sentence("Pass me the fork.", language: .en)
        #expect(spoken.wordId == nil)
        #expect(spoken.clip(voice: .us, catalogue: self.catalogue) == nil)

        let chunk = SpokenWord.headword("documents", language: .en)
        #expect(chunk.wordId == nil)
        #expect(chunk.clip(voice: .us, catalogue: self.catalogue) == nil)
    }

    /// A word's own tag wins over the session direction when picking a voice,
    /// so a JA word speaks Japanese outside a JA session.
    @Test
    func theSubjectCarriesTheWordsOwnLanguage() throws {
        let subject = try SpokenWord(self.queueWord())
        #expect(subject.language == .en)
    }
}
