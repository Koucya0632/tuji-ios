// 自制圖鑑「拍照快速新增」一鏡到底流程 (presented as a fullScreenCover from the
// 圖鑑 camera icon). Steps run top-to-bottom in one sheet:
//   1. 取得影像 — 拍照 或 從相簿選, then crop (ImageIntake)
//   2. 上傳 → 自動 AI 識別
//   3. 校正候選 / 人工修正
//   4. 確認並生成卡片 → 交給 生成佇列, sheet closes
//
// The pipeline state + rules live in AtlasCaptureVM; getting the photo in lives
// in `ImageIntake`, shared with the two 頭像 screens. This view only renders
// them and owns its prompts. Management (list/delete/review) lives separately in
// AtlasManageView — this screen is create-only.
//
// The screen keeps its own source *panel* rather than the intake's chooser
// sheet: 拍下身邊的東西, the remaining-allowance line and the capacity warning
// all live there, and a list of rows has nowhere to put them.

import NukeUI
import SwiftUI
import UIKit

struct AtlasCaptureView: View {
    @Environment(\.dismiss) private var dismiss

    /// Pipeline + form state. Replaced wholesale on 換一張 — a fresh VM *is* the
    /// reset, so there's no field-by-field clearing to keep in sync.
    @State private var vm = AtlasCaptureVM()
    /// 取得影像: source → crop → encode → deliver → park-and-retry.
    @State private var intake = ImageIntake(encoding: .capture, crop: .freeform)

    @State private var confirmDismiss = false
    @State private var confirmRetake = false
    @State private var showPrecisionInfo = false
    /// Set 3s into a recognition — see `recognizingPanel`.
    @State private var slowRecognition = false

    var body: some View {
        @Bindable var vm = self.vm
        TujiFormSheet(
            title: "拍照新增",
            closeDisabled: self.vm.busy != nil,
            onClose: {
                // Only warn when there's an in-progress capture to lose;
                // on the bare source chooser just close.
                if self.vm.uploadedImage != nil {
                    self.confirmDismiss = true
                } else {
                    self.dismiss()
                }
            }
        ) {
            TujiStepIndicator(total: 5, current: self.step)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    self.statusMessage
                    self.uploadRetry
                    if self.vm.busy == .recognize, let uploadedImage = self.vm.uploadedImage {
                        self.recognizingPanel(uploadedImage)
                    } else if let uploadedImage = self.vm.uploadedImage {
                        self.correctionPanel(uploadedImage)
                    } else {
                        self.sourcePanel
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
            }
        }
        .imageIntake(self.intake, title: "拍照新增")
        .tujiPrompt(
            isPresented: self.$confirmDismiss,
            style: .destructive,
            title: "放棄這次辨識？",
            message: "這張照片的辨識與校正結果會清除，不會生成卡片。",
            primary: TujiPromptAction("放棄", role: .destructive) {
                // Held locally because the delete outlives the screen: the task
                // must keep the VM it was started for, not whatever `@State`
                // holds by the time it runs.
                let abandoned = self.vm
                Task { await abandoned.discardUploadedImage() }
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
                // Held before the reassignment below: `@State` reads resolve
                // through the storage box at execution time, so an unheld
                // `self.vm` inside the task would find the *fresh* VM and
                // discard nothing.
                let abandoned = self.vm
                Task { await abandoned.discardUploadedImage() }
                // Fresh VM = full reset back to the source chooser.
                self.vm = AtlasCaptureVM()
            },
            secondary: TujiPromptAction("取消", role: .cancel) {}
        )
        .tujiPrompt(
            isPresented: self.$showPrecisionInfo,
            style: .confirmation,
            title: "高精度識別",
            message: "高精度識別會用更強的 AI 重新辨識，適合普通識別認錯或不確定的物件，準確度更高。",
            detail: "你隨時可以切換觀看「普通識別」「高精度識別」已識別的選項。",
            primary: TujiPromptAction("知道了", role: .cancel) {}
        )
        // Upload keeps the toast; recognition does not — it has its own panel
        // below, and a toast over a screen that is already saying "working"
        // is the app talking twice.
        .tujiStatusToast(
            isPresented: self.vm.busy == .upload,
            style: .recognizing
        )
        .task {
            AnalyticsService.shared.track(.atlasCaptureOpen)
            self.connectIntake()
            await self.vm.prepareOnOpen()
        }
        .sheet(isPresented: $vm.showPaywall) {
            PaywallView()
        }
    }

