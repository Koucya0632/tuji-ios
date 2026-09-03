// What 求救提示 prints, and — the part worth pinning — what it prints when the
// payload gives it nothing.
//
// The hint was `word.chinese` for its whole life. For a zh reader that is the
// answer translated, so the flip gave away exactly as much as it taught. It now
// prefers the 釋義, which the queue carries only when the server judged it worth
// carrying (lib/study-hint.ts). Every one of those "only when" cases arrives
// here as a missing field, which is why the fallback is the thing tested most.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct HintFaceTests {
    private func word(chinese: String = "水桶", definition: String?) throws -> StudyQueueWord {
        let field = definition.map { "\"\($0)\"" } ?? "null"
        let json = """
        {
          "id": "w-bucket", "word": "bucket", "chinese": "\(chinese)",
          "definition": \(field),
          "imageUrl": "", "pronunciation": "", "reading": null,
          "targetLanguage": "en", "category": "bathroom"
        }
        """
        return try JSONDecoder.tuji.decode(StudyQueueWord.self, from: Data(json.utf8))
    }

    private let bucketDefinition = "附提把、開口朝上的圓柱形容器，用來裝載或搬運液體。"

    @Test
    func aDefinitionOnThePayloadIsWhatTheFaceShows() throws {
        let face = try HintFace(self.word(definition: self.bucketDefinition))
        #expect(face == .definition(self.bucketDefinition))
        #expect(face.text == self.bucketDefinition)
    }

    /// The ordinary state for a word the catalogue never got a 釋義 for — and for
    /// every case where the server withheld one on purpose. A hint that came back
    /// blank would be worse than the one this replaced.
    @Test
    func noDefinitionFallsBackToTheGlossItAlwaysShowed() throws {
        let face = try HintFace(self.word(definition: nil))
        #expect(face == .gloss("水桶"))
    }

    /// An older build's queue, and any payload from before the field existed.
    @Test
    func anAbsentFieldDecodesRatherThanFailing() throws {
        let json = """
        {
          "id": "w-bucket", "word": "bucket", "chinese": "水桶", "imageUrl": "",
          "pronunciation": "", "reading": null, "targetLanguage": "en",
          "category": "bathroom"
        }
        """
        let word = try JSONDecoder.tuji.decode(StudyQueueWord.self, from: Data(json.utf8))
        #expect(word.definition == nil)
        #expect(HintFace(word) == .gloss("水桶"))
    }

    @Test
    func blankAndWhitespaceAreNotADefinition() throws {
        let blank = try HintFace(self.word(definition: ""))
        let spaces = try HintFace(self.word(definition: "   "))
        #expect(blank == .gloss("水桶"))
        #expect(spaces == .gloss("水桶"))
    }

    /// The server already drops a 釋義 equal to the gloss, because that equality
    /// is monolingual study and the sentence would be written in the language
    /// being tested. This asserts the client agrees rather than printing it as
    /// though it were new information.
    @Test
    func aDefinitionThatOnlyRepeatsTheGlossIsTheGloss() throws {
        let exact = try HintFace(self.word(definition: "水桶"))
        let padded = try HintFace(self.word(definition: " 水桶 "))
        #expect(exact == .gloss("水桶"))
        #expect(padded == .gloss("水桶"))
    }

    /// A definition is trimmed before it is measured, so a payload with padding
    /// does not become a different case than the same text without it.
    @Test
    func surroundingWhitespaceIsNotPartOfTheDefinition() throws {
        let face = try HintFace(self.word(definition: "  \(self.bucketDefinition)  "))
        #expect(face == .definition(self.bucketDefinition))
    }
}
