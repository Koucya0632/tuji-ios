// Pins "a row this client cannot read does not appear — the rest of the list does".
//
// `TargetLanguage` decodes strictly on purpose: the value set is pinned by
// `LearningDirection`, and adding one is a coordinated client+server change.
// The decision is right; its consequence was not. One row in an unknown
// language threw, and the throw took the whole response with it — `APIClient`
// turns that into 資料解析失敗, so 物見 showed *nothing* because one item was new.
//
// tuji-web deploys on its own and is routinely ahead of the app, while the
// clients that matter are already on the App Store. A third language would
// blank the community feeds of every shipped build.

import Foundation
import Testing
@testable import Tuji

struct LossyArrayTests {
    private struct Row: Decodable, Equatable {
        let id: String
        let language: TargetLanguage
    }

    private struct Envelope: Decodable {
        @LossyArray var rows: [Row]
    }

    private func decode(_ json: String) throws -> [Row] {
        try JSONDecoder.tuji.decode(Envelope.self, from: Data(json.utf8)).rows
    }

    /// The case this exists for: one unreadable row, and the list survives.
    @Test
    func anUnknownLanguageDropsItsRowAndKeepsTheRest() throws {
        let rows = try self.decode("""
        {"rows": [
          {"id": "a", "language": "en"},
          {"id": "b", "language": "ko"},
          {"id": "c", "language": "ja"}
        ]}
        """)
        #expect(rows.map(\.id) == ["a", "c"])
    }

    /// Position must not matter — a bad first element used to be the one that
    /// could leave the decoder's cursor stuck.
    @Test
    func aBadRowInAnyPositionIsSkipped() throws {
        #expect(try self.decode(#"{"rows": [{"id":"x","language":"ko"},{"id":"a","language":"en"}]}"#)
            .map(\.id) == ["a"])
        #expect(try self.decode(#"{"rows": [{"id":"a","language":"en"},{"id":"x","language":"ko"}]}"#)
            .map(\.id) == ["a"])
    }

    /// Not only enums: any row the client cannot read is a row it cannot show.
    @Test
    func aRowMissingARequiredFieldIsAlsoSkipped() throws {
        let rows = try self.decode(#"{"rows": [{"id":"a","language":"en"},{"language":"ja"}]}"#)
        #expect(rows.map(\.id) == ["a"])
    }

    @Test
    func severalBadRowsAreAllSkipped() throws {
        let rows = try self.decode("""
        {"rows": [
          {"id": "a", "language": "ko"},
          {"id": "b", "language": "en"},
          {"id": "c", "language": "fr"},
          {"id": "d", "language": "ja"}
        ]}
        """)
        #expect(rows.map(\.id) == ["b", "d"])
    }

    /// Tolerant, not credulous: a list of only unreadable rows reads as empty
    /// rather than as an error, which is the whole trade — the screen shows its
    /// empty state instead of 資料解析失敗.
    @Test
    func aListOfOnlyBadRowsReadsAsEmpty() throws {
        #expect(try self.decode(#"{"rows": [{"id":"a","language":"ko"}]}"#).isEmpty)
    }

    /// A wrapped field must still behave like the non-optional array it replaced
    /// — absent or null is an empty list, not a throw.
    @Test
    func anAbsentOrNullListReadsAsEmpty() throws {
        #expect(try self.decode(#"{}"#).isEmpty)
        #expect(try self.decode(#"{"rows": null}"#).isEmpty)
    }

    @Test
    func aFullyReadableListIsUntouched() throws {
        let rows = try self.decode(#"{"rows": [{"id":"a","language":"en"},{"id":"b","language":"ja"}]}"#)
        #expect(rows == [Row(id: "a", language: .en), Row(id: "b", language: .ja)])
    }

    // MARK: - The real payloads

    /// The shape that motivated this, against the actual feed model: a 物見 wall
    /// with one item in a language this build predates.
    @Test
    func aCommunityFeedSurvivesAnItemInAnUnknownLanguage() throws {
        let json = """
        {"items": [
          {"id": "1", "slug": "s1", "lemma": "cup", "displayZhHant": "杯子", "targetLanguage": "en"},
          {"id": "2", "slug": "s2", "lemma": "컵", "displayZhHant": "杯子", "targetLanguage": "ko"},
          {"id": "3", "slug": "s3", "lemma": "コップ", "displayZhHant": "杯子", "targetLanguage": "ja"}
        ]}
        """
        let feed = try JSONDecoder.tuji.decode(AtlasPublicFeedResponse.self, from: Data(json.utf8))
        #expect(feed.items.map(\.slug) == ["s1", "s3"])
    }
}
