// 建立合集 —— 標題、簡介，以及它綁定的學習語言。
//
// 兩個入口共用這一份：圖鑑管理的「合集」分頁（建立後就地插進列表），以及作者主頁
// （建立後直接推進編輯合集——新合集還是草稿，不會出現在那個公開頁上，按了沒反應
// 就等於沒發生）。所以它只負責建立，建完做什麼由呈現它的畫面決定。

import SwiftUI

struct AtlasCollectionCreateSheet: View {
    let onCreated: (AtlasMyCollection) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model: CollectionCreateModel

    init(
        language: TargetLanguage,
        repo: CollectionManaging = LiveAtlasRepository.shared,
        onCreated: @escaping (AtlasMyCollection) -> Void
    ) {
        _model = State(initialValue: CollectionCreateModel(language: language, repo: repo))
        self.onCreated = onCreated
    }

    var body: some View {
        TujiSheetShell(title: "建立合集") {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    TujiField(label: "標題") {
                        TujiTextField(placeholder: "例如：生活日常", text: self.$model.title)
                    }
                    TujiField(
                        label: "簡介（選填）",
                        footer: "合集可直接加入這個語言中已確認完成的圖鑑；公開合集時會一起送審。"
                    ) {
                        TujiTextField(
                            placeholder: "簡單描述這個合集",
                            text: self.$model.description,
                            lineLimit: 2...4,
                            errorMessage: self.model.errorMessage
                        )
                    }
                    TujiField(label: "語言") {
                        Text(self.model.language == .ja ? "日文" : "英文")
                            .font(.tujiBody)
                            .foregroundStyle(.tujiInk2)
                    }

                    BBtn(
                        title: self.model.creating ? "建立中…" : "建立",
                        fullWidth: true
                    ) {
                        Task {
                            guard let collection = await self.model.create() else { return }
                            self.onCreated(collection)
                            self.dismiss()
                        }
                    }
                    .disabled(!self.model.canCreate)
                    .padding(.horizontal, Space.s4)
                }
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s6)
            }
        }
    }
}
