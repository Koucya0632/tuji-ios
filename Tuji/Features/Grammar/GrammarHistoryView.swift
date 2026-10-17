import SwiftUI

struct GrammarHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: GrammarModel
    @State private var filter = GrammarModel.HistoryFilter()
    @State private var deleting: GrammarRecord?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s3) {
                    self.filters
                    Text("已生成的內容可免費重看；重新生成會再次使用點數。")
                        .font(.tujiLabel).foregroundStyle(.tujiInk2)
                    if let message = self.model.historyMessage {
                        Text(message).font(.tujiBodySm)
                        Button("重試") { Task { await self.model.loadHistory(self.filter, force: true) } }
                    }
                    if self.model.loadingHistory { ProgressView() }
                    if self.model.history.isEmpty, !self.model.loadingHistory, self.model.historyMessage == nil {
                        Text("還沒有語法紀錄。").font(.tujiBody).padding(.vertical, Space.s5)
                    }
                    ForEach(self.model.history) { record in self.row(record) }
                    if self.model.nextCursor != nil {
                        Button("載入更多") { Task { await self.model.loadHistory(self.filter, more: true) } }
                            .disabled(self.model.loadingHistory)
                    }
                }
                .padding(Space.s4)
            }
            .background(Color.tujiPaper.ignoresSafeArea())
            .navigationTitle("語法紀錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { self.dismiss() } } }
            .task(id: "\(self.model.scopeID)|\(self.filter.favorite)|\(self.filter.mode?.rawValue ?? "")") {
                await self.model.loadHistory(self.filter)
            }
            .refreshable { await self.model.loadHistory(self.filter, force: true) }
            .confirmationDialog("刪除這份語法紀錄？", isPresented: Binding(
                get: { self.deleting != nil }, set: { if !$0 { self.deleting = nil } }
            ), titleVisibility: .visible) {
                Button("刪除", role: .destructive) {
                    if let record = self.deleting { Task { await self.model.delete(record) } }
                    self.deleting = nil
                }
                Button("取消", role: .cancel) { self.deleting = nil }
            } message: { Text("刪除後無法復原，練習進度也會一併清除；重新生成會再次使用點數。") }
        }
        .tint(.tujiInk)
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Toggle("只看書籤", isOn: self.$filter.favorite).font(.tujiBody)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s2) {
                    self.chip("全部", selected: self.filter.mode == nil) { self.filter.mode = nil }
                    ForEach(GrammarMode.allCases) { mode in
                        self.chip(mode.title, selected: self.filter.mode == mode) { self.filter.mode = mode }
                    }
                }
            }
        }
    }

    private func chip(_ title: LocalizedStringKey, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.tujiBodySm(.strong))
                .padding(.horizontal, Space.s3).frame(minHeight: 44)
                .background(selected ? Color.tujiCurrent : .tujiPaper2)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func row(_ record: GrammarRecord) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Button {
                self.model.open(record)
                self.dismiss()
            } label: {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text(verbatim: record.result?.content?.title ?? record.input?.query ?? "").font(.tujiH3)
                        .lineLimit(2)
                    HStack(spacing: Space.s2) {
                        if let mode = record.input?.mode { Text(mode.title).font(.tujiLabel) }
                        // A card keeps the language it was explained in; say so when it is not this one.
                        if let code = record.input?.uiLanguage, code != self.model.uiLanguage {
                            Text(verbatim: UILanguage(code: code).nativeName)
                                .font(.tujiLabel).foregroundStyle(.tujiInk3)
                                .padding(.horizontal, Space.s1)
                                .overlay(Rectangle().stroke(Color.tujiInk3, lineWidth: 1))
                        }
                    }
                    Text(verbatim: record.result?.content?.gist ?? "").font(.tujiBodySm).lineLimit(2)
                    Text(verbatim: String(record.createdAt.prefix(10))).font(.tujiLabel).foregroundStyle(.tujiInk3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            VStack {
                Button { Task { await self.model.toggleFavorite(record) } } label: {
                    Image(systemName: record.favorite ? "bookmark.fill" : "bookmark").frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text(record.favorite ? "移除書籤" : "加入書籤"))
                Button { self.deleting = record } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                    .accessibilityLabel(Text("刪除"))
            }
        }
        .padding(Space.s3).background(.tujiPaper2)
    }
}
