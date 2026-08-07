// One pick → crop → encode → deliver flow, shared by 合集頭像 and 個人資料頭像.
//
// Both screens used to spell the same seven steps out in their own view bodies:
// the source dialog, the PhotosPicker, the camera cover, the 350 ms re-entry
// sleep before presenting the cropper, the transferable decode, the JPEG
// re-encode, and the delivery. They diverged in exactly the ways duplicated
// flows do — only 合集 carried the retry latch, only 合集 carried the sleep, and
// 合集's error row rendered its VM's shared `errorMessage`, which is defined as
// "a failed publish wins", as an *avatar upload* failure.
//
// Two adapters justify the seam: the two screens differ only in the encode
// profile, the crop mask, and what "deliver" means.

import Foundation
import Observation
import PhotosUI
import SwiftUI

/// How a picked photo is re-encoded before it leaves the device.
struct AvatarEncoding: Equatable {
    let maxPixelSize: Int
    let quality: CGFloat

    /// 個人資料 — circular, rendered at 104pt.
    static let profile = AvatarEncoding(maxPixelSize: 1200, quality: 0.86)
    /// 合集 — the public shelf tile renders it larger.
    static let collection = AvatarEncoding(maxPixelSize: 1600, quality: 0.82)
}

@MainActor
@Observable
final class AvatarPicker {
    enum Phase: Equatable {
        case idle
        /// Encoding, or handing the encoded photo to the caller.
        case working
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    /// The last encoded photo whose delivery failed, kept so 重試 can re-send the
    /// exact bytes rather than making the user pick the photo again.
    private(set) var retryData: Data?

    let encoding: AvatarEncoding
    let cropFrame: ImageCropFrame

    /// Presentation state owned by `AvatarPickerModifier`, which is the only
    /// thing that should touch it.
    var showSources = false
    var showPhotoLibrary = false
    var showCamera = false
    var pickerItem: PhotosPickerItem?
    var pendingCrop: PendingCrop?

    struct PendingCrop: Identifiable {
        let id = UUID()
        let data: Data
    }

    private var deliver: (Data) async -> Bool

    /// `deliver` returns whether the encoded photo was accepted — an upload for
    /// 合集, a local stash for 個人資料. Returning false parks the bytes for 重試.
    init(
        encoding: AvatarEncoding,
        cropFrame: ImageCropFrame = .circle,
        deliver: @escaping (Data) async -> Bool = { _ in false }
    ) {
        self.encoding = encoding
        self.cropFrame = cropFrame
        self.deliver = deliver
    }

    /// Connect the delivery once the screen's dependencies are reachable —
    /// SwiftUI gives a `@State` initializer no access to `@Environment`, so a
    /// screen whose upload needs environment values wires it from `.task`.
    func onDeliver(_ deliver: @escaping (Data) async -> Bool) {
        self.deliver = deliver
    }

    var isBusy: Bool {
        self.phase == .working
    }

    /// One error line for the whole flow. The two screens used to run two
    /// parallel error channels (a selection error and an upload error) and show
    /// whichever happened to be non-nil.
    var errorMessage: String? {
        if case let .failed(message) = self.phase { return message }
        return nil
    }

    var canRetry: Bool {
        self.retryData != nil && !self.isBusy
    }

    /// Open the 拍照 / 從相簿選擇 chooser.
    func begin() {
        guard !self.isBusy else { return }
        self.phase = .idle
        self.showSources = true
    }

    /// Re-send the last encoded photo that failed to deliver.
    func retry() async {
        guard let data = self.retryData, !self.isBusy else { return }
        await self.send(data)
    }

    // MARK: - Steps (driven by AvatarPickerModifier)

    func handlePicked(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            self.phase = .idle
            self.pendingCrop = PendingCrop(data: data)
        } catch {
            self.phase = .failed(error.localizedDescription)
        }
    }

    func handleCaptured(_ data: Data) async {
        // The camera cover has to finish dismissing before another
        // fullScreenCover will present; without the beat the cropper never
        // appears and the capture is silently dropped.
        try? await Task.sleep(for: .milliseconds(350))
        self.phase = .idle
        self.pendingCrop = PendingCrop(data: data)
    }

