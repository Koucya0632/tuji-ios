// Full-screen preview + free-form crop for the 自制圖鑑 capture flow. Sits between
// the picker (camera / 相簿) and the upload pipeline: it shows the picked photo and
// lets the user drag four corner handles to box the subject before AI 辨識.
//
// The selection lives as a NORMALIZED rect (`cropN`, each side in [0,1] of the image)
// so it's independent of layout / device rotation. Display uses a downscaled upright
// proxy (ImageCrop.prepareProxy); the actual cut happens on the full-res original
// (ImageCrop.crop) only at confirm. Confirming without dragging passes the original
// bytes straight through, so this screen doubles as the "預覽" step for 相簿 picks.

import SwiftUI
import UIKit

struct ImageCropView: View {
    let imageData: Data
    /// The cropped JPEG, or the untouched original bytes when nothing was cropped /
    /// cropping failed. Always valid JPEG `Data` ready for the upload pipeline.
    let onConfirm: (Data) -> Void
    let onCancel: () -> Void

    @State private var proxy: UIImage?
    @State private var cropN = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// Snapshot of `cropN` captured at the start of a drag; nil while idle.
    @State private var dragBaseline: CGRect?
    @State private var loadFailed = false
    @State private var working = false

    /// Smallest normalized crop side — keeps a handle from crossing the opposite edge
    /// or collapsing the window.
    private let minSize: CGFloat = 0.12
    private let handleSize: CGFloat = 26
    private let hitSlop: CGFloat = 44

    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    var body: some View {
        ZStack {
            Color.tujiInk.ignoresSafeArea()

            if let proxy {
                self.cropCanvas(proxy)
            } else if self.loadFailed {
                self.failureView
            } else {
                ProgressView().tint(.white)
            }

            self.toolbar
        }
        .task {
            let data = self.imageData
            let loaded = await Task.detached(priority: .userInitiated) {
                ImageCrop.prepareProxy(data: data)
            }.value
            if let loaded {
                self.proxy = loaded
            } else {
                self.loadFailed = true
            }
        }
    }

    // MARK: - Canvas

    private func cropCanvas(_ proxy: UIImage) -> some View {
        GeometryReader { geo in
            let frame = self.displayedFrame(for: proxy.size, in: geo.size)
            let window = self.viewRect(self.cropN, in: frame)

            ZStack {
                Image(uiImage: proxy)
                    .resizable()
                    .aspectRatio(contentMode: .fit)

                // Dim everything outside the crop window (even-odd punches the hole).
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geo.size))
                    path.addRect(window)
                }
                .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                self.thirdsGrid(in: window)

                Rectangle()
                    .stroke(.white, lineWidth: 2)
                    .frame(width: window.width, height: window.height)
                    .position(x: window.midX, y: window.midY)
                    .allowsHitTesting(false)

