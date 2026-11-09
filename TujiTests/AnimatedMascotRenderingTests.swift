import SwiftUI
import UIKit
import XCTest
@testable import Tuji

@MainActor
final class AnimatedMascotRenderingTests: XCTestCase {
    /// Match the app's shell-owned lifetime rather than creating a transient
    /// environment navigator for each hosting window on the simulator.
    private static let navigator = TabNavigator()

    func testNativeBlinkRegistration() throws {
        let artwork = try XCTUnwrap(AnimatedMascotArtwork.shared)
        var frames: [UIImage] = []
        for time in [TimeInterval?.none, 0.025, 0.09, 0.18] {
            let frame = MascotAnimationFrame(elapsed: 0, blinkElapsed: time, wagElapsed: nil)
            let renderer = ImageRenderer(content: Canvas { context, size in
                artwork.draw(in: &context, size: size, frame: frame)
            }.frame(width: 600, height: 580))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage)
            frames.append(image)
            self.attach(image, name: "mascot-eyes-\(frames.count)")
        }
        for range in [170..<260, 300..<390] {
            let open = try XCTUnwrap(self.goldBounds(frames[0], xRange: range))
            XCTAssertGreaterThan(open.width, 50, "The actual native atlas must render")
            for index in [1, 3] {
                let half = try XCTUnwrap(self.goldBounds(frames[index], xRange: range))
                XCTAssertEqual(half.minX, open.minX, accuracy: 2)
                XCTAssertEqual(half.maxX, open.maxX, accuracy: 2)
                XCTAssertEqual(half.maxY, open.maxY, accuracy: 2)
                XCTAssertLessThan(half.height, open.height * 0.65)
            }
            XCTAssertNil(self.goldBounds(frames[2], xRange: range), "Closed eyes must not leave any gold behind")
        }
    }

    /// 一個測試、一輪迴圈，而不是兩個各自開視窗的測試。
    ///
    /// 這個 class 以前會掛在 `malloc: pointer being freed was not allocated`。
    /// 不是字型快取：崩潰堆疊是 app 自己的畫面（物見、我）在測試中途被拆掉，
    /// 它們的 model 走 MainActor 隔離 deinit 的 iOS 18 相容層
    /// （`swift_task_deinitOnExecutorMainActorBackDeploy`）時出事。測試宿主現在
    /// 不顯示 app 的畫面（`TujiApp.isHostingUnitTests`），就不會走到那裡。
    func testBandAcrossWidthsLanguagesAndTypeSizes() throws {
        for (language, width, height, largeType) in [
            ("zh-Hant", 375.0, 667.0, false), ("zh-Hant", 402.0, 874.0, false),
            ("zh-Hans", 375.0, 667.0, false), ("ja", 375.0, 667.0, false),
            ("en", 375.0, 667.0, false),
            ("zh-Hant", 375.0, 667.0, true)
        ] {
            try self.bandSnapshot(
                language: language,
                size: CGSize(width: width, height: height),
                largeType: largeType
            )
        }
    }

    private func bandSnapshot(language: String, size: CGSize, largeType: Bool) throws {
        let content = NavigationStack {
            VStack {
                MoiraFeatureBand()
                Spacer()
            }
        }
        .environment(StudyFocus.shared)
        .environment(Self.navigator)
        .environment(\.locale, Locale(identifier: language))
        .environment(\.dynamicTypeSize, largeType ? .accessibility3 : .large)
        let host = UIHostingController(rootView: content)
        host.traitOverrides.preferredContentSizeCategory = largeType ? .accessibilityExtraLarge : .large
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            host.beginAppearanceTransition(false, animated: false)
            host.endAppearanceTransition()
            window.isHidden = true
            window.rootViewController = nil
            previousKey?.makeKey()
        }
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.preferredRange = .standard
        var screenshot: UIImage?
        for _ in 0..<4 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            if self.hasRenderedContent(image) {
                screenshot = image
                break
            }
        }
        let image = try XCTUnwrap(screenshot, "The screenshot must contain the rendered band, not an empty window")
        self.attach(
            image,
            name: "moira-band-\(language)-\(Int(size.width))-\(largeType ? "large-type" : "default")"
        )
    }

    /// 畫進一塊自己配的記憶體，而不是直接讀 `CGImage` 的 data provider。
    ///
    /// 那個指標不保證活得比產生它的那個表達式久，在迴圈裡一路讀下去會把 heap
    /// 讀壞 —— 一起跑這個 class 就會收到
    /// `malloc: pointer being freed was not allocated`，單獨跑卻過。以前畫面
    /// 塞的是一隻 236pt 的實心黑貓，不透明、格式單純，所以沒爆出來；換成一條
    /// 淺底橫帶之後 CoreGraphics 選了別的表示法，它就現形了。
    /// 底下的 `goldBounds` 本來就是這樣畫的。
    private func hasRenderedContent(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        let width = cg.width
        let height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            )
            else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return false }
        // 數深色像素：四個線條圖示加四行 13pt 的字。門檻比以前低很多 —— 以前
        // 數的是一隻實心黑貓。
        var dark = 0
        for y in stride(from: 0, to: height, by: 4) {
            for x in stride(from: 0, to: width, by: 4) {
                let i = (y * width + x) * 4
                if pixels[i] < 90, pixels[i + 1] < 90, pixels[i + 2] < 90 { dark += 1 }
            }
        }
        return dark > 80
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        self.add(attachment)
    }

    private func goldBounds(_ image: UIImage, xRange: Range<Int>) -> CGRect? {
        guard let image = image.cgImage else { return nil }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            )
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var points: [CGPoint] = []
        for y in 155..<245 {
            for x in xRange {
                let i = (y * width + x) * 4
                if pixels[i] > 160, pixels[i + 1] > 110, pixels[i + 1] < 240,
                   pixels[i + 2] < 80, pixels[i + 3] > 220
                {
                    points.append(CGPoint(x: x, y: y))
                }
            }
        }
        guard let first = points.first else { return nil }
        return points.dropFirst().reduce(CGRect(origin: first, size: CGSize(width: 1, height: 1))) {
            $0.union(CGRect(origin: $1, size: CGSize(width: 1, height: 1)))
        }
    }
}
