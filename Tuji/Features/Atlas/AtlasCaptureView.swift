// 自制圖鑑「拍照快速新增」一鏡到底流程 (presented as a fullScreenCover from the
// 圖鑑 camera icon). Steps run top-to-bottom in one sheet:
//   1. 取得影像 — 拍照 (CameraPicker) 或 從相簿選 (PhotosPicker)
//   2. 上傳 → 自動 AI 識別
//   3. 校正候選 / 人工修正
//   4. 確認並生成卡片 → 成功後可「完成」或「再拍一張」
//
// The whole upload → recognize → confirm → createCards pipeline is reused from
// AtlasStore; this view just sequences it. Management (list/delete/review) lives
// separately in AtlasManageView — this screen is create-only.

import NukeUI
import PhotosUI
import SwiftUI
import UIKit

struct AtlasCaptureView: View {
    @State private var store = AtlasStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var uploadedImage: AtlasImageSummary?
    @State private var candidates: [AtlasCandidate] = []
    @State private var selectedCandidateId: String?
    @State private var primaryLabel = ""
    @State private var fineLabel = ""
    @State private var lemma = ""
    @State private var displayZhHant = ""
    @State private var partOfSpeech = "noun"
    @State private var category = ""
    /// The downscaled frame kept around to seed the 圖鑑 progress placeholder.
    @State private var localThumbnail: UIImage?

    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    /// A freshly picked frame awaiting the crop/preview step before upload. Wrapping
    /// the bytes in an Identifiable drives `.fullScreenCover(item:)` and re-creates
    /// the crop view per pick.
    @State private var pendingCrop: PendingCrop?
    @State private var busy: Busy?
    @State private var errorMessage: String?
    @State private var successMessage: String?

    /// Each recognition mode (primary / escalate) runs at most once and its
    /// candidates are kept here — a re-run barely differs and just burns another
    /// AI call, so tapping a mode again re-shows its cached set for free.
    @State private var candidatesByMode: [String: [AtlasCandidate]] = [:]
    @State private var confirmDismiss = false
    @State private var confirmRetake = false

    private enum Busy: String {
        case upload, recognize
    }

    private struct PendingCrop: Identifiable {
        let id = UUID()
        let data: Data
    }

    /// At the tier's 自製圖鑑 capacity — capture is blocked until the user frees a
    /// slot or upgrades. Unknown entitlement resolves to "allow" (server enforces).
    private var atCapacity: Bool {
        !AtlasQuotas.canCreateItem(self.store.entitlement)
    }

    private var capacityMessage: String {
        if let max = self.store.entitlement?.limits.maxItems {
            "自製圖鑑已達上限（\(max)），刪除一些或升級後再新增。"
        } else {
            "自製圖鑑已達上限，刪除一些後再新增。"
        }
    }

