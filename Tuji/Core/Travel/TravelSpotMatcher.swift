// Which 景點 a photo was taken at, from the photo's own location — the same
// rule as tuji-web `spotAt` (lib/travel/spot-tagging.ts), run on the device so
// the point never reaches the server (parent repo docs/adr/0002).
//
// A spot matches when the point lies inside its circle, and only for a card in
// the destination's language: Japan's spots take Japanese cards. Neighbouring
// circles never overlap, but the nearest wins if they ever did.

import Foundation

enum TravelSpotMatcher {
    static func match(
        _ point: GeoPoint,
        in destinations: [TravelDestination],
        targetLanguage: String
    )
        -> TravelSpot?
    {
        var best: (spot: TravelSpot, distance: Double)?
        for destination in destinations where destination.language == targetLanguage {
            for spot in destination.cities.flatMap(\.spots) {
                guard let geo = spot.geo else { continue }
                let distance = Self.distanceMeters(point, GeoPoint(lat: geo.lat, lng: geo.lng))
                if distance <= geo.radiusM, distance < (best?.distance ?? .infinity) {
                    best = (spot, distance)
                }
            }
        }
        return best?.spot
    }

    /// Great-circle distance in metres.
    static func distanceMeters(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let rad = Double.pi / 180
        let dLat = (b.lat - a.lat) * rad
        let dLng = (b.lng - a.lng) * rad
        let h = pow(sin(dLat / 2), 2) + cos(a.lat * rad) * cos(b.lat * rad) * pow(sin(dLng / 2), 2)
        return 2 * 6_371_000 * asin(min(1, h.squareRoot()))
    }
}
