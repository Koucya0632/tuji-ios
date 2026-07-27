// 作者端「我的合集」：列出自己的合集 + 建立，並在編輯頁挑選成員、選封面、送審。
//
// 成員只能來自作者自己「已通過」的公開項目（後端強制），封面用選定成員的既有公開圖，
// 送審只審標題 + 簡介的文字（lib/atlas/collection-submit-pipeline.ts）。

import Nuke
import NukeUI
import SwiftUI

// MARK: - 我的合集列表

struct AtlasMyCollectionsView: View {
    @Environment(SettingsStore.self) private var settings

    @State private var collections: [AtlasMyCollection] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var showCreate = false

    private var newCollectionLanguage: TargetLanguage {
        self.settings.current.learningDirection.targetLanguage
    }

    var body: some View {
        ScrollView {
            if self.loading {
                ProgressView().tint(.tujiTeal).padding(.top, Space.s12)
            } else if self.collections.isEmpty {
                self.emptyState
            } else {
                LazyVStack(spacing: Space.s3) {
                    ForEach(self.collections) { collection in
                        NavigationLink(value: NavRoute.atlasCollectionEdit(id: collection.id)) {
                            AtlasMyCollectionRow(collection: collection)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Space.s6)
                .padding(.vertical, Space.s4)
            }
        }
        .background(.tujiBg)
        .navigationTitle("我的合集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    self.showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await self.load() }
        .refreshable { await self.load() }
        .sheet(isPresented: self.$showCreate) {
            AtlasCollectionCreateSheet(language: self.newCollectionLanguage) {
                Task { await self.load() }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 40))
                .foregroundStyle(.tujiInk4)
            Text(self.loadError == nil
                ? tujiLocalized("還沒有合集，點右上角＋建立一個")
                : tujiLocalized("載入失敗，請稍後再試"))
                .font(.tujiBody)
                .foregroundStyle(.tujiInk3)
                .multilineTextAlignment(.center)
            if self.loadError != nil {
                BBtn(title: "重試", fullWidth: false) { Task { await self.load() } }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.s12)
        .padding(.horizontal, Space.s6)
    }

    private func load() async {
        self.loading = true
        self.loadError = nil
        do {
            self.collections = try await LiveAtlasRepository.shared.myCollections()
        } catch {
            self.loadError = error.localizedDescription
        }
        self.loading = false
    }
}

private struct AtlasMyCollectionRow: View {
    let collection: AtlasMyCollection

    var body: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Rectangle().fill(.tujiBg)
                LazyImage(url: self.collection.coverURL) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 20))
                            .foregroundStyle(.tujiInk4)
                    }
                }
                .pipeline(.shared)
            }
            .frame(width: 64, height: 64)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))

            VStack(alignment: .leading, spacing: 4) {
                Text(self.collection.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.tujiInk)
                    .lineLimit(1)
                HStack(spacing: Space.s2) {
                    Text(self.collection.review.label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.tujiTeal)
                        .padding(.horizontal, Space.s2)
                        .padding(.vertical, 2)
                        .background(.tujiTealSoft, in: .capsule)
                    Label("\(self.collection.itemCount)", systemImage: "square.stack")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tujiInk3)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.tujiInk4)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(.tujiInk4.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - 建立合集

private struct AtlasCollectionCreateSheet: View {
    let language: TargetLanguage
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var creating = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("標題") {
                    TextField("例如：生活日常", text: self.$title)
                }
                Section("簡介（選填）") {
                    TextField("簡單描述這個合集", text: self.$description, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    HStack {
                        Text("語言")
                        Spacer()
                        Text(self.language == .ja ? "日文" : "英文").foregroundStyle(.tujiInk3)
                    }
                } footer: {
                    Text("合集只能收錄你這個語言、且已通過審核的公開項目。")
                }
                if let error {
                    Text(error).foregroundStyle(.tujiCoral)
                }
            }
            .navigationTitle("建立合集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { self.dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(self.creating ? "建立中…" : "建立") { self.create() }
                        .disabled(self.creating || self.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func create() {
        let trimmed = self.title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !self.creating else { return }
        self.creating = true
        self.error = nil
        Task {
            do {
                _ = try await LiveAtlasRepository.shared.createCollection(
                    title: trimmed,
                    description: self.description.trimmingCharacters(in: .whitespaces).isEmpty
                        ? nil : self.description,
                    targetLanguage: self.language
                )
                self.onCreated()
                self.dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            self.creating = false
        }
    }
}

// MARK: - 編輯合集

struct AtlasCollectionEditView: View {
    @State private var vm: CollectionEditVM
    @State private var showConfirm = false
    @State private var showPicker = false

    init(collectionId: String) {
        _vm = State(initialValue: CollectionEditVM(collectionId: collectionId))
    }

    var body: some View {
        ScrollView {
            if let collection = self.vm.collection {
                VStack(alignment: .leading, spacing: Space.s5) {
                    self.metaSection
                    self.membersSection
                    self.submitSection(collection)
                }
                .padding(Space.s6)
            } else if case .loading = self.vm.phase {
                ProgressView().tint(.tujiTeal).padding(.top, Space.s12)
            } else {
                self.errorState
            }
        }
        .background(.tujiBg)
        .navigationTitle(self.vm.collection?.title ?? tujiLocalized("編輯合集"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await self.vm.load() }
        .sheet(isPresented: self.$showPicker) {
            AtlasCollectionItemPicker(
                language: self.vm.language,
                existingIds: Set(self.vm.members.map(\.id))
            ) { publicItemId in
                await self.vm.addMember(publicItemId)
            }
        }
        .tujiPrompt(
            isPresented: self.$showConfirm,
            style: .confirmation,
            title: "要公開這個合集嗎？",
            message: "送出後會先經過審核，通過才會出現在公開圖鑑。",
            detail: "公開後其他人可以看到合集裡的所有項目。",
            // The VM owns the publish; the view decides whether the public feed
            // needs a cache-busting reload — keeping the VM free of the global
            // refresh center (and unit-testable).
            primary: TujiPromptAction("送出審核") {
                Task {
                    if await self.vm.submit() {
                        AtlasFeedRefreshCenter.shared.markNeedsForceReload()
                    }
                }
            },
            secondary: TujiPromptAction("取消", role: .cancel) {}
        )
    }

    // MARK: Meta

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("標題").font(.tujiCaption).foregroundStyle(.tujiInk3)
            TextField("標題", text: self.$vm.title)
                .textFieldStyle(.roundedBorder)
            Text("簡介").font(.tujiCaption).foregroundStyle(.tujiInk3).padding(.top, Space.s2)
            TextField("簡介（選填）", text: self.$vm.description, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
            HStack {
                if self.vm.metaSaved {
                    Text("已儲存").font(.tujiCaption).foregroundStyle(.tujiInk3)
                }
                Spacer()
                BBtn(title: self.vm.savingMeta ? "儲存中…" : "儲存", fullWidth: false) {
                    Task { await self.vm.saveMeta() }
                }
                .disabled(!self.vm.canSaveMeta)
            }
            .padding(.top, Space.s1)
        }
    }

    // MARK: Members

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("項目 \(self.vm.members.count)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.tujiInk)
                Spacer()
                Button {
                    self.showPicker = true
                } label: {
                    Label("新增", systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tujiTeal)
                }
                .buttonStyle(.plain)
            }
            if self.vm.members.isEmpty {
                Text("還沒有項目。點「新增」把你已通過的公開項目加進來。")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
            } else {
                Text("點縮圖設為封面")
                    .font(.system(size: 11))
                    .foregroundStyle(.tujiInk4)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Space.s3), count: 3),
                    spacing: Space.s3
                ) {
                    ForEach(self.vm.members) { item in
                        self.memberCell(item)
                    }
                }
            }
        }
    }

    private func memberCell(_ item: AtlasPublicItem) -> some View {
        let isCover = self.vm.coverId == item.id
        return VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Rectangle().fill(.tujiBg)
                    LazyImage(url: item.imageURL) { state in
                        if let image = state.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "photo").foregroundStyle(.tujiInk4)
                        }
                    }
                    .pipeline(.shared)
                }
                .frame(height: 84)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(isCover ? Color.tujiTeal : .clear, lineWidth: 2)
                )
                .contentShape(Rectangle())
                .onTapGesture { Task { await self.vm.setCover(item.id) } }

                Button {
                    Task { await self.vm.removeMember(item.id) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white, .black.opacity(0.5))
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
            .overlay(alignment: .bottomLeading) {
                if isCover {
                    Text("封面")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.tujiTeal, in: .capsule)
                        .padding(4)
                }
            }
            Text(item.lemma)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tujiInk2)
                .lineLimit(1)
        }
    }

    // MARK: Submit

    private func submitSection(_ collection: AtlasCollectionEdit) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("公開狀態").font(.tujiCaption).foregroundStyle(.tujiInk3)
                Spacer()
                Text(collection.review.label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.tujiInk)
            }
            if let errorMessage = self.vm.errorMessage {
                Text(errorMessage).font(.tujiCaption).foregroundStyle(.tujiCoral)
            }
            if case let .done(moderation) = self.vm.submitState {
                Text(moderation?.published == true
                    ? tujiLocalized("已通過審核，合集現在出現在公開圖鑑了。")
                    : tujiLocalized("已送出，審核通過後就會出現在公開圖鑑。"))
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
            }
            BBtn(
                title: self.vm.isSubmitting ? "送出中…" : "公開合集",
                bg: .tujiTeal,
                fg: .white,
                fullWidth: true,
                icon: "square.and.arrow.up"
            ) {
                self.showConfirm = true
            }
            .disabled(!self.vm.canSubmit)
            .opacity(self.vm.canSubmit ? 1 : 0.6)
            if self.vm.members.isEmpty {
                Text("合集至少要有一個項目才能公開。")
                    .font(.system(size: 11))
                    .foregroundStyle(.tujiInk4)
            }
        }
        .padding(.top, Space.s2)
    }

    private var errorState: some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.tujiInk4)
            Text(tujiLocalized("載入失敗，請稍後再試"))
                .font(.tujiBody)
                .foregroundStyle(.tujiInk3)
            BBtn(title: "重試", fullWidth: false) { Task { await self.vm.load() } }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.s12)
    }
}

