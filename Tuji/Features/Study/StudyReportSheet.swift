import SwiftUI

struct StudyReportSheet: View {
    let draft: StudyReportDraft

    @Environment(\.dismiss) private var dismiss
    @State private var issueType: StudyReportIssueType?
    @State private var detail = ""
    @State private var submitting = false
    @State private var submitted = false
    @State private var errorMessage: String?

    private var trimmedDetail: String {
        self.detail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        self.issueType != nil && !self.trimmedDetail.isEmpty && !self.submitting
    }

    private var submitTitle: String {
        self.submitting
            ? self.localized("提交中…")
            : self.localized("提交報錯")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if self.submitted {
                    self.successContent
                } else {
                    self.formContent
                }
            }
            .background(.tujiBg)
            .navigationTitle("回報學習問題")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { self.dismiss() }
                        .disabled(self.submitting)
                }
            }
        }
        .interactiveDismissDisabled(self.submitting)
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            Text(self.draft.item.word.word)
                .font(.tujiH2)
                .foregroundStyle(.tujiInk)

            VStack(alignment: .leading, spacing: Space.s3) {
                Text("當前學習遇到什麼問題呢？")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.tujiInk)

                ForEach(StudyReportIssueType.allCases) { type in
                    Button {
                        self.issueType = type
                    } label: {
                        HStack(spacing: Space.s3) {
                            Image(systemName: self.issueType == type ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(self.issueType == type ? .tujiTeal : .tujiInk4)
                            Text(self.title(for: type))
                                .font(.tujiBody)
                                .foregroundStyle(.tujiInk)
                            Spacer()
                        }
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, Space.s3)
                        .background(
                            self.issueType == type ? Color.tujiTealSoft : Color.tujiCard,
                            in: .rect(cornerRadius: Radius.md)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md)
                                .stroke(
                                    self.issueType == type ? Color.tujiTeal : Color.tujiInk4.opacity(0.2),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: Space.s2) {
                Text("請詳細說說哪裡需要改進呢？（必填）")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.tujiInk)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: self.$detail)
                        .frame(minHeight: 140)
                        .scrollContentBackground(.hidden)
                        .padding(Space.s2)
                    if self.detail.isEmpty {
                        Text("請描述你看到的問題與正確內容…")
                            .font(.tujiBody)
                            .foregroundStyle(.tujiInk4)
                            .padding(.horizontal, Space.s4)
                            .padding(.vertical, Space.s3)
                            .allowsHitTesting(false)
                    }
                }
                .background(.tujiCard, in: .rect(cornerRadius: Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(.tujiInk4.opacity(0.25), lineWidth: 1)
                )
                .onChange(of: self.detail) { _, value in
                    if value.count > 1000 {
                        self.detail = String(value.prefix(1000))
                    }
                }

                Text("\(self.detail.count)/1000")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiCoral)
            }

            BBtn(title: self.submitTitle, fullWidth: true) {
                Task { await self.submit() }
            }
            .disabled(!self.canSubmit)
        }
        .padding(.horizontal, Space.s6)
        .padding(.vertical, Space.s6)
    }

    private var successContent: some View {
        VStack(spacing: Space.s5) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tujiGreen)
            Text("謝謝你的回報！我們會盡快確認並改進。")
                .font(.system(size: 15, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.tujiInk)
            BBtn(title: self.localized("完成"), fullWidth: true) { self.dismiss() }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.s6)
        .padding(.top, Space.s12)
    }

    private func title(for type: StudyReportIssueType) -> LocalizedStringKey {
        switch type {
        case .image: "圖片不正確或不清楚"
        case .content: "單字、翻譯或解釋有誤"
        case .audio: "發音或音訊有問題"
        case .answer: "題目或答案有誤"
        case .ui: "頁面顯示或操作異常"
        case .other: "其他問題"
        }
    }

    private func submit() async {
        guard self.canSubmit, let issueType else { return }
        self.submitting = true
        self.errorMessage = nil
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let payload = StudyReportPayload(
            requestId: self.draft.id.uuidString,
            wordId: self.draft.item.word.id,
            cardId: self.draft.item.card.id,
            issueType: issueType.rawValue,
            description: self.trimmedDetail,
            mode: self.draft.mode,
            phase: self.draft.phase,
            selectedAnswer: self.draft.selectedAnswer,
            platform: "ios",
            appVersion: "\(version) (\(build))",
            uiLang: self.draft.uiLang,
            snapshot: self.draft.snapshot
        )
        do {
            let _: Empty = try await APIClient.shared.post(.studyReports, body: payload)
            self.submitted = true
        } catch {
            self.errorMessage = self.localized("提交失敗，內容已保留，請再試一次。")
        }
        self.submitting = false
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: Locale(identifier: self.draft.uiLang))
    }
}
