import Testing
import UIKit
import SwiftUI
@testable import Tuji

struct LaunchAssetTests {
    @Test @MainActor
    func nativePeekStartHasTheExpectedLogicalSize() throws {
        let image = try #require(UIImage(named: "LaunchLockupPeekStart"))

        #expect(image.size.width == 232)
        #expect(image.size.height == 230)
        #expect(UIImage(named: "LaunchMarkV2") == nil)
    }

    @Test @MainActor
    func launchBackgroundMatchesTujiPaper() throws {
        let traits = UITraitCollection(userInterfaceStyle: .light)
        let color = try #require(UIColor(named: "LaunchBg")?.resolvedColor(with: traits))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        let decomposed = color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        #expect(decomposed)
        #expect(abs(red - 251.0 / 255.0) < 0.001)
        #expect(abs(green - 247.0 / 255.0) < 0.001)
        #expect(abs(blue - 239.0 / 255.0) < 0.001)
        #expect(abs(alpha - 1) < 0.001)
    }

    @Test @MainActor
    func reduceMotionRendersTheFinishedLockupImmediately() throws {
        let reducedMotion = try self.renderedPNG(
            TujiBrandLockup(
                animateEntrance: true,
                reduceMotionOverride: true
            )
        )
        let finished = try self.renderedPNG(TujiBrandLockup())

        #expect(reducedMotion == finished)
    }

    @MainActor
    private func renderedPNG(_ content: some View) throws -> Data {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        return try #require(renderer.uiImage?.pngData())
    }
}
