// Where a library photo was taken, read from the photo's own EXIF GPS.
//
// Only the 自製圖鑑 capture asks, and only to suggest a 景點 on the device
// (TravelSpotMatcher). The point stays in memory and never leaves the phone:
// the upload is re-encoded without metadata and the server strips EXIF anyway
// (parent repo docs/adr/0002). No location permission is involved — the picker
// hands the bytes over, and the user can turn 位置 off in its options.

import Foundation
import ImageIO

/// A place on the ground, in degrees.
struct GeoPoint: Hashable {
    let lat: Double
    let lng: Double
}

enum PhotoLocation {
    /// The GPS position stored in the image, or nil when there is none.
    static func read(from data: Data) -> GeoPoint? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let lat = number(gps[kCGImagePropertyGPSLatitude]),
              let lng = number(gps[kCGImagePropertyGPSLongitude])
        else { return nil }
        let south = (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased() == "S"
        let west = (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased() == "W"
        let point = GeoPoint(lat: south ? -lat : lat, lng: west ? -lng : lng)
        guard abs(point.lat) <= 90, abs(point.lng) <= 180, point != GeoPoint(lat: 0, lng: 0) else { return nil }
        return point
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber: n.doubleValue
        case let s as String: Double(s)
        default: nil
        }
    }
}