                // Pan the whole window. Sits below the corner handles so the corners
                // win their hit area.
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: window.width, height: window.height)
                    .position(x: window.midX, y: window.midY)
                    .gesture(self.panGesture(in: frame))

                self.handle(.topLeft, window: window, frame: frame)
                self.handle(.topRight, window: window, frame: frame)
                self.handle(.bottomLeft, window: window, frame: frame)
                self.handle(.bottomRight, window: window, frame: frame)
            }
        }
        .ignoresSafeArea()
    }

    private func thirdsGrid(in window: CGRect) -> some View {
        Path { path in
            for i in 1...2 {
                let x = window.minX + window.width * CGFloat(i) / 3
                path.move(to: CGPoint(x: x, y: window.minY))
                path.addLine(to: CGPoint(x: x, y: window.maxY))
                let y = window.minY + window.height * CGFloat(i) / 3
                path.move(to: CGPoint(x: window.minX, y: y))
                path.addLine(to: CGPoint(x: window.maxX, y: y))
            }
        }
        .stroke(.white.opacity(0.35), lineWidth: 0.5)
        .allowsHitTesting(false)
    }

    private func handle(_ corner: Corner, window: CGRect, frame: CGRect) -> some View {
        let point = self.cornerPoint(corner, in: window)
        return Circle()
            .fill(.white)
            .overlay(Circle().stroke(.tujiTeal, lineWidth: 3))
            .frame(width: self.handleSize, height: self.handleSize)
            .frame(width: self.hitSlop, height: self.hitSlop) // larger touch target
            .contentShape(Rectangle())
            .position(x: point.x, y: point.y)
            .gesture(self.cornerGesture(corner, in: frame))
    }

    // MARK: - Gestures

    private func cornerGesture(_ corner: Corner, in frame: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let base = self.beginDrag()
                guard frame.width > 0, frame.height > 0 else { return }
                let dx = value.translation.width / frame.width
                let dy = value.translation.height / frame.height
                self.cropN = self.resized(base, corner: corner, dx: dx, dy: dy)
            }
            .onEnded { _ in self.dragBaseline = nil }
    }

    private func panGesture(in frame: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let base = self.beginDrag()
                guard frame.width > 0, frame.height > 0 else { return }
                let dx = (value.translation.width / frame.width)
                    .clamped(to: -base.minX...(1 - base.maxX))
                let dy = (value.translation.height / frame.height)
                    .clamped(to: -base.minY...(1 - base.maxY))
                self.cropN = base.offsetBy(dx: dx, dy: dy)
            }
            .onEnded { _ in self.dragBaseline = nil }
    }

    /// Capture `cropN` at the first change of a drag and reuse it for the rest, so the
    /// cumulative `translation` is applied against a stable origin.
    private func beginDrag() -> CGRect {
        if let dragBaseline { return dragBaseline }
        self.dragBaseline = self.cropN
        return self.cropN
    }

    /// Move one corner by a normalized delta, clamping so it stays in [0,1] and never
    /// crosses the opposite edge closer than `minSize`.
    private func resized(_ base: CGRect, corner: Corner, dx: CGFloat, dy: CGFloat) -> CGRect {
        var left = base.minX, right = base.maxX, top = base.minY, bottom = base.maxY
        switch corner {
        case .topLeft:
            left = (base.minX + dx).clamped(to: 0...(right - self.minSize))
            top = (base.minY + dy).clamped(to: 0...(bottom - self.minSize))
        case .topRight:
            right = (base.maxX + dx).clamped(to: (left + self.minSize)...1)
            top = (base.minY + dy).clamped(to: 0...(bottom - self.minSize))
        case .bottomLeft:
            left = (base.minX + dx).clamped(to: 0...(right - self.minSize))
            bottom = (base.maxY + dy).clamped(to: (top + self.minSize)...1)
        case .bottomRight:
            right = (base.maxX + dx).clamped(to: (left + self.minSize)...1)
            bottom = (base.maxY + dy).clamped(to: (top + self.minSize)...1)
        }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    // MARK: - Geometry

    /// Aspect-fit the image inside `container`, returning the displayed image frame.
    private func displayedFrame(for imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              container.width > 0, container.height > 0
        else { return .zero }
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = container.width / container.height
        let dw: CGFloat
        let dh: CGFloat
        if containerAspect > imageAspect {
            dh = container.height
            dw = dh * imageAspect
        } else {
            dw = container.width
            dh = dw / imageAspect
        }
        return CGRect(x: (container.width - dw) / 2, y: (container.height - dh) / 2, width: dw, height: dh)
    }

    private func viewRect(_ norm: CGRect, in frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX + norm.minX * frame.width,
            y: frame.minY + norm.minY * frame.height,
            width: norm.width * frame.width,
            height: norm.height * frame.height
        )
    }

    private func cornerPoint(_ corner: Corner, in window: CGRect) -> CGPoint {
        switch corner {
        case .topLeft: CGPoint(x: window.minX, y: window.minY)
        case .topRight: CGPoint(x: window.maxX, y: window.minY)
        case .bottomLeft: CGPoint(x: window.minX, y: window.maxY)
        case .bottomRight: CGPoint(x: window.maxX, y: window.maxY)
        }
    }

    // MARK: - Toolbar & failure

    private var toolbar: some View {
        VStack {
            Spacer()
            HStack(spacing: Space.s3) {
                Button {
                    self.onCancel()
                } label: {
                    Text("取消")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, Space.s3)
                        .padding(.horizontal, Space.s4)
                }
                .disabled(self.working)

                if self.proxy != nil {
                    Button {
                        self.cropN = CGRect(x: 0, y: 0, width: 1, height: 1)
                    } label: {
                        Text("重設")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.vertical, Space.s3)
                            .padding(.horizontal, Space.s4)
                    }
                    .disabled(self.working)
                }

                Spacer()

                BBtn(
                    title: self.working ? "處理中…" : "使用裁切",
                    bg: .tujiTeal,
                    fg: .white,
                    icon: "checkmark"
                ) {
                    self.confirm()
                }
                .disabled(self.working || self.proxy == nil)
            }
            .padding(.horizontal, Space.s5)
            .padding(.bottom, Space.s4)
        }
    }

    private var failureView: some View {
        VStack(spacing: Space.s4) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
            Text("無法載入這張照片")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            BBtn(title: "繼續上傳原圖", bg: .tujiTeal, fg: .white, icon: "arrow.up") {
                self.onConfirm(self.imageData)
            }
        }
        .padding(Space.s6)
    }

    private func confirm() {
        self.working = true
        let data = self.imageData
        let norm = self.cropN
        Task {
            let cropped = await Task.detached(priority: .userInitiated) {
                ImageCrop.crop(data: data, normalizedRect: norm)
            }.value
            self.onConfirm(cropped ?? data)
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
