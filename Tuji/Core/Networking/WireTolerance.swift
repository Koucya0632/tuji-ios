// What the wire may say, and how the app reads it anyway.
//
// The tolerances existed; they were scattered and one of them was a trap.
//
//   • NUMERIC-as-string. A few atlas routes hand back raw Postgres NUMERIC
//     columns, which serialize as `"0.9500"` rather than `0.95`. The tolerance
//     for that was a `private extension` inside one model file, so the file
//     next door could not use it — and its own doc named two fields while it
//     was wired to one.
//   • Fractional seconds. `JSONDecoder.tuji` set `.iso8601`, whose formatter
//     *rejects* the `.SSS` the server's `Date.toISOString()` always emits. So
//     the strategy was not merely unused — no model declares a `Date` — it was
//     the reason none can: a `Date` field would throw and sink the payload.
//     The tolerant parser for it lived on `ReviewSchedule`, which is 複習's
//     module and not the wire's.
//
// A policy the file next door cannot reach is not a policy. Both live here now,
// and the decoder's date strategy is the tolerant parser rather than the one
// that traps.

import Foundation

/// Reading values the server spells more than one way.
enum Wire {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain = ISO8601DateFormatter()

    /// An ISO8601 timestamp with or without fractional seconds.
    ///
    /// The server always emits `.SSS`; some fixtures and older rows do not.
    static func parseISO(_ string: String) -> Date? {
        self.isoFractional.date(from: string) ?? self.isoPlain.date(from: string)
    }
}

extension KeyedDecodingContainer {
    /// A Double that may arrive as a JSON number or as a numeric string.
    ///
    /// Postgres NUMERIC columns serialize as strings — `"0.9500"` — and a few
    /// atlas routes return them raw. Not `private`: it was, and the field its
    /// own doc named second went on decoding strictly one screen away.
    func decodeFlexibleDouble(forKey key: Key) throws -> Double {
        if let value = try? decode(Double.self, forKey: key) { return value }
        let raw = try decode(String.self, forKey: key)
        guard let value = Double(raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Expected Double or numeric string, got \"\(raw)\""
            )
        }
        return value
    }

    /// The same tolerance where the value is optional.
    func decodeFlexibleDoubleIfPresent(forKey key: Key) throws -> Double? {
        guard self.contains(key), try !decodeNil(forKey: key) else { return nil }
        return try self.decodeFlexibleDouble(forKey: key)
    }
}
