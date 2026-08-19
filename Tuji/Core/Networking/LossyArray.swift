// A list that survives a row it cannot read.
//
// `TargetLanguage` decodes strictly, and that is deliberate: the value set is
// pinned by `LearningDirection`, and adding a language is a coordinated
// client+server change. The decision is right. Its *consequence* was not:
//
//   one row in a language this client has never heard of threw, and the throw
//   took the whole response with it — `APIClient` turns a decode failure into
//   資料解析失敗, so 物見 showed everyone nothing because one item was new.
//
// That is not a theoretical ordering. tuji-web deploys on its own (a manual
// `vercel --prod`, no git trigger) and is routinely ahead of the app, while the
// clients that matter are the ones already on the App Store and cannot be
// updated in lockstep. A third language would blank the community feeds of
// every shipped build until each user updated.
//
// So: a row this client cannot read does not appear. The rest of the list does.
// It is the same shape as the coverage rule for 詞塊 — *absent beats wrong* —
// applied one level up.

import Foundation
import OSLog

/// Decodes an array element by element, dropping the ones that throw.
///
/// Dropped rows are logged rather than swallowed. A list that quietly empties
/// itself is worse than one that fails loudly, so the evidence has to exist
/// somewhere even though the user never sees an error.
@propertyWrapper
struct LossyArray<Element: Decodable>: Decodable {
    var wrappedValue: [Element]

    private static var log: Logger {
        Logger(subsystem: "app.tuji.ios", category: "decode")
    }

    init(wrappedValue: [Element]) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var kept: [Element] = []
        var dropped = 0
        // Decoding into a throwaway wrapper is what advances the container past
        // a bad element: `decode(Element.self)` that throws leaves the cursor
        // where it was, and the loop would never end.
        while !container.isAtEnd {
            do {
                try kept.append(container.decode(Element.self))
            } catch {
                _ = try? container.decode(Skipped.self)
                dropped += 1
            }
        }
        if dropped > 0 {
            Self.log.error(
                "dropped \(dropped, privacy: .public) unreadable \(String(describing: Element.self), privacy: .public) row(s)"
            )
        }
        self.wrappedValue = kept
    }

    /// Consumes one element of any shape, so the cursor can move past a row
    /// that would not decode.
    private struct Skipped: Decodable {
        init(from _: Decoder) throws {}
    }
}

// Conditional, so a wrapped field does not cost its container the synthesized
// conformances it had before. `AtlasAuthorResponse` is `Hashable` and holds two
// of these.
extension LossyArray: Equatable where Element: Equatable {}
extension LossyArray: Hashable where Element: Hashable {}
extension LossyArray: Sendable where Element: Sendable {}

extension KeyedDecodingContainer {
    /// Lets `@LossyArray` behave like any other field: absent or null reads as
    /// an empty list rather than throwing, which is what the synthesized
    /// initializer would do for a non-optional array.
    func decode<Element>(
        _ type: LossyArray<Element>.Type,
        forKey key: Key
    ) throws
        -> LossyArray<Element>
    {
        try self.decodeIfPresent(type, forKey: key) ?? LossyArray(wrappedValue: [])
    }
}
