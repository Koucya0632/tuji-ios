// Client-side image downscale for atlas capture. The backend caps stored images
// at 1600px anyway, and recognition only sees 1024px, so shipping the full-res
// phone photo (2–5 MB) is wasted upload time. Downscaling to ~1600px first cuts
// the upload to a few hundred KB.
//
// Uses ImageIO thumbnailing (CGImageSourceCreateThumbnailAtIndex) so a 12 MP
// photo is never fully decoded into a UIImage — it scales straight from the
// source, which is far lighter on memory than UIGraphics-based resizing.

import ImageIO
import UIKit

enum ImageDownscale {
    /// Downscale `data` so its longest side is at most `maxPixelSize`, honoring
    /// EXIF orientation, then JPEG-encode at `quality`. Returns nil if the data
    /// isn't a decodable image (caller should fall back to the original bytes).
    static func jpeg(from data: Data, maxPixelSize: Int = 1600, quality: CGFloat = 0.78) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: quality)
    }
}
