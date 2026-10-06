// 點數版「拍照新增」. Steps run top-to-bottom in one sheet:
//   1. 選辨識方式（普通／高精度，價格寫在選項上）
//   2. 拍照或從相簿選 → 裁切；照片留在手機上
//   3. 開始識別 — 上傳、報價、扣點一次做完
//   4. 候選結果（與舊版同一套樣式）；普通識別後可補差價升級高精度
//   5. 確認並生成卡片 → sheet closes
//
// State and money rules live in CreditCaptureModel; this view only renders them.

import NukeUI
import SwiftUI
import UIKit

struct CreditCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.targetLanguage) private var language
    @State private var model = CreditCaptureModel()
    @State private var intake = ImageIntake(encoding: .capture, crop: .freeform)
    @State private var showWallet = false
    @State private var showPrecisionInfo = false
    @State private var slowRecognition = false
    private var glossLanguage: String? {
        let ui = SettingsStore.shared.uiLang
        return ["en", "ja"].contains(ui) && ui != self.language.rawValue ? ui : nil
    }

    var body: some View {
        TujiFormSheet(title: "拍照新增", closeDisabled: self.model.busy, onClose: { self.dismiss() }) {
            TujiStepIndicator(total: 5, current: self.step)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    self.walletRow
                    self.statusMessage
                    if self.model.pending != nil {
                        self.pendingPanel
                    } else if let quote = self.model.quote {
                        self.quotePanel(quote)
                    } else if let operation = self.model.operation {
                        self.operationPanel(operation)
                    } else if self.model.photo != nil {
                        self.readyPanel
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
            isPresented: self.$showPrecisionInfo,
            style: .confirmation,
            title: "高精度識別",
            message: "高精度識別會用更強的 AI 重新辨識，適合普通識別認錯或不確定的物件，準確度更高。",
            detail: "普通識別後覺得不準，可以補差價升級成高精度，不用重拍。",
            primary: TujiPromptAction("知道了", role: .cancel) {}
        )
        .sheet(isPresented: self.$showWallet) { PaywallView() }
        .task {
            AnalyticsService.shared.track(.atlasCaptureOpen)
            // The photo stays on the phone until 開始識別.
            self.intake.onDeliver { data in
                self.model.setPhoto(data)
                return .accepted
            }
            await self.model.load()
        }
        .task(id: "\(self.model.operation?.id ?? ""):\(self.model.operation?.state ?? "")") {
            while self.model.operation?.isRunning == true, !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                await self.model.poll()
            }
        }
    }

    private var step: Int {
        if self.model.operation?.state == "committed" { return 3 }
        if self.model.operation?.isRunning == true { return 2 }
        if self.model.photo != nil { return 1 }
        return 0
    }

    // MARK: - Wallet

    private var walletRow: some View {
        Button { self.showWallet = true } label: {
            HStack(spacing: Space.s2) {
                Image("CreditCan").resizable().scaledToFit().frame(width: 28, height: 28)
                Text("罐頭點數").font(.tujiLabel).tracking(0.5).foregroundStyle(.tujiInk3)
                Spacer()
                Text(self.model.wallet.map { String($0.available) } ?? "—")
                    .font(.tujiH3).foregroundStyle(.tujiInk)
                Image(systemName: "chevron.right").font(.tujiIcon(12, weight: .semibold)).foregroundStyle(.tujiInk3)
            }
            .padding(.horizontal, Space.s3)
            .frame(height: 48)
            .background(.tujiPaper2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 1–2. Mode + source

    private var sourcePanel: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("選擇辨識方式").font(.tujiH3).foregroundStyle(.tujiInk)
                Spacer()
                Button { self.showPrecisionInfo = true } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.tujiIcon(18, weight: .semibold))
                        .foregroundStyle(.tujiInk3)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("高精度識別說明")
            }
            VStack(spacing: Space.s2) {
                self.modeRadio(.primary, title: "普通識別", points: self.model.recognitionPrice)
                self.modeRadio(.precision, title: "高精度識別", points: self.model.precisionPrice)
            }
            Text("照片會在按下「開始識別」後才上傳。")
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)

            if CameraPicker.isAvailable {
                BBtn(title: "拍照", fullWidth: true, icon: "camera.fill") {
                    self.intake.pick(.camera)
                }
                .disabled(self.sourcesDisabled)
            }
            Button {
                self.intake.pick(.photoLibrary)
            } label: {
                HStack {
                    Image(systemName: "photo.on.rectangle")
                    Text("從相簿選")
                }
                .font(.tujiH3)
                .foregroundStyle(.tujiInk)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(.tujiPaper2)
            }
            .buttonStyle(.plain)
            .disabled(self.sourcesDisabled)
        }
    }

    private var sourcesDisabled: Bool {
        self.model.busy || self.intake.isBusy || !self.model.operationsEnabled
    }

    private func modeRadio(_ mode: CreditCaptureModel.Mode, title: LocalizedStringKey, points: Int?) -> some View {
        let selected = self.model.mode == mode
        return Button { self.model.mode = mode } label: {
            HStack(spacing: Space.s3) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.tujiIcon(20, weight: .regular))
                    .foregroundStyle(selected ? Color.tujiInk : .tujiInk3)
                Text(title).font(.tujiBody).foregroundStyle(.tujiInk)
                Spacer()
                self.price(points)
            }
            .padding(.horizontal, Space.s3)
            .frame(height: 56)
            .background(.tujiPaper2)
            .overlay { Rectangle().stroke(selected ? Color.tujiInk : .clear, lineWidth: 1.5) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 罐頭 ×N. `plus` marks a top-up rather than a full price.
    private func price(_ points: Int?, plus: Bool = false) -> some View {
        HStack(spacing: 2) {
            if plus { Text(verbatim: "+") }
            Image("CreditCan").resizable().scaledToFit().frame(width: 20, height: 20)
            Text(verbatim: "×\(points.map(String.init) ?? "—")")
        }
        .font(.tujiLabel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(format: tujiLocalized("辨識費用：%d 點"), points ?? 0)))
    }

    // MARK: - 3. Ready to start

    private var readyPanel: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text(self.model.mode == .primary ? "普通識別" : "高精度識別")
                    .font(.tujiLabel).tracking(0.5).foregroundStyle(.tujiInk3)
                Spacer()
                TujiNavTextAction(title: "換一張", isEnabled: !self.model.busy) { self.model.reset() }
            }
            self.photoFrame
            if self.model.busy {
                TujiProgressBar(progress: nil)
                Text("辨識中…").font(.tujiLabel).tracking(0.5).foregroundStyle(.tujiInk3)
            } else if self.model.affordable(self.model.price) {
                Button {
                    Task { await self.model.start(language: self.language, glossLanguage: self.glossLanguage) }
                } label: {
                    HStack(spacing: Space.s2) {
                        Image(systemName: "sparkles")
                        Text("開始識別")
                        Spacer().frame(width: Space.s2)
                        self.price(self.model.price)
                    }
                    .font(.tujiH3)
                    .foregroundStyle(.tujiInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(.tujiBrandPrimary)
                }
                .buttonStyle(.plain)
                .disabled(!self.model.operationsEnabled)
            } else {
                self.topUp
            }
        }
    }

    private var topUp: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("點數不足").font(.tujiLabel).foregroundStyle(.tujiAlert)
            BBtn(title: "補充點數", fullWidth: true) { self.showWallet = true }
        }
    }

    /// The photo on screen: the local crop while this session has it, else the upload.
    private var photoFrame: some View {
        Color.tujiPaper2
            .frame(height: 240)
            .overlay {
                if let data = self.model.photo, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                } else if let url = self.model.image?.imageURL {
                    LazyImage(url: url) { state in
                        if let image = state.image { image.resizable().aspectRatio(contentMode: .fit) }
                    }
                } else {
                    Image(systemName: "photo").font(.tujiIcon(28, weight: .bold)).foregroundStyle(.tujiInk3)
                }
            }
            .clipped()
    }

    // MARK: - 4. Recognition + results

    @ViewBuilder
    private func operationPanel(_ operation: CreditOperation) -> some View {
        if operation.isRunning {
            self.recognizingPanel(operation)
        } else if operation.state == "released" {
            VStack(alignment: .leading, spacing: Space.s3) {
                self.photoFrame
                Text("辨識沒有完成，點數未扣除。").font(.tujiBody).foregroundStyle(.tujiInk)
                BBtn(title: "換一張", fullWidth: true) { self.model.reset() }
            }
        } else if operation.confirmedItemId != nil {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("卡片已保存，但同步失敗。").font(.tujiBody).foregroundStyle(.tujiInk)
                BBtn(title: "同步複習卡片", fullWidth: true) {
                    Task { if await self.model.syncCards() { self.dismiss() } }
                }
                .disabled(self.model.busy)
            }
        } else {
            self.resultPanel(operation)
        }
    }

    /// AI 辨識中 — same panel as the free flow: no spinner, the cat after 3s.
    private func recognizingPanel(_ operation: CreditOperation) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            self.photoFrame
            TujiProgressBar(progress: nil)
            Text("辨識中…").font(.tujiLabel).tracking(0.5).foregroundStyle(.tujiInk3)
            if self.slowRecognition {
                MascotSpeechBubble(pose: .think, text: "這張比較費工，再等一下")
                    .transition(.opacity)
            }
            if operation.state == "reserved" {
                TujiNavTextAction(title: "取消", isEnabled: !self.model.busy) {
                    Task { await self.model.cancelOperation() }
                }
            }
        }
        .animation(Motion.ease(Motion.d2), value: self.slowRecognition)
        .task(id: operation.id) {
            self.slowRecognition = false
            try? await Task.sleep(for: .seconds(3))
            self.slowRecognition = true
        }
    }

    private func resultPanel(_ operation: CreditOperation) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("候選結果").font(.tujiLabel).tracking(0.5).foregroundStyle(.tujiInk3)
                Spacer()
                TujiNavTextAction(title: "換一張", isEnabled: !self.model.busy) { self.model.reset() }
            }
            self.photoFrame
            self.modeRow
            self.candidates(operation)
            if self.model.selectedCandidateId != nil {
                self.correctionForm
            }
            BBtn(title: "確認並生成卡片", bg: .tujiBrandPrimary, fg: .tujiInk, fullWidth: true, icon: "checkmark") {
                Task { if await self.model.confirm() { self.dismiss() } }
            }
            .disabled(!self.model.canConfirm)
        }
    }

    /// 人工校正 — the free flow's two names, prefilled from the chosen candidate.
    private var correctionForm: some View {
        @Bindable var model = self.model
        return VStack(alignment: .leading, spacing: Space.s4) {
            Text("人工校正")
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiInk3)
            self.field("圖片名稱", text: $model.lemma, suggested: .lemma)
            if let warning = self.model.duplicateLemmaWarning {
                Text(warning)
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk2)
            }
            switch self.model.secondField {
            case .chineseName:
                self.field("中文名稱", text: $model.displayZhHant, suggested: .zhHant)
            case .gloss:
                self.field("中文名稱", text: $model.displayGloss, suggested: .gloss)
            case .hidden:
                EmptyView()
            }
        }
    }

    private func field(
        _ title: LocalizedStringKey,
        text: Binding<String>,
        suggested: AtlasCaptureVM.SuggestedField
    )
        -> some View
    {
        TujiField(label: title, badge: self.model.isStillSuggested(suggested) ? "AI 建議" : nil) {
            TujiTextField(placeholder: "", text: text)
        }
        // TujiField carries the page margin itself; this panel has its own.
        .padding(.horizontal, -Space.s4)
    }

    /// 普通／高精度. A run already paid for is a switch; 高精度 not yet run is the top-up.
    private var modeRow: some View {
        HStack(spacing: Space.s2) {
            Button { self.model.show(.primary) } label: {
                self.modeLabel("普通識別", icon: "sparkles", selected: self.model.shownMode == .primary)
            }
            .buttonStyle(.plain)
            .disabled(self.model.busy || self.model.run(.primary) == nil)

            if self.model.run(.precision) != nil || !self.model.canUpgrade {
                Button { self.model.show(.precision) } label: {
                    self.modeLabel("高精度識別", icon: "scope", selected: self.model.shownMode == .precision)
                }
                .buttonStyle(.plain)
                .disabled(self.model.busy || self.model.run(.precision) == nil)
            } else {
                Button {
                    if self.model.affordable(self.model.upgradePrice) {
                        Task { await self.model.upgrade(language: self.language, glossLanguage: self.glossLanguage) }
                    } else {
                        self.showWallet = true
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "scope")
                        Text("升級高精度")
                        self.price(self.model.upgradePrice, plus: true)
                    }
                    .font(.tujiLabel)
                    .tracking(0.5)
                    .foregroundStyle(.tujiInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .overlay { Rectangle().stroke(Color.tujiInk, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .disabled(self.model.busy || !self.model.operationsEnabled)
            }
        }
    }

    private func modeLabel(_ title: LocalizedStringKey, icon: String, selected: Bool) -> some View {
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

    private func candidates(_ operation: CreditOperation) -> some View {
        let all = operation.result?.candidates ?? []
        return VStack(alignment: .leading, spacing: Space.s2) {
            self.candidateGroup(all.filter { $0.level != "fine" })
            self.candidateGroup(all.filter { $0.level == "fine" })
        }
    }

    @ViewBuilder
    private func candidateGroup(_ rows: [CreditCandidate]) -> some View {
        if !rows.isEmpty {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120), spacing: Space.s2)],
                alignment: .leading,
                spacing: Space.s2
            ) {
                ForEach(rows) { candidate in
                    let selected = self.model.selectedCandidateId == candidate.id
                    Button { self.model.select(candidate) } label: {
                        VStack(spacing: 2) {
                            Text(candidate.label).font(.tujiBodySm)
                            Text(candidate.gloss ?? candidate.zhHant).font(.tujiLabel).opacity(0.7)
                        }
                        .foregroundStyle(selected ? Color.tujiPaper : .tujiInk)
                        .padding(.horizontal, Space.s3)
                        .padding(.vertical, Space.s2)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(selected ? Color.tujiInk : .tujiPaper2)
                    }
                    .buttonStyle(.plain)
                    .disabled(self.model.busy)
                }
            }
        }
    }

    // MARK: - Exceptions

    /// The server priced differently from the screen (price change mid-session): ask, don't charge.
    private func quotePanel(_ quote: CreditQuote) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(String(format: tujiLocalized("辨識費用：%d 點"), quote.points)).font(.tujiH3)
            BBtn(title: "確認使用點數", fullWidth: true) { Task { await self.model.accept() } }
                .disabled(self.model.busy || !self.model.affordable(quote.points))
            TujiNavTextAction(title: "取消", isEnabled: !self.model.busy) { self.model.cancelQuote() }
        }
    }

    private var pendingPanel: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("上次的扣點確認尚未同步，請重試同一筆操作。").font(.tujiBody)
            BBtn(title: "重試同步", fullWidth: true) { Task { await self.model.accept() } }
                .disabled(self.model.busy)
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        if let message = self.model.message ?? self.intake.errorMessage {
            Text(message)
                .font(.tujiLabel)
                .foregroundStyle(.tujiAlert)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.s3)
                .background(Color.tujiAlert.opacity(0.12), in: .rect(cornerRadius: Radius.r0))
        } else if self.model.catalog != nil, !self.model.operationsEnabled {
            Text("AI 辨識暫時無法使用，請稍後再試。")
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
        }
    }
}