// MARK: - 成員挑選

private struct AtlasCollectionItemPicker: View {
    let language: TargetLanguage
    let existingIds: Set<String>
    let onAdd: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [AtlasPublicItem] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var added: Set<String> = []

    private var available: [AtlasPublicItem] {
        self.candidates.filter { !self.existingIds.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if self.loading {
                    ProgressView().tint(.tujiTeal).padding(.top, Space.s12)
                } else if self.available.isEmpty {
                    VStack(spacing: Space.s3) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 36)).foregroundStyle(.tujiInk4)
                        Text(self.loadError == nil
                            ? tujiLocalized("沒有可加入的項目。先把你的圖鑑公開並通過審核。")
                            : tujiLocalized("載入失敗，請稍後再試"))
                            .font(.tujiCaption)
                            .foregroundStyle(.tujiInk3)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Space.s12)
                    .padding(.horizontal, Space.s6)
                } else {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: Space.s3), count: 3),
                        spacing: Space.s3
                    ) {
                        ForEach(self.available) { item in
                            self.cell(item)
                        }
                    }
                    .padding(Space.s4)
                }
            }
            .background(.tujiBg)
            .navigationTitle("加入項目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { self.dismiss() }
                }
            }
            .task { await self.load() }
        }
    }

    private func cell(_ item: AtlasPublicItem) -> some View {
        let isAdded = self.added.contains(item.id)
        return Button {
            guard !isAdded else { return }
            self.added.insert(item.id)
            Task { await self.onAdd(item.id) }
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Rectangle().fill(.tujiBg)
                    LazyImage(url: item.imageURL) { state in
                        if let image = state.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "photo").foregroundStyle(.tujiInk4)
                        }
                    }
                    .pipeline(.shared)
                }
                .frame(height: 84)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(isAdded ? .white : .white, isAdded ? .tujiTeal : .black.opacity(0.5))
                        .padding(4)
                }
                Text(item.lemma)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tujiInk2)
                    .lineLimit(1)
            }
            .opacity(isAdded ? 0.6 : 1)
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        self.loading = true
        self.loadError = nil
        do {
            self.candidates = try await LiveAtlasRepository.shared.collectionCandidates(lang: self.language)
        } catch {
            self.loadError = error.localizedDescription
        }
        self.loading = false
    }
}