    /// Remaining AI recognitions today when the tier is limited; nil = unlimited.
    private var remainingAiToday: Int? {
        AtlasQuotas.remainingAi(self.store.entitlement)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    self.statusMessage
                    if let uploadedImage {
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
                        if self.uploadedImage != nil {
                            self.confirmDismiss = true
                        } else {
                            self.dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(.tujiInk2)
                    }
                    .disabled(self.busy != nil)
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
                    Task { await self.handlePicked(data: cropped) }
                },
                onCancel: { self.pendingCrop = nil }
            )
            .ignoresSafeArea()
        }
        .onChange(of: self.pickerItem) { _, newValue in
            guard let newValue else { return }
            Task { await self.loadFromLibrary(newValue) }
        }
        .tujiPrompt(
            isPresented: self.$confirmDismiss,
            style: .destructive,
            title: "放棄這次辨識？",
            message: "這張照片的辨識與校正結果會清除，不會生成卡片。",
            primary: TujiPromptAction("放棄", role: .destructive) {
                self.discardUploadedImage()
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
                self.discardUploadedImage()
                self.reset()
            },
            secondary: TujiPromptAction("取消", role: .cancel) {}
        )
        .tujiStatusToast(
            isPresented: self.busy == .upload || self.busy == .recognize,
            style: .recognizing
        )
        .task {
            // Fresh tier / usage so capture gating and remaining-quota copy are
            // current when the sheet opens.
            await self.store.refreshEntitlement()
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
                if let remaining = self.remainingAiToday {
                    Text("今日 AI 辨識剩 \(remaining) 次")
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiInk4)
                }
            }

            if self.atCapacity {
                Text(self.capacityMessage)
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiCoral)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s4)
                    .background(.tujiTeal, in: .rect(cornerRadius: Radius.lg))
                }
                .buttonStyle(.plain)
                .disabled(self.busy != nil || self.atCapacity)
            }

            PhotosPicker(selection: self.$pickerItem, matching: .images) {
                AtlasPickerPillLabel(title: "從相簿選", icon: "photo.on.rectangle")
            }
            .disabled(self.busy != nil || self.atCapacity)

        }
    }

    // MARK: - Correction (recognize + manual fields + confirm)

    private func correctionPanel(_ image: AtlasImageSummary) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            self.imagePreview(image)
            self.actionRow(image)
            self.candidateSection
            self.correctionForm(image)
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
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.tujiInk)
                Spacer()
                Button {
                    self.confirmRetake = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("換一張")
                    }
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.tujiInk3)
                }
                .buttonStyle(.plain)
                .disabled(self.busy != nil)
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

    private func actionRow(_ image: AtlasImageSummary) -> some View {
        HStack(spacing: Space.s2) {
            Button {
                self.requestRecognize(imageId: image.id, mode: "primary")
            } label: {
                self.smallActionLabel("AI 識別", icon: "sparkles")
            }
            .buttonStyle(.plain)
            .disabled(self.busy != nil)

            Button {
                self.requestRecognize(imageId: image.id, mode: "escalate")
            } label: {
                self.smallActionLabel("高精度", icon: "scope")
            }
            .buttonStyle(.plain)
            .disabled(self.busy != nil)
        }
    }

    private func smallActionLabel(_ title: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.system(size: 13, weight: .heavy))
        .foregroundStyle(.tujiInk)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s3)
        .background(.tujiBg, in: .rect(cornerRadius: Radius.md))
    }

    @ViewBuilder
    private var candidateSection: some View {
        if !self.candidates.isEmpty {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("候選結果")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.tujiInk)
                let primary = self.candidates.filter { $0.level == "primary" }
                let fine = self.candidates.filter { $0.level == "fine" }
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
                            self.apply(candidate, overwrite: true)
                        } label: {
                            Text(self.candidateLabel(candidate))
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(self.selectedCandidateId == candidate.id ? .white : .tujiInk)
                                .padding(.horizontal, Space.s3)
                                .padding(.vertical, Space.s2)
                                .background(
                                    self.selectedCandidateId == candidate.id ? .tujiTeal : .tujiBg,
                                    in: .capsule
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func correctionForm(_ image: AtlasImageSummary) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("人工校正")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(.tujiInk)
            // Only the two names are editable; primaryLabel / fineLabel /
            // partOfSpeech / category stay populated from the AI candidate via
            // apply(_:) and are sent through on confirm without cluttering the UI.
            self.field("圖片名稱", text: self.$lemma)
            self.field("中文名稱", text: self.$displayZhHant)

            BBtn(
                title: "確認並生成卡片",
                bg: .tujiTeal,
                fg: .white,
                fullWidth: true,
                icon: "checkmark"
            ) {
                self.submit(imageId: image.id)
            }
            .disabled(
                self.busy != nil
                    || self.lemma.trimmingCharacters(in: .whitespaces).isEmpty
                    || self.displayZhHant.trimmingCharacters(in: .whitespaces).isEmpty
            )
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

    @ViewBuilder
    private var statusMessage: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.tujiCaption)
                .foregroundStyle(.tujiCoral)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.s3)
                .background(Color.tujiCoral.opacity(0.12), in: .rect(cornerRadius: Radius.md))
        } else if let successMessage {
            Text(successMessage)
                .font(.tujiCaption)
                .foregroundStyle(.tujiTeal)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.s3)
                .background(Color.tujiTeal.opacity(0.12), in: .rect(cornerRadius: Radius.md))
        }
    }

    // MARK: - Pipeline

    private func loadFromLibrary(_ item: PhotosPickerItem) async {
        self.errorMessage = nil
        self.successMessage = nil
        defer { self.pickerItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw AtlasCaptureError.missingPhotoData
            }
            self.pendingCrop = PendingCrop(data: data)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    /// Upload one captured/picked frame, then immediately kick AI recognition so
    /// the flow feels one-shot.
    private func handlePicked(data: Data) async {
        self.busy = .upload
        self.errorMessage = nil
        self.successMessage = nil
        do {
            let encoded = ImageDownscale.jpeg(from: data) ?? data
            self.localThumbnail = UIImage(data: encoded)
            let response = try await self.store.uploadImage(
                data: encoded,
                filename: "atlas-photo.jpg",
                mimeType: "image/jpeg"
            )
            self.uploadedImage = response.image
            self.busy = nil
            // Candidates ride back with the upload now (recognition runs inline
            // server-side) — no separate recognize round trip on the first pass.
            // Cache it so a later AI 識別 tap re-shows the same set for free.
            self.candidatesByMode["primary"] = response.candidates ?? []
            self.applyCandidates(response.candidates ?? [])
        } catch {
            self.busy = nil
            self.errorMessage = error.localizedDescription
        }
    }

    /// AI 識別 / 高精度 tap. A mode is recognized at most once; if we already
    /// have its candidates, re-show them for free rather than spending another
    /// AI call (the result barely changes on a re-run). An empty / failed result
    /// isn't treated as final, so it can still be retried.
    private func requestRecognize(imageId: String, mode: String) {
        if let cached = self.candidatesByMode[mode], !cached.isEmpty {
            self.applyCandidates(cached)
        } else {
            Task { await self.recognize(imageId: imageId, mode: mode) }
        }
    }

    /// Run recognition once for a mode (AI 識別 = primary, 高精度 = escalate) and
    /// cache the result; repeat taps re-show the cache via `requestRecognize`.
    private func recognize(imageId: String, mode: String) async {
        self.busy = .recognize
        self.errorMessage = nil
        self.successMessage = nil
        defer { self.busy = nil }
        do {
            let response = try await self.store.recognize(imageId: imageId, mode: mode)
            self.candidatesByMode[mode] = response.candidates
            self.applyCandidates(response.candidates)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private func applyCandidates(_ list: [AtlasCandidate]) {
        self.candidates = list.sorted { $0.rank < $1.rank }
        if let best = self.candidates.first(where: { $0.level == "fine" }) ?? self.candidates.first {
            self.apply(best)
        }
        self.successMessage = list.isEmpty
            ? "沒有自動辨識到，請手動填寫或按「AI 識別」重試。"
            : "已辨識，確認名稱後即可生成卡片。"
    }

    /// `overwrite` is true when the user taps a candidate chip — their explicit
    /// choice replaces the name fields. It's false for the auto-apply after
    /// recognition, which only fills empty fields so it never clobbers a name
    /// the user already typed.
    private func apply(_ candidate: AtlasCandidate, overwrite: Bool = false) {
        self.selectedCandidateId = candidate.id
        if candidate.level == "fine" {
            self.fineLabel = candidate.label
            // Same rule as the primary branch: auto-apply only fills an empty
            // lemma so re-running recognition never clobbers a name the user
            // already typed; an explicit chip tap (overwrite) always wins.
            if overwrite || self.lemma.isEmpty { self.lemma = candidate.label }
        } else {
            self.primaryLabel = candidate.label
            if overwrite || self.lemma.isEmpty { self.lemma = candidate.label }
        }
        if overwrite || self.displayZhHant.isEmpty {
            self.displayZhHant = candidate.zhHant ?? candidate.label
        }
    }

    /// Hand the heavy tail (confirm → createCards → sync) to the background queue
    /// and close the cover immediately. The 圖鑑 page shows a "製作中" placeholder
    /// until it finishes, so the user never waits here.
    private func submit(imageId: String) {
        let payload = AtlasConfirmPayload(
            selectedCandidateId: self.selectedCandidateId,
            targetLanguage: nil,
            primaryLabel: self.primaryLabel.isEmpty ? self.lemma : self.primaryLabel,
            fineLabel: self.fineLabel.isEmpty ? nil : self.fineLabel,
            lemma: self.lemma,
            displayZhHant: self.displayZhHant,
            partOfSpeech: self.partOfSpeech.isEmpty ? nil : self.partOfSpeech,
            category: self.category.isEmpty ? nil : self.category
        )
        AtlasCaptureQueue.shared.enqueue(
            imageId: imageId,
            payload: payload,
            thumbnail: self.localThumbnail
        )
        self.dismiss()
    }

    /// Best-effort delete the just-uploaded image when the user abandons this
    /// capture (X / 換一張), so an unconfirmed photo is never kept in 自制圖鑑.
    private func discardUploadedImage() {
        guard let image = self.uploadedImage else { return }
        Task { try? await self.store.deleteImage(id: image.id) }
    }

    /// Back to the source chooser for another capture, clearing the per-photo
    /// correction state.
    private func reset() {
        self.uploadedImage = nil
        self.candidates = []
        self.selectedCandidateId = nil
        self.primaryLabel = ""
        self.fineLabel = ""
        self.lemma = ""
        self.displayZhHant = ""
        self.partOfSpeech = "noun"
        self.category = ""
        self.localThumbnail = nil
        self.candidatesByMode = [:]
        self.errorMessage = nil
        self.successMessage = nil
    }

    private func candidateLabel(_ candidate: AtlasCandidate) -> String {
        let pct = Int((candidate.confidence * 100).rounded())
        if let zh = candidate.zhHant, !zh.isEmpty {
            return "\(candidate.label) · \(zh) · \(pct)%"
        }
        return "\(candidate.label) · \(pct)%"
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
        .font(.system(size: 15, weight: .heavy))
        .foregroundStyle(.tujiInk)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s4)
        .background(.tujiYellow, in: .rect(cornerRadius: Radius.lg))
    }
}

private enum AtlasCaptureError: LocalizedError {
    case missingPhotoData

    var errorDescription: String? {
        switch self {
        case .missingPhotoData: "讀取照片失敗"
        }
    }
}

#Preview {
    AtlasCaptureView()
        .environment(AuthService.shared)
}
