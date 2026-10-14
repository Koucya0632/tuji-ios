import SwiftUI
import UIKit

/// Decodes/crops the atlas once, outside the animation's frame loop. Coordinates
/// are the calibrated 1254-unit source used by design/mascot-2d-v1/rig.js.
final class AnimatedMascotArtwork {
    static let shared = AnimatedMascotArtwork()

    private struct EyePatch {
        let image: UIImage
        let rect: CGRect
    }

    private let body: UIImage
    private let tail: UIImage
    private let halfEyes: [EyePatch]
    private let closedEyes: [EyePatch]

    init?() {
        guard let atlas = UIImage(named: "mascot-interactive-atlas")?.cgImage,
              let body = Self.crop(atlas, rect: CGRect(x: 0, y: 0, width: 650, height: 880)),
              let tail = Self.crop(atlas, rect: CGRect(x: 820, y: 180, width: 400, height: 640))
        else { return nil }
        self.body = body
        self.tail = tail
        let centers = [CGPoint(x: -84.185, y: 198.515), CGPoint(x: 44.065, y: 207.635)]
        let closed = [
            Self.patch(
                atlas,
                crop: CGRect(x: 80, y: 960, width: 230, height: 190),
                anchor: CGPoint(x: 190.5, y: 1067.5),
                scale: CGSize(width: 0.5, height: 0.5),
                center: centers[0]
            ),
            Self.patch(
                atlas,
                crop: CGRect(x: 350, y: 960, width: 230, height: 190),
                anchor: CGPoint(x: 463, y: 1067),
                scale: CGSize(width: 0.5, height: 0.5),
                center: centers[1]
            )
        ]
        let half = [
            Self.patch(
                atlas,
                crop: CGRect(x: 680, y: 960, width: 240, height: 190),
                anchor: CGPoint(x: 804, y: 1053),
                scale: CGSize(
                    width: 109 * 0.57 / 130,
                    height: 103 * 0.57 / 130
                ),
                center: centers[0]
            ),
            Self.patch(
                atlas,
                crop: CGRect(x: 955, y: 960, width: 235, height: 190),
                anchor: CGPoint(x: 1076, y: 1053.5),
                scale: CGSize(
                    width: 113 * 0.57 / 130,
                    height: 105 * 0.57 / 130
                ),
                center: centers[1]
            )
        ]
        guard closed.allSatisfy({ $0 != nil }), half.allSatisfy({ $0 != nil }) else { return nil }
        self.closedEyes = closed.compactMap(\.self)
        self.halfEyes = half.compactMap(\.self)
    }

    func draw(in context: inout GraphicsContext, size: CGSize, frame: MascotAnimationFrame) {
        let fit = min(size.width / 600, size.height / 580)
        context.translateBy(x: size.width / 2, y: (size.height - 580 * fit) / 2)
        context.scaleBy(x: fit, y: fit)
        context.fill(
            Path(ellipseIn: CGRect(x: -145, y: 495, width: 270, height: 20)),
            with: .color(.tujiInk.opacity(0.08))
        )
        var tailContext = context
        tailContext.translateBy(x: 82, y: 461)
        tailContext.rotate(by: .radians(frame.wag * 0.36))
        tailContext.draw(Image(uiImage: self.tail), in: CGRect(x: -50.4, y: -268.8, width: 192, height: 307.2))

        context.translateBy(x: -30, y: 510)
        context.scaleBy(x: 1 + frame.breath * 0.007, y: 1 + frame.breath * 0.012)
        context.rotate(by: .radians(frame.wag * 0.006))
        context.translateBy(x: 30, y: -510)
        context.draw(Image(uiImage: self.body), in: CGRect(x: -215, y: 5, width: 370.5, height: 501.6))
        let patches: [EyePatch] = switch frame.eyes {
        case .open: []
        case .half: self.halfEyes
        case .closed: self.closedEyes
        }
        for patch in patches {
            context.draw(Image(uiImage: patch.image), in: patch.rect)
        }
    }

    private static func crop(_ atlas: CGImage, rect: CGRect) -> UIImage? {
        let factor = CGFloat(atlas.width) / 1254
        let pixels = CGRect(
            x: rect.minX * factor,
            y: rect.minY * factor,
            width: rect.width * factor,
            height: rect.height * factor
        )
        guard let cropped = atlas.cropping(to: pixels) else { return nil }
        return UIImage(cgImage: cropped)
    }

    private static func patch(
        _ atlas: CGImage,
        crop: CGRect,
        anchor: CGPoint,
        scale: CGSize,
        center: CGPoint
    )
        -> EyePatch?
    {
        guard let image = Self.crop(atlas, rect: crop),
              let gradient = CGGradient(
                  colorsSpace: CGColorSpaceCreateDeviceGray(),
                  colors: [
                      CGColor(gray: 0, alpha: 1),
                      CGColor(gray: 0, alpha: 1),
                      CGColor(gray: 0, alpha: 0)
                  ] as CFArray,
                  locations: [0, 0.78, 1]
              )
        else { return nil }
        let local = CGPoint(x: anchor.x - crop.minX, y: anchor.y - crop.minY)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let masked = UIGraphicsImageRenderer(size: crop.size, format: format).image { renderer in
            image.draw(in: CGRect(origin: .zero, size: crop.size))
            let ctx = renderer.cgContext
            ctx.setBlendMode(.destinationIn)
            ctx.translateBy(x: local.x, y: local.y)
            ctx.scaleBy(x: 100, y: 90)
            ctx.drawRadialGradient(
                gradient,
                startCenter: .zero,
                startRadius: 0,
                endCenter: .zero,
                endRadius: 1,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        return EyePatch(image: masked, rect: CGRect(
            x: center.x - local.x * scale.width, y: center.y - local.y * scale.height,
            width: crop.width * scale.width, height: crop.height * scale.height
        ))
    }
}
