import SwiftUI

struct VocabularyHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: VocabularyModel
    @State private var favorites = false
    @State private var deleting: VocabularyRecord?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s3) {
                    Toggle("只看收藏", isOn: self.$favorites).font(.tujiBody)
                    Text("已生成的內容可免費重看；重新生成會再次使用點數。")
                        .font(.tujiLabel).foregroundStyle(.tujiInk2)
                    if let message = self.model.historyMessage {
                        Text(message).font(.tujiBodySm)
                        Button("重試") { Task { await self.model.loadHistory(favorite: self.favorites) } }
                    }
                    if self.model.loadingHistory { ProgressView() }
                    if self.model.history.isEmpty, !self.model.loadingHistory, self.model.historyMessage == nil {
                        Text("還沒有查詞紀錄。").font(.tujiBody).padding(.vertical, Space.s5)
                    }
                    ForEach(self.model.history) { record in self.row(record) }
                    if self.model.nextCursor != nil {
                        Button("載入更多") { Task { await self.model.loadHistory(favorite: self.favorites, more: true) } }
                            .disabled(self.model.loadingHistory)
                    }
                }
                .padding(Space.s4)
            }
            .background(Color.tujiPaper.ignoresSafeArea())
            .navigationTitle("查詞紀錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { self.dismiss() } } }
            .task(id: "\(self.model.scopeID)|\(self.favorites)") {
                await self.model.loadHistory(favorite: self.favorites)
            }
            .refreshable { await self.model.loadHistory(favorite: self.favorites) }
            .confirmationDialog("刪除這份查詞紀錄？", isPresented: Binding(
                get: { self.deleting != nil }, set: { if !$0 { self.deleting = nil } }
            ), titleVisibility: .visible) {
                Button("刪除", role: .destructive) {
                    if let record = self.deleting { Task { await self.model.delete(record) } }
                    self.deleting = nil
                }
                Button("取消", role: .cancel) { self.deleting = nil }
            } message: { Text("刪除後無法復原；重新生成會再次使用點數。") }
        }
        .tint(.tujiInk)
    }

    private func row(_ record: VocabularyRecord) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Button {
                self.model.open(record)
                self.dismiss()
            } label: {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text(verbatim: record.result?.content?.headword.text ?? record.input?.query ?? "").font(.tujiH3)
                    Text(record.input?.mode.title ?? "").font(.tujiLabel)
                    Text(verbatim: record.result?.content?.headword.meaning ?? "").font(.tujiBodySm)
                    Text(verbatim: String(record.createdAt.prefix(10))).font(.tujiLabel).foregroundStyle(.tujiInk3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            VStack {
                Button { Task { await self.model.toggleFavorite(record) } } label: {
                    Image(systemName: record.favorite ? "star.fill" : "star").frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text(record.favorite ? "取消收藏" : "收藏"))
                Button { self.deleting = record } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                    .accessibilityLabel(Text("刪除"))
            }
        }
        .padding(Space.s3).background(.tujiPaper2)
    }
}
