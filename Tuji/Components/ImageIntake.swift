// One pick → crop → encode → deliver flow, shared by 合集頭像, 個人資料頭像 and
// 拍照新增.
//
// This was `AvatarPicker`, and its own header explained why it existed: two
// screens had each spelled the same seven steps out in their view bodies — the
// source dialog, the PhotosPicker, the camera cover, the 350 ms re-entry sleep
// before presenting the cropper, the transferable decode, the JPEG re-encode,
// and the delivery — and they had diverged in exactly the ways duplicated flows
// do.
//
// A third screen was still doing it. 拍照新增 carried its own `showCamera`,
// `pickerItem` and `PendingCrop` state, its own 350 ms beat (in the *view*,
// where the other two had moved it into the model), its own transferable
// decode, its own downscale, and its own park-the-bytes retry under a second
// name (`lastUploadData` rather than `retryData`). It was never migrated because
// the module was named after avatars, and 拍照新增 is not one.
//
// Three adapters now. They differ in the encode profile, which cropper they
// present, and what "deliver" means.

import Foundation
import Observation
import PhotosUI
import SwiftUI

/// How a picked photo is re-encoded before it leaves the device.
struct ImageIntakeEncoding: Equatable {
    let maxPixelSize: Int
    let quality: CGFloat

    /// 個人資料 — circular, rendered at 104pt.
    static let profile = ImageIntakeEncoding(maxPixelSize: 1200, quality: 0.86)
    /// 合集 — the public shelf tile renders it larger.
    static let collection = ImageIntakeEncoding(maxPixelSize: 1600, quality: 0.82)
    /// 拍照新增 — the backend caps stored images at 1600 and recognition only
    /// ever sees 1024, so anything larger is upload time spent on nothing.
    static let capture = ImageIntakeEncoding(maxPixelSize: 1600, quality: 0.78)
}

/// Which cropper the flow presents. The two are genuinely different
/// interactions, which is why they stay two implementations — everything
/// around them is shared.
enum ImageIntakeCrop: Equatable {
    /// Fixed square, pan and pinch. The saved image is always square; the mask
    /// only changes the preview, so personal avatars stay circular.
    case square(mask: ImageCropFrame)
    /// Four corner handles, any aspect. 拍照新增 boxes a subject for AI 辨識,
    /// and squaring that would crop the thing being identified.
    case freeform
}

/// What the screen did with the encoded bytes.
enum ImageIntakeDelivery: Equatable {
    case accepted
    /// Rejected — the bytes are parked for 重試. The message is the screen's
    /// own, because a server's description of the failure beats a generic line;
    /// nil falls back to the generic one.
    case rejected(String?)
}

@MainActor
@Observable
final class ImageIntake {
    /// Where a photo can come from, for a screen that presents its own
    /// affordances instead of the chooser sheet.
    enum Source {
        case camera
        case photoLibrary
    }

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

    let encoding: ImageIntakeEncoding
    let crop: ImageIntakeCrop

    /// Presentation state owned by `ImageIntakeModifier`, which is the only
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

    private var deliver: (Data) async -> ImageIntakeDelivery

    init(
        encoding: ImageIntakeEncoding,
        crop: ImageIntakeCrop = .square(mask: .circle),
        deliver: @escaping (Data) async -> ImageIntakeDelivery = { _ in .rejected(nil) }
    ) {
        self.encoding = encoding
        self.crop = crop
        self.deliver = deliver
    }

    /// Connect the delivery once the screen's dependencies are reachable —
    /// SwiftUI gives a `@State` initializer no access to `@Environment`, so a
    /// screen whose upload needs environment values wires it from `.task`.
    func onDeliver(_ deliver: @escaping (Data) async -> ImageIntakeDelivery) {
        self.deliver = deliver
    }

    var isBusy: Bool {
        self.phase == .working
    }

    /// One error line for the whole flow. The two avatar screens used to run two
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

    /// Go straight to one source, for a screen that draws its own buttons.
    /// 拍照新增's source panel carries the remaining-quota line and the capacity
    /// warning, which a list of chooser rows cannot.
    func pick(_ source: Source) {
        guard !self.isBusy else { return }
        self.phase = .idle
        switch source {
        case .camera: self.showCamera = true
        case .photoLibrary: self.showPhotoLibrary = true
        }
    }

    /// Re-send the last encoded photo that failed to deliver.
    func retry() async {
        guard let data = self.retryData, !self.isBusy else { return }
        await self.send(data)
    }

    // MARK: - Steps (driven by ImageIntakeModifier)

