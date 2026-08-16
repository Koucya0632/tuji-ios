import SwiftUI
import UIKit

enum ImageCropFrame: Equatable {
    case circle
    case square
}

/// Shared fixed-aspect cropper. The saved image is always square; the frame only
/// changes the preview mask so personal avatars remain circular while collection
/// source photos use the full rounded square.
struct AvatarCropView: View {
    let imageData: Data
    let onConfirm: (Data) -> Void
    let onCancel: () -> Void
    var cropFrame: ImageCropFrame = .circle

    @State private var proxy: UIImage?
    @State private var loadFailed = false
    @State private var working = false
    @State private var zoom: CGFloat = 1
    @State private var zoomBaseline: CGFloat?
    @State private var offset: CGSize = .zero
    @State private var dragBaseline: CGSize?
    @State private var viewportDiameter: CGFloat = 1

    private let maxZoom: CGFloat = 4

    var body: some View {
        ZStack {
            Color.tujiInk.ignoresSafeArea()
            Group {
                if let proxy {
                    self.cropCanvas(proxy)
                } else if self.loadFailed {
                    self.failureView
                } else {
                    TujiProgressBar(progress: nil, track: .tujiPaper.opacity(0.2), fill: .tujiPaper).frame(width: 120)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                self.toolbar
            }
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

    private func cropCanvas(_ proxy: UIImage) -> some View {
        GeometryReader { geo in
            let diameter = max(120, min(360, geo.size.width - 48, geo.size.height - 96))
            let viewport = CGRect(
                x: (geo.size.width - diameter) / 2,
                y: (geo.size.height - diameter) / 2,
                width: diameter,
                height: diameter
            )
            let baseSize = self.aspectFillSize(image: proxy.size, diameter: diameter)
            let renderedSize = CGSize(width: baseSize.width * self.zoom, height: baseSize.height * self.zoom)

            ZStack {
                Image(uiImage: proxy)
                    .resizable()
                    .frame(width: renderedSize.width, height: renderedSize.height)
                    .position(
                        x: viewport.midX + self.offset.width,
                        y: viewport.midY + self.offset.height
                    )

                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geo.size))
                    switch self.cropFrame {
                    case .circle:
                        path.addEllipse(in: viewport)
                    case .square:
                        path.addRoundedRect(
                            in: viewport,
                            cornerSize: CGSize(width: 18, height: 18)
                        )
                    }
                }
                .fill(.black.opacity(0.58), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                Group {
                    switch self.cropFrame {
                    case .circle:
                        Circle().stroke(.white, lineWidth: 2)
                    case .square:
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white, lineWidth: 2)
                    }
                }
                .frame(width: diameter, height: diameter)
                .position(x: viewport.midX, y: viewport.midY)
                .allowsHitTesting(false)

                Text("拖曳移動・雙指縮放")
                    .font(.tujiLabel)
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s2)
                    .background(.black.opacity(0.45), in: .rect(cornerRadius: Radius.r0))
                    .position(x: viewport.midX, y: max(28, viewport.minY - 30))
                    .allowsHitTesting(false)

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(self.dragGesture(baseSize: baseSize, diameter: diameter))
                    .simultaneousGesture(self.zoomGesture(baseSize: baseSize, diameter: diameter))
            }
            .onAppear { self.viewportDiameter = diameter }
            .onChange(of: diameter) { _, value in
                self.viewportDiameter = value
                self.offset = self.clampedOffset(
                    self.offset,
                    baseSize: baseSize,
                    diameter: value,
                    zoom: self.zoom
                )
            }
        }
    }

    private func aspectFillSize(image: CGSize, diameter: CGFloat) -> CGSize {
        guard image.width > 0, image.height > 0 else {
            return CGSize(width: diameter, height: diameter)
        }
        let scale = max(diameter / image.width, diameter / image.height)
        return CGSize(width: image.width * scale, height: image.height * scale)
    }

    private func dragGesture(baseSize: CGSize, diameter: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let baseline = self.dragBaseline ?? self.offset
                if self.dragBaseline == nil { self.dragBaseline = baseline }
                self.offset = self.clampedOffset(
                    CGSize(
                        width: baseline.width + value.translation.width,
                        height: baseline.height + value.translation.height
                    ),
                    baseSize: baseSize,
                    diameter: diameter,
                    zoom: self.zoom
                )
            }
            .onEnded { _ in self.dragBaseline = nil }
    }

    private func zoomGesture(baseSize: CGSize, diameter: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let baseline = self.zoomBaseline ?? self.zoom
                if self.zoomBaseline == nil { self.zoomBaseline = baseline }
                self.zoom = self.clamp(baseline * value.magnification, to: 1...self.maxZoom)
                self.offset = self.clampedOffset(
                    self.offset,
                    baseSize: baseSize,
                    diameter: diameter,
                    zoom: self.zoom
                )
            }
            .onEnded { _ in self.zoomBaseline = nil }
    }

    private func clampedOffset(
        _ proposed: CGSize,
        baseSize: CGSize,
        diameter: CGFloat,
        zoom: CGFloat
    )
        -> CGSize
    {
        let maxX = max(0, (baseSize.width * zoom - diameter) / 2)
        let maxY = max(0, (baseSize.height * zoom - diameter) / 2)
        return CGSize(
            width: self.clamp(proposed.width, to: -maxX...maxX),
            height: self.clamp(proposed.height, to: -maxY...maxY)
        )
    }

    private func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        min(range.upperBound, max(range.lowerBound, value))
    }

    private var toolbar: some View {
        HStack(spacing: Space.s3) {
            Button("取消") { self.onCancel() }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .disabled(self.working)

            Button("重設") {
                self.zoom = 1
                self.offset = .zero
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white.opacity(0.82))
            .disabled(self.working || self.proxy == nil)

            Spacer()

            BBtn(
                title: self.working ? "處理中…" : "使用照片",
                bg: .tujiBrandPrimary,
                fg: .tujiInk,
                icon: "checkmark"
            ) {
                self.confirm()
            }
            .disabled(self.working || self.proxy == nil)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    private var failureView: some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle")
                .font(.tujiIcon(32, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
            Text("無法載入這張照片")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Button("返回") { self.onCancel() }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tujiBrandPrimary)
        }
        .padding(Space.s4)
    }

    private func confirm() {
        guard let proxy else { return }
        self.working = true
        let data = self.imageData
        let imageSize = proxy.size
        let zoom = self.zoom
        let offset = self.offset
        Task {
            // Geometry is scale-independent: use an arbitrary unit circle to
            // convert the visible fixed viewport back into normalized image space.
            let diameter: CGFloat = 1
            let baseSize = self.aspectFillSize(image: imageSize, diameter: diameter)
            let rendered = CGSize(width: baseSize.width * zoom, height: baseSize.height * zoom)
            let scaledOffset = CGSize(
                width: offset.width / max(1, self.viewportDiameter),
                height: offset.height / max(1, self.viewportDiameter)
            )
            let rect = CGRect(
                x: (rendered.width / 2 - 0.5 - scaledOffset.width) / rendered.width,
                y: (rendered.height / 2 - 0.5 - scaledOffset.height) / rendered.height,
                width: 1 / rendered.width,
                height: 1 / rendered.height
            )
            let cropped = await Task.detached(priority: .userInitiated) {
                ImageCrop.crop(data: data, normalizedRect: rect)
            }.value
            self.onConfirm(cropped ?? data)
        }
    }
}