    /// Delivery for this screen is the upload itself. A rejection carries the
    /// VM's own message — the server's description of why an upload failed beats
    /// 「上傳失敗，請再試一次。」 — and parks the encoded frame so 重試 re-sends the
    /// same bytes instead of making the user pick the photo again.
    private func connectIntake() {
        let vm = self.vm
        self.intake.onDeliver { data in
            await vm.handlePicked(data: data)
            return vm.uploadedImage == nil ? .rejected(vm.errorMessage) : .accepted
        }
    }

    /// Which of D.10's five steps is on screen. 校正 and 生成 share the form —
    /// the queue step happens after this sheet closes.
    private var step: Int {
        if self.vm.busy == .upload { return 1 }
        if self.vm.busy == .recognize { return 2 }
        if self.vm.uploadedImage != nil { return 3 }
        return 0
    }

    /// AI 辨識中 (D.10). **No spinner** — a determinate-looking bar for work of
    /// unknown length is a lie, and a spinner is the platform's own idle mark.
    /// The cat only arrives after 3 seconds, which is C.11's "waiting > 3s"
    /// clause: before that the wait is short enough that a character showing up
    /// to acknowledge it would be the slower thing on screen.
    private func recognizingPanel(_ image: AtlasImageSummary) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Color.tujiPaper2
                .frame(height: 240)
                .overlay {
                    LazyImage(url: image.imageURL) { state in
                        if let image = state.image {
                            image.resizable().aspectRatio(contentMode: .fit)
                        }
                    }
                }
                .clipped()
            TujiProgressBar(progress: nil)
            Text("辨識中…")
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiInk3)
            if self.slowRecognition {
                MascotSpeechBubble(pose: .think, text: "這張比較費工，再等一下")
                    .transition(.opacity)
            }
        }
        .animation(Motion.ease(Motion.d2), value: self.slowRecognition)
        .task(id: self.vm.busy) {
            self.slowRecognition = false
            guard self.vm.busy == .recognize else { return }
            try? await Task.sleep(for: .seconds(3))
            self.slowRecognition = true
        }
    }

    // MARK: - Source chooser

    private var sourcePanel: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s2) {
                // H3, not H2: the sheet header above already carries a 34pt
                // 拍照新增, and two headings of the same size stacked twelve
                // points apart read as a mistake rather than as a hierarchy.
                Text("拍下身邊的東西")
                    .font(.tujiH3)
                    .foregroundStyle(.tujiInk)
                Text("拍照後自動 AI 辨識，校正後一鍵生成學習卡片。")
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
                // Free and Pro allowances differ (30 vs 500), so the hint names
                // the plan and its own limit instead of a shared count.
                if let remaining = self.vm.remainingPrimaryThisMonth,
                   let limit = self.vm.primaryLimitPerMonth
                {
                    if self.vm.isPro {
                        Text("Pro：本月 AI 辨識剩 \(remaining)／\(limit) 次")
                            .font(.tujiLabel)
                            .foregroundStyle(.tujiInk3)
                    } else {
                        Text("免費版：本月 AI 辨識剩 \(remaining)／\(limit) 次")
                            .font(.tujiLabel)
                            .foregroundStyle(.tujiInk3)
                    }
                }
            }

            if self.vm.atCapacity {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text(self.vm.capacityMessage)
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiAlert)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !self.vm.isPro {
                        Button {
                            self.vm.showPaywall = true
                        } label: {
                            Text("升級 Tuji Pro")
                                .font(.tujiLabel)
                                .foregroundStyle(.tujiBrandSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Space.s3)
                .background(Color.tujiAlert.opacity(0.12), in: .rect(cornerRadius: Radius.r0))
            }

            if CameraPicker.isAvailable {
                BBtn(title: "拍照", fullWidth: true, icon: "camera.fill") {
                    self.intake.pick(.camera)
                }
                .disabled(self.sourcesDisabled)
            }

            Button {
                self.intake.pick(.photoLibrary)
            } label: {
                AtlasPickerPillLabel(title: "從相簿選", icon: "photo.on.rectangle")
            }
            .buttonStyle(.plain)
            .disabled(self.sourcesDisabled)
        }
    }

    private var sourcesDisabled: Bool {
        self.vm.busy != nil || self.vm.atCapacity || self.intake.isBusy
    }

    // MARK: - Correction (recognize + manual fields + confirm)

    private func correctionPanel(_ image: AtlasImageSummary) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            self.imagePreview(image)
            self.actionRow
            self.candidateSection
            self.correctionForm
        }
    }

    private func imagePreview(_ image: AtlasImageSummary) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("校正資料")
                    .font(.tujiLabel)
                    .tracking(0.5)
                    .foregroundStyle(.tujiInk3)
                Spacer()
                TujiNavTextAction(title: "換一張", isEnabled: self.vm.busy == nil) {
                    self.confirmRetake = true
                }
            }
            // A user photograph, so no multiply — the ground is `tujiPaper2`
            // only so a portrait shot's letterboxing reads as part of the page.
            Color.tujiPaper2
                .frame(height: 240)
                .overlay {
                    LazyImage(url: image.imageURL) { state in
                        if let image = state.image {
                            image.resizable().aspectRatio(contentMode: .fit)
                        } else if state.error != nil {
                            Image(systemName: "photo")
                                .font(.tujiIcon(28, weight: .bold))
                                .foregroundStyle(.tujiInk3)
                        } else {
                            TujiProgressBar(progress: nil)
                        }
                    }
                }
                .clipped()
        }
    }

    private var actionRow: some View {
        HStack(spacing: Space.s2) {
            Button {
                Task { await self.vm.requestRecognize(.primary) }
            } label: {
                self.modeActionLabel(
                    "普通識別",
                    icon: "sparkles",
                    selected: self.vm.activeMode == .primary
                )
            }
            .buttonStyle(.plain)
            .disabled(self.vm.busy != nil)

            Button {
                // 高精度 is Pro-only — a Free user goes straight to the paywall
                // instead of spending a call that the server would 402.
                if self.vm.precisionAvailable {
                    Task { await self.vm.requestRecognize(.escalate) }
                } else {
                    self.vm.showPaywall = true
                }
            } label: {
                self.precisionActionLabel
            }
            .buttonStyle(.plain)
            .disabled(self.vm.busy != nil)

            Button {
                self.showPrecisionInfo = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.tujiIcon(18, weight: .semibold))
                    .foregroundStyle(.tujiInk3)
                    .frame(width: 32)
                    .padding(.vertical, Space.s3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("高精度識別說明")
        }
    }

    /// A recognition-mode pill with a selected (filled teal) vs unselected
    /// (outlined cream) state, so the currently active depth is obvious.
    private func modeActionLabel(
        _ title: LocalizedStringKey,
        icon: String,
        selected: Bool
    )
        -> some View
    {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.tujiLabel)
        .tracking(0.5)
        .foregroundStyle(selected ? Color.tujiPaper : .tujiInk)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(selected ? Color.tujiInk : .tujiPaper2)
    }

    /// 高精度識別. For Pro it's a selectable mode (filled when active); for Free
    /// it's a locked upsell pill whose tap opens the paywall.
    @ViewBuilder
    private var precisionActionLabel: some View {
        if self.vm.precisionAvailable {
            self.modeActionLabel(
                "高精度識別",
                icon: "scope",
                selected: self.vm.activeMode == .escalate
            )
        } else {
            HStack(spacing: 5) {
                Image(systemName: "lock.fill")
                Text("高精度識別")
            }
            .font(.tujiLabel)
            .tracking(0.5)
            .foregroundStyle(.tujiInk2)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            // Locked, not sold: a Pro-only mode gets the same ground as the
            // others plus a padlock, rather than a teal panel shouting at the
            // user from inside a form they are trying to finish.
            .background(.tujiPaper2)
        }
    }

    @ViewBuilder
    private var candidateSection: some View {
        if !self.vm.candidates.isEmpty {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("候選結果")
                    .font(.tujiLabel)
                    .tracking(0.5)
                    .foregroundStyle(.tujiInk3)
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
                                .font(.tujiBodySm)
                                .foregroundStyle(
                                    self.vm.selectedCandidateId == candidate.id
                                        ? Color.tujiPaper : .tujiInk
                                )
                                .padding(.horizontal, Space.s3)
                                .frame(height: 40)
                                .background(
                                    self.vm.selectedCandidateId == candidate.id
                                        ? Color.tujiInk : .tujiPaper2
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
        return VStack(alignment: .leading, spacing: Space.s4) {
            Text("人工校正")
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiInk3)
            self.field("圖片名稱", text: $vm.lemma, suggested: .lemma)
            if let warning = self.vm.duplicateLemmaWarning {
                Text(warning)
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk2)
            }
            // "中文名稱" localizes to Meaning/意味 for ja/en. displayZhHant
            // always rides through as the Chinese base column (prefilled from
            // the candidate) even when the field is hidden or bound to the gloss.
            switch self.vm.secondField {
            case .chineseName:
                self.field("中文名稱", text: $vm.displayZhHant, suggested: .zhHant)
            case .gloss:
                self.field("中文名稱", text: $vm.displayGloss, suggested: .gloss)
            case .hidden:
                EmptyView()
            }

            BBtn(
                title: "確認並生成卡片",
                bg: .tujiBrandPrimary,
                fg: .tujiInk,
                fullWidth: true,
                icon: "checkmark"
            ) {
                // Enqueue and close the cover immediately — the user never
                // waits here, and the queue owns the work from this point.
                self.vm.submit()
                self.dismiss()
            }
            .disabled(!self.vm.canSubmit)
        }
    }

    /// A field the model filled carries an AI 建議 mark until the user types
    /// over it (D.10). The point is not to rank the value — the model is right
    /// most of the time — but to say plainly where it came from, so correcting
    /// it feels like the expected next step rather than overruling the app.
    private func field(
        _ title: LocalizedStringKey,
        text: Binding<String>,
        suggested: AtlasCaptureVM.SuggestedField
    )
        -> some View
    {
        TujiField(
            label: title,
            badge: self.vm.isStillSuggested(suggested) ? "AI 建議" : nil
        ) {
            TujiTextField(placeholder: "", text: text)
        }
        // TujiField carries the page margin itself; the panel around this form
        // has its own, so cancel one out.
        .padding(.horizontal, -Space.s4)
    }

    /// Shown when the initial upload failed (typically weak network): re-send the
    /// frame the intake parked, without making the user re-pick the photo.
    @ViewBuilder
    private var uploadRetry: some View {
        if self.vm.uploadedImage == nil, self.intake.canRetry {
            Button {
                Task { await self.intake.retry() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("重試上傳")
                }
                .font(.tujiIcon(14, weight: .semibold))
                .foregroundStyle(.tujiInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s3)
                .background(.tujiBrandPrimary, in: .rect(cornerRadius: Radius.r0))
            }
            .buttonStyle(.plain)
            .disabled(self.vm.busy != nil)
        }
    }

    /// One error line, from two owners that cannot both be speaking: the intake
    /// only fails *before* a photo is in (selection, encode, the upload it
    /// delivers), and every VM error comes after one is. Disjoint by
    /// construction, unlike the two parallel channels `ImageIntake` was built
    /// to end.
    @ViewBuilder
    private var statusMessage: some View {
        if let errorMessage = self.vm.errorMessage ?? self.intake.errorMessage {
            Text(errorMessage)
                .font(.tujiLabel)
                .foregroundStyle(.tujiAlert)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.s3)
                .background(Color.tujiAlert.opacity(0.12), in: .rect(cornerRadius: Radius.r0))
        } else if let successMessage = self.vm.successMessage {
            Text(successMessage)
                .font(.tujiLabel)
                .foregroundStyle(.tujiAccumulation)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.s3)
                .background(Color.tujiAccumulation.opacity(0.12), in: .rect(cornerRadius: Radius.r0))
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
        .font(.tujiH3)
        .foregroundStyle(.tujiInk)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        // 瞳黃 belongs to the primary action, and 拍照 is it. The library is the
        // *other* source, not a second primary — two solid buttons in two
        // colours implied a ranking that isn't there.
        .background(.tujiPaper2)
    }
}

#Preview {
    AtlasCaptureView()
        .environment(AuthService.shared)
}