    func handlePicked(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                self.phase = .failed(tujiLocalized("讀取照片失敗"))
                return
            }
            self.phase = .idle
            self.pendingCrop = PendingCrop(data: data)
        } catch {
            self.phase = .failed(tujiUserMessage(for: error))
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
        switch await self.deliver(data) {
        case .accepted:
            self.retryData = nil
            self.phase = .idle
        case let .rejected(message):
            self.phase = .failed(message ?? tujiLocalized("上傳失敗，請再試一次。"))
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
struct ImageIntakeChoice: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
}

private struct ImageIntakeModifier: ViewModifier {
    let intake: ImageIntake
    let title: LocalizedStringKey
    let extraChoices: [ImageIntakeChoice]

    private var choices: [ImageIntakeChoice] {
        var out: [ImageIntakeChoice] = []
        if CameraPicker.isAvailable {
            out.append(ImageIntakeChoice("拍照") { self.intake.showCamera = true })
        }
        out.append(ImageIntakeChoice("從相簿選擇") { self.intake.showPhotoLibrary = true })
        out.append(contentsOf: self.extraChoices)
        return out
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: self.intake.pickerItem) { _, item in
                guard let item else { return }
                Task {
                    await self.intake.handlePicked(item)
                    self.intake.pickerItem = nil
                }
            }
            .tujiSheet(
                isPresented: Binding(
                    get: { self.intake.showSources },
                    set: { self.intake.showSources = $0 }
                ),
                title: self.title
            ) {
                ImageIntakeChoiceList(choices: self.choices)
            }
            .photosPicker(
                isPresented: Binding(
                    get: { self.intake.showPhotoLibrary },
                    set: { self.intake.showPhotoLibrary = $0 }
                ),
                selection: Binding(
                    get: { self.intake.pickerItem },
                    set: { self.intake.pickerItem = $0 }
                ),
                matching: .images
            )
            .fullScreenCover(isPresented: Binding(
                get: { self.intake.showCamera },
                set: { self.intake.showCamera = $0 }
            )) {
                CameraPicker(
                    onCapture: { data in
                        self.intake.showCamera = false
                        Task { await self.intake.handleCaptured(data) }
                    },
                    onCancel: { self.intake.showCamera = false }
                )
                .ignoresSafeArea()
            }
            .fullScreenCover(item: Binding(
                get: { self.intake.pendingCrop },
                set: { self.intake.pendingCrop = $0 }
            )) { pending in
                self.cropper(pending.data)
            }
    }

    /// The one place the two croppers are chosen between. Their interactions
    /// differ — corner handles vs pan-and-zoom — but everything on either side
    /// of them is this module's.
    @ViewBuilder
    private func cropper(_ data: Data) -> some View {
        switch self.intake.crop {
        case let .square(mask):
            AvatarCropView(
                imageData: data,
                onConfirm: { cropped in
                    Task { await self.intake.handleCropped(cropped) }
                },
                onCancel: { self.intake.pendingCrop = nil },
                cropFrame: mask
            )
        case .freeform:
            ImageCropView(
                imageData: data,
                onConfirm: { cropped in
                    Task { await self.intake.handleCropped(cropped) }
                },
                onCancel: { self.intake.pendingCrop = nil }
            )
        }
    }
}

/// The rows themselves. Picking closes the sheet *before* the source opens: the
/// camera and the photo library are each another presentation, and asking UIKit
/// to put one up while this one is still sliding away drops it.
private struct ImageIntakeChoiceList: View {
    let choices: [ImageIntakeChoice]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(self.choices.enumerated()), id: \.element.id) { index, choice in
                if index > 0 {
                    Rectangle()
                        .fill(.tujiRule)
                        .frame(height: Border.bw1)
                        .padding(.horizontal, Space.s4)
                }
                Button {
                    self.dismiss()
                    let action = choice.action
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        action()
                    }
                } label: {
                    TujiRow(choice.title, showsArrow: false)
                }
                .tujiRowStyle()
            }
        }
    }
}

extension View {
    /// Hosts the whole intake flow's presentation. The screen keeps only the
    /// affordance that starts it — `begin()` for the chooser sheet, `pick(_:)`
    /// for a screen with its own buttons — and whatever it renders from `phase`.
    ///
    /// `extraChoices` are screen-specific rows in the chooser (個人資料 offers
    /// 使用預設黑貓頭像).
    func imageIntake(
        _ intake: ImageIntake,
        title: LocalizedStringKey,
        extraChoices: [ImageIntakeChoice] = []
    )
        -> some View
    {
        self.modifier(
            ImageIntakeModifier(intake: intake, title: title, extraChoices: extraChoices)
        )
    }
}
