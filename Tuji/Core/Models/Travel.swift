// 跟著 Moira 去旅遊 — what GET /api/travel answers (tuji-web
// lib/travel/destinations.ts): destinations, their cities, and the 景點 in each.
//
// A 景點 owns no content. Its `wordIds` name ordinary 官方圖鑑 words, so a spot
// is a second way into words the dictionary already holds.
//
// The maps arrive as shapes, not pictures: a grid of cells for the country and
// a few lines for a city. Names come already in the interface language, so
// nothing here is translated on the device.

import CoreGraphics
import Foundation

/// A position the server sends as `[x, y]`.
struct TravelPoint: Decodable, Hashable {
    let x: Double
    let y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(from decoder: Decoder) throws {
        var pair = try decoder.unkeyedContainer()
        self.x = try pair.decode(Double.self)
        self.y = try pair.decode(Double.self)
    }

    var cgPoint: CGPoint {
        CGPoint(x: self.x, y: self.y)
    }
}

/// Where a spot is on the ground: a centre and how far from it a photo still
/// counts as taken there. Only used on the device, to suggest a spot for a photo
/// that carries its own location — the photo's coordinates never leave the
/// phone (parent repo docs/adr/0002).
struct TravelSpotGeo: Decodable, Hashable {
    let lat: Double
    let lng: Double
    let radiusM: Double
}

struct TravelSpot: Decodable, Identifiable, Hashable {
    enum LabelSide: String, Decodable {
        case left
        case right
    }

    let id: String
    let name: String
    /// How the place is written and read in Japanese, whatever the interface language.
    let native: String
    let reading: String
    /// 0–1 inside the city map.
    let at: TravelPoint
    let label: LabelSide
    let wordIds: [String]
    /// Every word is published, so there is something to open.
    let open: Bool
    /// A non-member may study this spot.
    let free: Bool
    /// Missing from a server that predates it; no suggestion is made then.
    var geo: TravelSpotGeo? = nil
}

/// One thing a city map is drawn from. A kind this build does not know is
/// dropped while decoding, so a newer server can add one without breaking the
/// map for everyone on an older app.
enum TravelMapShape: Decodable, Hashable {
    /// A closed loop, e.g. 山手線.
    case ring(center: TravelPoint, radius: TravelPoint, name: String, nameAt: TravelPoint)
    /// An open line, e.g. 隅田川.
    case river(points: [TravelPoint], name: String, nameAt: TravelPoint)
    /// A filled area, e.g. 東京灣.
    case water(points: [TravelPoint], name: String, nameAt: TravelPoint)

    private enum CodingKeys: String, CodingKey {
        case kind, center, radius, points, name, nameAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let name = try c.decode(String.self, forKey: .name)
        let nameAt = try c.decode(TravelPoint.self, forKey: .nameAt)
        switch try c.decode(String.self, forKey: .kind) {
        case "ring":
            self = try .ring(
                center: c.decode(TravelPoint.self, forKey: .center),
                radius: c.decode(TravelPoint.self, forKey: .radius),
                name: name,
                nameAt: nameAt
            )
        case "river":
            self = try .river(points: c.decode([TravelPoint].self, forKey: .points), name: name, nameAt: nameAt)
        case "water":
            self = try .water(points: c.decode([TravelPoint].self, forKey: .points), name: name, nameAt: nameAt)
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown shape \(other)")
        }
    }

    var name: String {
        switch self {
        case let .ring(_, _, name, _), let .river(_, name, _), let .water(_, name, _): name
        }
    }

    var nameAt: TravelPoint {
        switch self {
        case let .ring(_, _, _, at), let .river(_, _, at), let .water(_, _, at): at
        }
    }
}

struct TravelCity: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let regionId: String
    /// Width over height of the box the shapes and spots are placed in.
    let aspect: Double
    let shapes: [TravelMapShape]
    let spots: [TravelSpot]

    private enum CodingKeys: String, CodingKey {
        case id, name, regionId, aspect, shapes, spots
    }

    init(id: String, name: String, regionId: String, aspect: Double, shapes: [TravelMapShape], spots: [TravelSpot]) {
        self.id = id
        self.name = name
        self.regionId = regionId
        self.aspect = aspect
        self.shapes = shapes
        self.spots = spots
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.regionId = try c.decode(String.self, forKey: .regionId)
        self.aspect = try c.decode(Double.self, forKey: .aspect)
        self.shapes = try c.decode([Tolerant<TravelMapShape>].self, forKey: .shapes).compactMap(\.value)
        self.spots = try c.decode([TravelSpot].self, forKey: .spots)
    }

    var openSpots: [TravelSpot] {
        self.spots.filter(\.open)
    }
}

struct TravelRegion: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    /// Grid cells, `[column, row]`.
    let tiles: [TravelPoint]
    /// Where the name goes, in cells; may sit between cells.
    let nameAt: TravelPoint
    let cityIds: [String]
}

struct TravelGrid: Decodable, Hashable {
    let columns: Int
    let rows: Int
}

struct TravelDestination: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    /// The place's language (`ja`). A 自製圖鑑 card may sit at a spot here only
    /// when it is a card for this language. Missing from an older server.
    var language: String? = nil
    let grid: TravelGrid
    let regions: [TravelRegion]
    let cities: [TravelCity]

    func city(_ id: String) -> TravelCity? {
        self.cities.first { $0.id == id }
    }

    /// The cities of one region that have something to open.
    func openCities(in region: TravelRegion) -> [TravelCity] {
        region.cityIds.compactMap { self.city($0) }.filter { !$0.openSpots.isEmpty }
    }
}

struct TravelResponse: Decodable {
    let destinations: [TravelDestination]
}

/// Decodes to nil rather than failing the array it sits in.
private struct Tolerant<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        self.value = try? Value(from: decoder)
    }
}
