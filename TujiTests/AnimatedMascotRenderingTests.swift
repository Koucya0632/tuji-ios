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

    func testHomeAtSmallAndLargeWidthsAndEveryLanguage() async throws {
        for (language, width, height) in [
            ("zh-Hant", 375.0, 667.0), ("zh-Hant", 402.0, 874.0),
            ("zh-Hans", 375.0, 667.0), ("ja", 375.0, 667.0), ("en", 375.0, 667.0)
        ] {
            try await self.homeSnapshot(
                language: language,
                size: CGSize(width: width, height: height),
                largeType: false
            )
        }
    }

    func testHomeAtAccessibilitySize() async throws {
        try await self.homeSnapshot(language: "zh-Hant", size: CGSize(width: 375, height: 667), largeType: true)
    }

    func testNativeHomeChatAndBackNavigation() async throws {
        XCTAssertFalse(StudyFocus.shared.active, "Snapshot hosting must release its focus ownership")
        let navigator = Self.navigator
        navigator.todayPath = NavigationPath()
        let host = UIHostingController(rootView: AssistantNavigationFixture(navigator: navigator)
            .environment(StudyFocus.shared)
            .environment(navigator)
            .environment(SettingsStore.shared))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            host.beginAppearanceTransition(false, animated: false)
            host.endAppearanceTransition()
            window.isHidden = true
            window.rootViewController = nil
            previousKey?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(250))
        navigator.push(.assistant)
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertTrue(StudyFocus.shared.active, "The assistant home hides the tab bar")
        XCTAssertEqual(self.fields(in: host.view).count, 1)
        navigator.push(.assistantChat(entry: .conversation))
        try await Task.sleep(for: .milliseconds(600))
        let field = try XCTUnwrap(self.fields(in: host.view).first { $0.isFirstResponder })
        XCTAssertTrue(StudyFocus.shared.active, "The chat keeps the tab bar hidden")
        XCTAssertLessThanOrEqual(field.convert(field.bounds, to: window).maxY, window.bounds.maxY)
        let keyboard = host.view.keyboardLayoutGuide.layoutFrame
        if keyboard.height > 100 {
            XCTAssertLessThanOrEqual(field.convert(field.bounds, to: host.view).maxY, keyboard.minY)
        }
        self.attach(UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }, name: "assistant-chat-keyboard")
        navigator.todayPath.removeLast()
        try await self.waitForNavigation {
            let fields = self.fields(in: host.view)
            return fields.count == 1 && fields.allSatisfy { $0 !== field } && StudyFocus.shared.active
        }
        self.attach(UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }, name: "assistant-home-return")
        XCTAssertTrue(StudyFocus.shared.active, "Returning to the home keeps its focus ownership")
        XCTAssertEqual(self.fields(in: host.view).count, 1)
        navigator.todayPath.removeLast()
        try await self.waitForNavigation {
            self.fields(in: host.view).isEmpty && !StudyFocus.shared.active
        }
        self.attach(UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }, name: "assistant-tab-root")
        XCTAssertFalse(StudyFocus.shared.active, "Returning to the tab root restores the tab bar")
    }

    private func waitForNavigation(_ settled: () -> Bool) async throws {
        // Keyboard dismissal can outlast the navigation animation. Observe the
        // completed destination instead of checking midway through that pop.
        for _ in 0..<60 {
            if settled() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Navigation did not settle")
    }

    private func fields(in view: UIView) -> [UITextField] {
        (view as? UITextField).map { [$0] } ?? view.subviews.flatMap { self.fields(in: $0) }
    }

    private func homeSnapshot(language: String, size: CGSize, largeType: Bool) async throws {
        let content = NavigationStack {
            AssistantHomeView()
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
            try await Task.sleep(for: .milliseconds(150))
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            if self.hasArtwork(image) {
                screenshot = image
                break
            }
        }
        let image = try XCTUnwrap(screenshot, "The screenshot must contain the rendered mascot, not an empty window")
        self.attach(
            image,
            name: "assistant-home-\(language)-\(Int(size.width))-\(largeType ? "large-type" : "default")"
        )
    }

    private func hasArtwork(_ image: UIImage) -> Bool {
        guard let image = image.cgImage, let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data)
        else { return false }
        // Dark pixels identify the black cat/text regardless of BGRA/RGBA order.
        var dark = 0
        for y in stride(from: 0, to: image.height, by: 4) {
            for x in stride(from: 0, to: image.width, by: 4) {
                let i = y * image.bytesPerRow + x * 4
                if bytes[i] < 90, bytes[i + 1] < 90, bytes[i + 2] < 90 { dark += 1 }
            }
        }
        return dark > 500
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

private struct AssistantNavigationFixture: View {
    @Bindable var navigator: TabNavigator

    var body: some View {
        NavigationStack(path: self.$navigator.todayPath) {
            Color.tujiPaper
                .navigationTitle(Text(verbatim: "Test root"))
                .tujiNavDestinations(user: nil)
        }
    }
}
