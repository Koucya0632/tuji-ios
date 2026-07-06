// 自制圖鑑「拍照快速新增」一鏡到底流程 (presented as a fullScreenCover from the
// 圖鑑 camera icon). Steps run top-to-bottom in one sheet:
//   1. 取得影像 — 拍照 (CameraPicker) 或 從相簿選 (PhotosPicker)
//   2. 上傳 → 自動 AI 識別
//   3. 校正候選 / 人工修正
//   4. 確認並生成卡片 → 成功後可「完成」或「再拍一張」
//
// The pipeline state + rules live in AtlasCaptureVM; this view only renders it
// and owns presentation-only state (covers, prompts, the pending crop frame).
// Management (list/delete/review) lives separately in AtlasManageView — this
// screen is create-only.

import NukeUI
import PhotosUI
import SwiftUI
import UIKit

struct AtlasCaptureView: View {
    @Environment(\.dismiss) private var dismiss

    /// Pipeline + form state. Replaced wholesale on 換一張 — a fresh VM *is* the
    /// reset, so there's no field-by-field clearing to keep in sync.
    @State private var vm = AtlasCaptureVM()

    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    /// A freshly picked frame awaiting the crop/preview step before upload. Wrapping
    /// the bytes in an Identifiable drives `.fullScreenCover(item:)` and re-creates
    /// the crop view per pick.
    @State private var pendingCrop: PendingCrop?
    @State private var confirmDismiss = false
    @State private var confirmRetake = false

    private struct PendingCrop: Identifiable {
        let id = UUID()
        let data: Data
    }

