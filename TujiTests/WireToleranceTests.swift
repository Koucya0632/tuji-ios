// Pins what the wire is allowed to say.
//
// Both tolerances existed before this and neither was reachable from where it
// was needed: the NUMERIC-as-string decoder was a `private extension` inside one
// model file, and the fractional-seconds parser was a static on `ReviewSchedule`
// — 複習's module, not the wire's — while `JSONDecoder.tuji` next door still
// carried `.iso8601`, which rejects exactly what that parser tolerates.
//
// These assertions go through `JSONDecoder.tuji`, the decoder the app ships.
// Every decoding test in the suite used a bare `JSONDecoder()` before this,
// including the one written for the 資料解析失敗 regression — so the shipped
// configuration was asserted by nothing.

import Foundation
import Testing
@testable import Tuji

struct WireToleranceTests {
    // MARK: - NUMERIC as string

    private struct Row: Decodable {
        let value: Double
        let maybe: Double?

        enum CodingKeys: String, CodingKey { case value, maybe }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.value = try c.decodeFlexibleDouble(forKey: .value)
            self.maybe = try c.decodeFlexibleDoubleIfPresent(forKey: .maybe)
        }
    }

    private func row(_ json: String) throws -> Row {
        try JSONDecoder.tuji.decode(Row.self, from: Data(json.utf8))
    }

    /// Postgres NUMERIC serializes as a string. A plain number still decodes.
    @Test
    func aDoubleMayArriveAsANumberOrAsANumericString() throws {
        #expect(try self.row(#"{"value": 0.95}"#).value == 0.95)
        #expect(try self.row(#"{"value": "0.9500"}"#).value == 0.95)
        #expect(try self.row(#"{"value": "1.0000"}"#).value == 1)
    }

    /// Tolerant, not credulous: a string that is not a number is still a fault,
    /// and saying so beats reading it as zero.
    @Test
    func aNonNumericStringIsStillAnError() {
        #expect(throws: (any Error).self) { try self.row(#"{"value": "abc"}"#) }
    }

    @Test
    func theOptionalFormAcceptsAbsentAndNull() throws {
        #expect(try self.row(#"{"value": 1}"#).maybe == nil)
        #expect(try self.row(#"{"value": 1, "maybe": null}"#).maybe == nil)
        #expect(try self.row(#"{"value": 1, "maybe": "2.5"}"#).maybe == 2.5)
    }

    // MARK: - Timestamps

    private struct Stamped: Decodable {
        let at: Date
    }

    private func stamped(_ raw: String) throws -> Date {
        try JSONDecoder.tuji.decode(
            Stamped.self,
            from: Data(#"{"at": "\#(raw)"}"#.utf8)
        ).at
    }

    /// The server's `Date.toISOString()` always emits `.SSS`, and `.iso8601`
    /// rejects it. That is why no model in the app declares a `Date` — every
    /// timestamp is a `String` parsed at the point of use. This is the assertion
    /// that says the constraint is gone.
    @Test
    func aTimestampWithFractionalSecondsDecodes() throws {
        #expect(try self.stamped("2026-07-02T10:00:00.123Z") != nil)
    }

    /// And one without them, which is what older rows and fixtures carry.
    @Test
    func aTimestampWithoutFractionalSecondsDecodes() throws {
        #expect(try self.stamped("2026-07-02T10:00:00Z") != nil)
    }

    /// The two forms are the same instant, so tolerating both cannot mean
    /// reading them differently.
    @Test
    func bothFormsOfTheSameInstantAgree() throws {
        let withMillis = try self.stamped("2026-07-02T10:00:00.000Z")
        let without = try self.stamped("2026-07-02T10:00:00Z")
        #expect(withMillis == without)
    }

    @Test
    func somethingThatIsNotATimestampIsAnError() {
        #expect(throws: (any Error).self) { try self.stamped("not-a-date") }
        #expect(throws: (any Error).self) { try self.stamped("") }
    }

    // MARK: - Key conversion

    private struct SnakeRow: Decodable {
        let serverTime: String
    }

    /// `.convertFromSnakeCase` is on as a safety net for payloads that slip
    /// through in snake_case. Nothing asserted it in either direction, because
    /// every fixture was decoded with a bare `JSONDecoder()`.
    @Test
    func snakeCaseKeysConvert() throws {
        let snake = try JSONDecoder.tuji.decode(
            SnakeRow.self,
            from: Data(#"{"server_time": "T1"}"#.utf8)
        )
        #expect(snake.serverTime == "T1")

        let camel = try JSONDecoder.tuji.decode(
            SnakeRow.self,
            from: Data(#"{"serverTime": "T1"}"#.utf8)
        )
        #expect(camel.serverTime == "T1")
    }
}
