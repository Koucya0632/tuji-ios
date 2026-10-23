// Category metadata matching GET /api/categories.
//
// `color` is a Tailwind gradient string from the web app
// ("from-orange-100 to-rose-100"). The iOS rendering uses tujiAccumulationSoft
// as a default tint and ignores the gradient — design will catch up
// once W3 finishes.

import Foundation
import SwiftUI

struct TujiCategory: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let nameZh: String
    let emoji: String
    let description: String?
    let color: String?
    let imageUrl: String?

    var imageURL: URL? {
        guard let imageUrl else { return nil }
        return URL(string: imageUrl)
    }
}

/// 主題組合 — a named group of public themes for one way of being in Japan
/// (CONTEXT.md). Already named in the request's language and trimmed by the
/// server to the themes it serves.
struct TopicPreset: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let categoryIds: [String]
    /// What a brand-new account starts from. The server marks exactly one;
    /// read the flag, never the order.
    let isDefault: Bool
}

struct CategoriesResponse: Decodable {
    let categories: [TujiCategory]
    /// Empty from a backend that predates 主題組合.
    let presets: [TopicPreset]

    init(categories: [TujiCategory], presets: [TopicPreset] = []) {
        self.categories = categories
        self.presets = presets
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.categories = try c.decode([TujiCategory].self, forKey: .categories)
        self.presets = try c.decodeIfPresent([TopicPreset].self, forKey: .presets) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case categories, presets
    }
}
