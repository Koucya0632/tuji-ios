import SwiftUI

struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    private let repository: UserRepository = LiveUserRepository.shared
    // Stable per presentation so a retry after a network failure stays
    // idempotent server-side (request_id UNIQUE).
    @State private var requestId = UUID()
    @State private var feedbackType: FeedbackType?
    @State private var detail = ""
    @State private var submitting = false
    @State private var submitted = false
    @State private var errorMessage: String?

    private var trimmedDetail: String {
        self.detail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        self.feedbackType != nil && !self.trimmedDetail.isEmpty && !self.submitting
    }

    private var submitTitle: String {
        self.submitting
            ? tujiLocalized("提交中…")
            : tujiLocalized("提交意見")
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
            .navigationTitle("意見收集")
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
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("想告訴我們什麼呢？")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.tujiInk)

                ForEach(FeedbackType.allCases) { type in
                    Button {
                        self.feedbackType = type
                    } label: {
                        HStack(spacing: Space.s3) {
                            Image(systemName: self.feedbackType == type ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(self.feedbackType == type ? .tujiTeal : .tujiInk4)
                            Text(self.title(for: type))
                                .font(.tujiBody)
                                .foregroundStyle(.tujiInk)
                            Spacer()
                        }
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, Space.s3)
                        .background(
                            self.feedbackType == type ? Color.tujiTealSoft : Color.tujiCard,
                            in: .rect(cornerRadius: Radius.md)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md)
                                .stroke(
                                    self.feedbackType == type ? Color.tujiTeal : Color.tujiInk4.opacity(0.2),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: Space.s2) {
                Text("請詳細描述你的意見（必填）")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.tujiInk)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: self.$detail)
                        .frame(minHeight: 140)
                        .scrollContentBackground(.hidden)
                        .padding(Space.s2)
                    if self.detail.isEmpty {
                        Text("請描述你的建議或遇到的狀況…")
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

            BBtn(title: "\(self.submitTitle)", fullWidth: true) {
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
            Text("謝謝你的意見！我們會參考並持續改進。")
                .font(.system(size: 15, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.tujiInk)
            BBtn(title: "\(tujiLocalized("完成"))", fullWidth: true) { self.dismiss() }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.s6)
        .padding(.top, Space.s12)
    }

    private func title(for type: FeedbackType) -> LocalizedStringKey {
        switch type {
        case .feature: "功能建議"
        case .bug: "問題回報"
        case .content: "內容建議"
        case .other: "其他"
        }
    }

    private func submit() async {
        guard self.canSubmit, let feedbackType else { return }
        self.submitting = true
        self.errorMessage = nil
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let payload = FeedbackPayload(
            requestId: self.requestId.uuidString,
            feedbackType: feedbackType.rawValue,
            description: self.trimmedDetail,
            platform: "ios",
            appVersion: "\(version) (\(build))",
            uiLang: self.settings.current.uiLang
        )
        do {
            try await self.repository.submitFeedback(payload)
            self.submitted = true
        } catch {
            self.errorMessage = tujiLocalized("提交失敗，內容已保留，請再試一次。")
        }
        self.submitting = false
    }
}
