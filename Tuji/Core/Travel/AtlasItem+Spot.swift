// A 自製圖鑑 card at a 景點 — the same rules as tuji-web
// lib/travel/spot-tagging.ts, so the card page only offers what the server
// will accept.
//
//   - A card may sit only at a spot in its own language (Japan's spots take
//     Japanese cards).
//   - Sharing it there needs it public on 物見, and a spot an admin took it off
//     stays closed to it.

import Foundation

extension AtlasItem {
    /// The open spots this card may be tagged to: those of destinations in its language.
    func taggableSpots(in destinations: [TravelDestination]) -> [TravelSpot] {
        destinations
            .filter { $0.language == self.targetLanguage.rawValue }
            .flatMap(\.cities)
            .flatMap(\.openSpots)
    }

    /// Submitted to 物見 and not refused, withdrawn or taken down.
    var isPublicForSpot: Bool {
        guard self.visibility == "public" else { return false }
        switch self.review {
        case .pending, .pendingAuto, .pendingReview, .approved: return true
        case .draft, .rejected, .takedown, .withdrawn: return false
        }
    }

    /// Whether 「放到景點頁」 may be turned on for the spot the card carries.
    var canShareToSpot: Bool {
        self.spotId != nil && self.isPublicForSpot && self.spotShareBlocked != true
    }
}
