// The frame both croppers sit in: load the proxy, say what is happening while
// it loads or if it fails, and reserve the toolbar's height.
//
// `ImageIntakeCrop` keeps the two cropping *interactions* apart on purpose —
// 個人資料 is a fixed square with pan-and-zoom, 拍照新增 is four corner handles at
// any aspect, and squaring the second would crop the thing being identified.
// That decision was about the interaction. The shell around it was written
// twice, byte for byte.
//
// And it had already gone half-documented: `ImageCropView` carries four lines
// explaining why the toolbar is a `safeAreaInset` rather than an overlay — the
// bottom crop handles end up under the buttons for full-bleed sources like
// phone screenshots, whose aspect ratio matches the screen. `AvatarCropView`
// has the same line with no reason beside it, so the next person to edit it has
// nothing telling them not to float the toolbar instead.

import SwiftUI

/// Loads `imageData` into a display proxy, then hands it to `canvas`.
struct CropScaffold<Canvas: View, Toolbar: View, FailureAction: View>: View {
    let imageData: Data
    /// The loaded proxy, held by the screen rather than here: it is the subject
    /// the canvas draws *and* the toolbar acts on (「使用照片」 is disabled until
    /// it exists, and confirming reads its size). What this scaffold owns is how
    /// it gets loaded and what the screen shows meanwhile.
    @Binding var proxy: UIImage?
    /// The cropping surface, once there is something to crop.
    @ViewBuilder let canvas: (UIImage) -> Canvas
    @ViewBuilder let toolbar: () -> Toolbar
    /// What a reader can do when the photo will not load. The two croppers
    /// differ here and should: 拍照新增 can still upload the original, an avatar
    /// cannot, so one offers 繼續上傳原圖 and the other 返回.
    @ViewBuilder let failureAction: () -> FailureAction

    @State private var loadFailed = false

    var body: some View {
        ZStack {
            Color.tujiInk.ignoresSafeArea()

            Group {
                if let proxy {
                    self.canvas(proxy)
                } else if self.loadFailed {
                    self.failureView
                } else {
                    TujiProgressBar(progress: nil, track: .tujiPaper.opacity(0.2), fill: .tujiPaper)
                        .frame(width: 120)
                }
            }
            // Reserve the toolbar's height out of the crop area (instead of
            // floating it over the image) so the bottom crop handles never sit
            // under the buttons — the failure mode for full-bleed sources like
            // phone screenshots, whose aspect ratio matches the screen.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                self.toolbar()
            }
        }
        .task {
            // Off the main actor: decoding a full-resolution camera image on it
            // holds the first frame of the crop screen.
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

    private var failureView: some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle")
                .font(.tujiIcon(32, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
            Text("無法載入這張照片")
                .font(.tujiBody(.strong))
                .foregroundStyle(.white)
            self.failureAction()
        }
        .padding(Space.s4)
    }
}
