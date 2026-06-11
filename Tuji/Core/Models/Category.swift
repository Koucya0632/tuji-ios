// Category metadata matching GET /api/categories.
//
// `color` is a Tailwind gradient string from the web app
// ("from-orange-100 to-rose-100"). The iOS rendering uses tujiTealSoft
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

struct CategoriesResponse: Decodable {
    let categories: [TujiCategory]
}
