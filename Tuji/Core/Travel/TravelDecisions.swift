// What the travel screens show, decided from plain values so each rule can be
// asserted by calling it.

import CoreGraphics
import Foundation

/// Whether this account may study a spot.
enum TravelSpotAccess: Equatable {
    case open
    /// Opens the paywall instead of a session.
    case needsMembership
}

/// One 景點 as its page shows it.
struct TravelSpotState: Equatable {
    /// The spot's words the dictionary has, in the spot's order.
    let words: [CardWord]
    let studied: Int
    let due: Int
    let access: TravelSpotAccess

    var total: Int {
        self.words.count
    }

    /// 0–1, for the bar.
    var progress: Double {
        self.total == 0 ? 0 : Double(self.studied) / Double(self.total)
    }

    /// Which study buttons to offer. A mode with nothing in it is not offered:
    /// an empty session is a dead end. A locked spot offers none — its one
    /// button opens the paywall.
    var studyModes: [StudyMode] {
        guard self.access == .open else { return [] }
        var modes: [StudyMode] = []
        if self.studied < self.total { modes.append(.new) }
        if self.due > 0 { modes.append(.review) }
        return modes
    }
}

enum TravelDecisions {
    /// - Parameter studyable: `Membership.studyableCategories`. nil = this
    ///   account is not gated, so every spot is open.
    static func access(to spot: TravelSpot, studyable: [String]?) -> TravelSpotAccess {
        studyable == nil || spot.free ? .open : .needsMembership
    }

    /// - Parameter scores: `MasteryStore.byId` — a word with a score has been studied.
    /// - Parameter nextReview: `MasteryStore.nextReviewById`.
    static func state(
        of spot: TravelSpot,
        words: [CardWord],
        scores: [String: Int],
        nextReview: [String: Date],
        studyable: [String]?,
        now: Date = Date()
    )
        -> TravelSpotState
    {
        let byId = Dictionary(words.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let resolved = spot.wordIds.compactMap { byId[$0] }
        return TravelSpotState(
            words: resolved,
            studied: resolved.count(where: { scores[$0.id] != nil }),
            due: resolved.count(where: { nextReview[$0.id].map { $0 <= now } ?? false }),
            access: self.access(to: spot, studyable: studyable)
        )
    }

    /// How many of a spot's words have been studied, without resolving them —
    /// for the city list, which shows a count per row.
    static func studiedCount(of spot: TravelSpot, scores: [String: Int]) -> Int {
        spot.wordIds.count(where: { scores[$0] != nil })
    }

    /// The entry in 物見 is drawn only when there is somewhere to go.
    static func showsEntry(_ destinations: [TravelDestination]) -> Bool {
        !destinations.isEmpty
    }

    /// Spots that can be opened, across a destination — the number on the entry.
    static func openSpotCount(_ destination: TravelDestination) -> Int {
        destination.cities.reduce(0) { $0 + $1.openSpots.count }
    }

    /// The side of one grid cell that fits `columns` cells and the gaps between
    /// them into `width`.
    static func cellSide(width: CGFloat, columns: Int, gap: CGFloat) -> CGFloat {
        guard columns > 0 else { return 0 }
        return max(0, (width - gap * CGFloat(columns - 1)) / CGFloat(columns))
    }

    /// Top-left corner of the cell at `tile`.
    static func cellOrigin(_ tile: TravelPoint, side: CGFloat, gap: CGFloat) -> CGPoint {
        CGPoint(x: tile.x * (side + gap), y: tile.y * (side + gap))
    }

    // MARK: - The 2026-11 maps

    /// A card's height on the country map: a 20pt name over 18pt lines, inside
    /// 6pt and 8pt of padding and a 2pt border. The server breaks the lines so
    /// at most two fit (tuji-web lib/travel/destinations.ts `cardLines`).
    static func cardHeight(lines: Int) -> CGFloat {
        4 + 6 + 20 + CGFloat(lines) * 18 + 8
    }

    /// The open spots' names, for the line under a city's name.
    static func spotPreview(_ city: TravelCity) -> String {
        let names = city.openSpots.map(\.name)
        return names.joined(separator: self.listSeparator(names))
    }

    /// 「、」 between Chinese or Japanese names, a comma between others.
    static func listSeparator(_ names: [String]) -> String {
        let cjk = names.allSatisfy { $0.unicodeScalars.first.map { $0.value >= 0x2E80 } ?? true }
        return cjk ? "、" : ", "
    }

    /// The character on a city's stamp.
    static func stampMark(_ name: String) -> String {
        name.first.map(String.init) ?? ""
    }

    /// Regions with nothing open yet, in map order — named together on one row.
    static func closedRegions(_ destination: TravelDestination) -> [TravelRegion] {
        destination.regions.filter { destination.openCities(in: $0).isEmpty }
    }
}
