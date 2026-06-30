// Client-side crop for atlas capture, sibling of ImageDownscale. Both helpers use
// the same ImageIO thumbnail idiom (CGImageSourceCreateThumbnailAtIndex with
// kCGImageSourceCreateThumbnailWithTransform) so the image is decoded UPRIGHT —
// EXIF / UIImage.imageOrientation is baked into the pixels. That's the whole trick:
//
//   • `prepareProxy` returns an upright, downscaled UIImage for the crop UI to
//     display and gesture over (a 12 MP photo is never shown at full res).
//   • `crop` independently re-decodes the source UPRIGHT at full resolution and
//     cuts out a normalized [0,1] rectangle.
//
// Because both paths are upright and share the same aspect ratio, the normalized
// rect chosen on the proxy maps 1:1 onto the full-res crop with no pixel-size or
// orientation bookkeeping — and SwiftUI view space and CGImage pixel space both use
// a top-left origin, so there's no y-flip either.

import ImageIO
import UIKit

enum ImageCrop {
    /// Decode an upright, downscaled proxy for the crop UI. `proxyMaxPixel` caps the
    /// longest side. Returns nil if the data isn't a decodable image.
    ///
    /// `nonisolated` (this target defaults to MainActor isolation): pure ImageIO
    /// work with no main-actor state, and callers run it in `Task.detached` to
    /// keep the decode off the main thread.
    nonisolated static func prepareProxy(data: Data, proxyMaxPixel: Int = 2048) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: proxyMaxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    /// Crop `data` to `normalizedRect` (each component in [0,1], image space) and
    /// JPEG-encode at `quality`. The high default quality is intentional: the result
    /// is re-compressed by `ImageDownscale.jpeg` (0.78) before upload, so encoding
    /// soft here would compound the loss.
    ///
    /// Returns nil when the rect is effectively the whole image (caller should pass
    /// the original bytes through untouched — no point decoding full res to re-encode
    /// the same frame) or when the data isn't decodable / the rect is degenerate.
    ///
    /// `nonisolated` for the same reason as `prepareProxy`: pure, off-main work.
    nonisolated static func crop(data: Data, normalizedRect: CGRect, quality: CGFloat = 0.92) -> Data? {
        let eps: CGFloat = 0.005
        if normalizedRect.minX <= eps, normalizedRect.minY <= eps,
           normalizedRect.maxX >= 1 - eps, normalizedRect.maxY >= 1 - eps
        {
            return nil
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelW = props[kCGImagePropertyPixelWidth] as? Int,
              let pixelH = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }

        // Ask for the image at its full size (max of the pre-transform dimensions is
        // orientation-invariant), upright. FromImageAlways guarantees a fresh decode
        // rather than a small embedded EXIF thumbnail.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(pixelW, pixelH)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let pixelRect = CGRect(
            x: normalizedRect.minX * width,
            y: normalizedRect.minY * height,
            width: normalizedRect.width * width,
            height: normalizedRect.height * height
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        guard !pixelRect.isNull, pixelRect.width >= 1, pixelRect.height >= 1,
              let cropped = cgImage.cropping(to: pixelRect)
        else { return nil }

        return UIImage(cgImage: cropped).jpegData(compressionQuality: quality)
    }
}