    func handleCropped(_ cropped: Data) async {
        self.pendingCrop = nil
        guard let encoded = ImageDownscale.jpeg(
            from: cropped,
            maxPixelSize: self.encoding.maxPixelSize,
            quality: self.encoding.quality
        )
        else {
            self.phase = .failed(tujiLocalized("無法讀取這張照片，請換一張再試。"))
            return
        }
        await self.send(encoded)
    }

    private func send(_ data: Data) async {
        self.phase = .working
        self.retryData = data
        if await self.deliver(data) {
            self.retryData = nil
            self.phase = .idle
        } else {
            self.phase = .failed(tujiLocalized("上傳失敗，請再試一次。"))
        }
    }
}

// MARK: - Presentation

/// One row in the source chooser.
///
/// A value rather than a `@ViewBuilder`: the chooser is a list of choices, which
/// this app draws as `TujiRow`s in a `tujiSheet`, and a caller handing over
/// arbitrary `Button`s cannot be drawn that way. Screens describe *what* they
/// offer; the sheet decides how it looks.
struct AvatarSource: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
}

private struct AvatarPickerModifier: ViewModifier {
    let picker: AvatarPicker
    let title: LocalizedStringKey
    let extraSources: [AvatarSource]

    private var sources: [AvatarSource] {
        var out: [AvatarSource] = []
        if CameraPicker.isAvailable {
            out.append(AvatarSource("拍照") { self.picker.showCamera = true })
        }
        out.append(AvatarSource("從相簿選擇") { self.picker.showPhotoLibrary = true })
        out.append(contentsOf: self.extraSources)
        return out
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: self.picker.pickerItem) { _, item in
                guard let item else { return }
                Task {
                    await self.picker.handlePicked(item)
                    self.picker.pickerItem = nil
                }
            }
            .tujiSheet(
                isPresented: Binding(
                    get: { self.picker.showSources },
                    set: { self.picker.showSources = $0 }
                ),
                title: self.title
            ) {
                AvatarSourceList(sources: self.sources)
            }
            .photosPicker(
                isPresented: Binding(
                    get: { self.picker.showPhotoLibrary },
                    set: { self.picker.showPhotoLibrary = $0 }
                ),
                selection: Binding(
                    get: { self.picker.pickerItem },
                    set: { self.picker.pickerItem = $0 }
                ),
                matching: .images
            )
            .fullScreenCover(isPresented: Binding(
                get: { self.picker.showCamera },
                set: { self.picker.showCamera = $0 }
            )) {
                CameraPicker(
                    onCapture: { data in
                        self.picker.showCamera = false
                        Task { await self.picker.handleCaptured(data) }
                    },
                    onCancel: { self.picker.showCamera = false }
                )
                .ignoresSafeArea()
            }
            .fullScreenCover(item: Binding(
                get: { self.picker.pendingCrop },
                set: { self.picker.pendingCrop = $0 }
            )) { pending in
                AvatarCropView(
                    imageData: pending.data,
                    onConfirm: { cropped in
                        Task { await self.picker.handleCropped(cropped) }
                    },
                    onCancel: { self.picker.pendingCrop = nil },
                    cropFrame: self.picker.cropFrame
                )
            }
    }
}

/// The rows themselves. Picking closes the sheet *before* the source opens: the
/// camera and the photo library are each another presentation, and asking UIKit
/// to put one up while this one is still sliding away drops it.
private struct AvatarSourceList: View {
    let sources: [AvatarSource]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(self.sources.enumerated()), id: \.element.id) { index, source in
                if index > 0 {
                    Rectangle()
                        .fill(.tujiRule)
                        .frame(height: Border.bw1)
                        .padding(.horizontal, Space.s4)
                }
                Button {
                    self.dismiss()
                    let action = source.action
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        action()
                    }
                } label: {
                    TujiRow(source.title, showsArrow: false)
                }
                .tujiRowStyle()
            }
        }
    }
}

extension View {
    /// Hosts the whole avatar flow's presentation. The screen keeps only the
    /// button that calls `picker.begin()` and whatever it renders from `phase`.
    ///
    /// `extraSources` are screen-specific rows in the chooser (個人資料 offers
    /// 使用預設黑貓頭像).
    func avatarPicker(
        _ picker: AvatarPicker,
        title: LocalizedStringKey,
        extraSources: [AvatarSource] = []
    )
        -> some View
    {
        self.modifier(
            AvatarPickerModifier(picker: picker, title: title, extraSources: extraSources)
        )
    }
}