    var body: some View {
        @Bindable var vm = self.vm
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    self.statusMessage
                    self.uploadRetry
                    if let uploadedImage = self.vm.uploadedImage {
                        self.correctionPanel(uploadedImage)
                    } else {
                        self.sourcePanel
                    }
                }
                .padding(.horizontal, Space.s6)
                .padding(.vertical, Space.s4)
            }
            .background(.tujiBg)
            .navigationTitle("拍照新增")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        // Only warn when there's an in-progress capture to lose;
                        // on the bare source chooser just close.
                        if self.vm.uploadedImage != nil {
                            self.confirmDismiss = true
                        } else {
                            self.dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.tujiInk2)
                    }
                    .disabled(self.vm.busy != nil)
                }
            }
        }
        .fullScreenCover(isPresented: self.$showCamera) {
            CameraPicker(
                onCapture: { data in
                    self.showCamera = false
                    // Hand off to the crop cover only after the camera cover has
                    // dismissed — presenting a second fullScreenCover in the same
                    // runloop tick gets dropped by SwiftUI. (The 相簿 path has no
                    // such race; it isn't coming from another cover.)
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        self.pendingCrop = PendingCrop(data: data)
                    }
                },
                onCancel: { self.showCamera = false }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(item: self.$pendingCrop) { pending in
            ImageCropView(
                imageData: pending.data,
                onConfirm: { cropped in
                    self.pendingCrop = nil
                    Task { await self.vm.handlePicked(data: cropped) }
                },
                onCancel: { self.pendingCrop = nil }
            )
            .ignoresSafeArea()
        }
        .onChange(of: self.pickerItem) { _, newValue in
            guard let newValue else { return }
            Task {
                let data = await self.vm.loadPhotoData(newValue)
                self.pickerItem = nil
                if let data {
                    self.pendingCrop = PendingCrop(data: data)
                }
            }
        }
        .tujiPrompt(
            isPresented: self.$confirmDismiss,
            style: .destructive,
            title: "放棄這次辨識？",
            message: "這張照片的辨識與校正結果會清除，不會生成卡片。",
            primary: TujiPromptAction("放棄", role: .destructive) {
                self.vm.discardUploadedImage()
                self.dismiss()
            },
            secondary: TujiPromptAction("繼續校正", role: .cancel) {}
        )
        .tujiPrompt(
            isPresented: self.$confirmRetake,
            style: .destructive,
            title: "換一張照片？",
            message: "目前的辨識與校正結果會清除，再拍或選一張新的。",
            primary: TujiPromptAction("換一張", role: .destructive) {
                self.vm.discardUploadedImage()
                // Fresh VM = full reset back to the source chooser.
                self.vm = AtlasCaptureVM()
            },
            secondary: TujiPromptAction("取消", role: .cancel) {}
        )
        .tujiStatusToast(
            isPresented: self.vm.busy != nil,
            style: .recognizing
        )
        .task { await self.vm.prepareOnOpen() }
        .sheet(isPresented: $vm.showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Source chooser

    private var sourcePanel: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("拍下身邊的東西")
                    .font(.tujiH2)
                    .foregroundStyle(.tujiInk)
                Text("拍照後自動 AI 辨識，校正後一鍵生成學習卡片。")
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk3)
                // Free and Pro allowances differ (30 vs 500), so the hint names
                // the plan and its own limit instead of a shared count.
                if let remaining = self.vm.remainingPrimaryThisMonth,
                   let limit = self.vm.primaryLimitPerMonth
                {
                    if self.vm.isPro {
                        Text("Pro：本月 AI 辨識剩 \(remaining)／\(limit) 次")
                            .font(.tujiCaption)
                            .foregroundStyle(.tujiInk4)
                    } else {
                        Text("免費版：本月 AI 辨識剩 \(remaining)／\(limit) 次")
                            .font(.tujiCaption)
                            .foregroundStyle(.tujiInk4)
                    }
                }
            }

            if self.vm.atCapacity {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text(self.vm.capacityMessage)
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiCoral)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !self.vm.isPro {
                        Button {
                            self.vm.showPaywall = true
                        } label: {
                            Text("升級 Tuji Pro")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tujiTeal)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Space.s3)
                .background(Color.tujiCoral.opacity(0.12), in: .rect(cornerRadius: Radius.md))
            }

            if CameraPicker.isAvailable {
                Button {
                    self.showCamera = true
                } label: {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text("拍照")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s4)
                    .background(.tujiTeal, in: .rect(cornerRadius: Radius.lg))
                }
                .buttonStyle(.plain)
                .disabled(self.vm.busy != nil || self.vm.atCapacity)
            }

            PhotosPicker(selection: self.$pickerItem, matching: .images) {
                AtlasPickerPillLabel(title: "從相簿選", icon: "photo.on.rectangle")
            }
            .disabled(self.vm.busy != nil || self.vm.atCapacity)
        }
    }

    // MARK: - Correction (recognize + manual fields + confirm)

    private func correctionPanel(_ image: AtlasImageSummary) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            self.imagePreview(image)
            self.actionRow
            self.candidateSection
            self.correctionForm
        }
        .padding(Space.s4)
        .background(.tujiCard, in: .rect(cornerRadius: Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .stroke(.tujiInk4.opacity(0.25), lineWidth: 1)
        )
    }

    private func imagePreview(_ image: AtlasImageSummary) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("校正資料")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.tujiInk)
                Spacer()
                Button {
                    self.confirmRetake = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("換一張")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tujiInk3)
                }
                .buttonStyle(.plain)
                .disabled(self.vm.busy != nil)
            }
            ZStack {
                Rectangle().fill(.tujiBg)
                LazyImage(url: image.imageURL) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fit)
                    } else if state.error != nil {
                        Image(systemName: "photo")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.tujiInk4)
                    } else {
                        ProgressView().tint(.tujiTeal)
                    }
                }
            }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    private var actionRow: some View {
        HStack(spacing: Space.s2) {
            Button {
                self.vm.requestRecognize(.primary)
            } label: {
                self.smallActionLabel("AI 識別", icon: "sparkles")
            }
            .buttonStyle(.plain)
            .disabled(self.vm.busy != nil)

            Button {
                // 高精度 is Pro-only — a Free user goes straight to the paywall
                // instead of spending a call that the server would 402.
                if self.vm.precisionAvailable {
                    self.vm.requestRecognize(.escalate)
                } else {
                    self.vm.showPaywall = true
                }
            } label: {
                self.smallActionLabel("高精度", icon: "scope")
            }
            .buttonStyle(.plain)
            .disabled(self.vm.busy != nil)
        }
    }

    private func smallActionLabel(_ title: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.tujiInk)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s3)
        .background(.tujiBg, in: .rect(cornerRadius: Radius.md))
    }

    @ViewBuilder
    private var candidateSection: some View {
        if !self.vm.candidates.isEmpty {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("候選結果")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.tujiInk)
                let primary = self.vm.candidates.filter { $0.levelKind == .primary }
                let fine = self.vm.candidates.filter { $0.levelKind == .fine }
                self.candidateGroup(rows: primary)
                self.candidateGroup(rows: fine)
            }
        }
    }

    private func candidateGroup(rows: [AtlasCandidate]) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if !rows.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 120), spacing: Space.s2)],
                    alignment: .leading,
                    spacing: Space.s2
                ) {
                    ForEach(rows) { candidate in
                        Button {
                            self.vm.apply(candidate, overwrite: true)
                        } label: {
                            Text(self.vm.candidateLabel(candidate))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(self.vm.selectedCandidateId == candidate.id ? .white : .tujiInk)
                                .padding(.horizontal, Space.s3)
                                .padding(.vertical, Space.s2)
                                .background(
                                    self.vm.selectedCandidateId == candidate.id ? .tujiTeal : .tujiBg,
                                    in: .capsule
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var correctionForm: some View {
        @Bindable var vm = self.vm
        return VStack(alignment: .leading, spacing: Space.s3) {
            Text("人工校正")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tujiInk)
            self.field("圖片名稱", text: $vm.lemma)
            self.field("中文名稱", text: $vm.displayZhHant)

            BBtn(
                title: "確認並生成卡片",
                bg: .tujiTeal,
                fg: .white,
                fullWidth: true,
                icon: "checkmark"
            ) {
                // Enqueue and close the cover immediately — the user never
                // waits here.
                Task {
                    await self.vm.submit()
                    self.dismiss()
                }
            }
            .disabled(!self.vm.canSubmit)
        }
    }

    private func field(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk3)
            TextField("", text: text)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.tujiInk)
                .textInputAutocapitalization(.never)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s3)
                .background(.tujiBg, in: .rect(cornerRadius: Radius.md))
        }
    }

    /// Shown when the initial upload failed (typically weak network): re-upload
    /// the retained frame without making the user re-pick the photo.
    @ViewBuilder
    private var uploadRetry: some View {
        if self.vm.uploadedImage == nil, self.vm.errorMessage != nil, let data = self.vm.lastUploadData {
            Button {
                Task { await self.vm.handlePicked(data: data) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("重試上傳")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s3)
                .background(.tujiTeal, in: .rect(cornerRadius: Radius.md))
            }
            .buttonStyle(.plain)
            .disabled(self.vm.busy != nil)
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        if let errorMessage = self.vm.errorMessage {
            Text(errorMessage)
                .font(.tujiCaption)
                .foregroundStyle(.tujiCoral)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.s3)
                .background(Color.tujiCoral.opacity(0.12), in: .rect(cornerRadius: Radius.md))
        } else if let successMessage = self.vm.successMessage {
            Text(successMessage)
                .font(.tujiCaption)
                .foregroundStyle(.tujiTeal)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.s3)
                .background(Color.tujiTeal.opacity(0.12), in: .rect(cornerRadius: Radius.md))
        }
    }
}

/// Extracted so the PhotosPicker label (a `@Sendable`, nonisolated closure) can
/// construct it: `nonisolated` makes the init callable there, while `body` stays
/// MainActor and references the theme statics safely.
private nonisolated struct AtlasPickerPillLabel: View {
    let title: LocalizedStringKey
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: self.icon)
            Text(self.title)
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.tujiInk)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s4)
        .background(.tujiYellow, in: .rect(cornerRadius: Radius.lg))
    }
}

#Preview {
    AtlasCaptureView()
        .environment(AuthService.shared)
}
