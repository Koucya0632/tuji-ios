// 作者端「我的合集」：列出自己的合集 + 建立，並在編輯頁更換公開頭像、挑選成員、送審。
//
// 成員只能來自作者自己「已通過」的公開項目（後端強制）；集合背景圖不再顯示，
// 集合頭像照片則用於列表與詳情。送審只審標題 + 簡介的文字。

import Nuke
import NukeUI
import PhotosUI
import SwiftUI
import UIKit

// MARK: - 我的合集列表

struct AtlasMyCollectionsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(CommunityFeedRefresh.self) private var feedRefresh

    @State private var vm = MyCollectionsVM()
    @State private var pendingDelete: AtlasMyCollection?
    @State private var deleteError: String?
    @State private var deleting = false

    @Binding var showCreate: Bool

    private var currentLanguage: TargetLanguage {
        self.settings.current.learningDirection.targetLanguage
    }

    private var visibleCollections: [AtlasMyCollection] {
        self.vm.collections(for: self.currentLanguage)
    }

    private var emptyTitle: String {
        switch self.currentLanguage {
        case .ja: tujiLocalized("目前沒有日文合集")
        case .en: tujiLocalized("目前沒有英文合集")
        }
    }

    var body: some View {
        let target = self.pendingDelete
        return List {
            if let deleteError {
                Text(deleteError)
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiCoral)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if self.vm.loading {
                HStack {
                    Spacer()
                    ProgressView().tint(.tujiTeal)
                    Spacer()
                }
                .padding(.top, Space.s12)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if self.visibleCollections.isEmpty {
                self.emptyState
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(self.visibleCollections) { collection in
                    NavigationLink {
                        AtlasCollectionEditView(collectionId: collection.id)
                            .onDisappear { Task { await self.vm.load() } }
                    } label: {
                        AtlasMyCollectionRow(collection: collection)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(
                        EdgeInsets(
                            top: Space.s2,
                            leading: Space.s6,
                            bottom: Space.s2,
                            trailing: Space.s6
                        )
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            self.pendingDelete = collection
                        } label: {
                            Label("刪除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(.tujiBg)
        .task { await self.vm.load() }
        .refreshable { await self.vm.load() }
        .sheet(isPresented: self.$showCreate) {
            AtlasCollectionCreateSheet(language: self.currentLanguage) { collection in
                self.vm.prepend(collection)
            }
        }
        .tujiPrompt(
            isPresented: Binding(
                get: { self.pendingDelete != nil },
                set: { if !$0 { self.pendingDelete = nil } }
            ),
            style: .destructive,
            title: "刪除這個合集？",
            message: LocalizedStringKey(target.map(self.deleteMessage) ?? ""),
            primary: TujiPromptAction("刪除", role: .destructive) {
                if let target {
                    Task { await self.delete(target) }
                }
            },
            secondary: TujiPromptAction("取消", role: .cancel) {}
        )
        .tujiStatusToast(isPresented: self.deleting, style: .deleting)
    }

    private var emptyState: some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 40))
                .foregroundStyle(.tujiInk4)
            Text(self.vm.loadError == nil
                ? self.emptyTitle
                : tujiLocalized("載入失敗，請稍後再試"))
                .font(.tujiBody)
                .foregroundStyle(.tujiInk3)
                .multilineTextAlignment(.center)
            if self.vm.loadError != nil {
                BBtn(title: "重試", fullWidth: false) { Task { await self.vm.load() } }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.s12)
        .padding(.horizontal, Space.s6)
    }

    private func deleteMessage(for collection: AtlasMyCollection) -> String {
        switch collection.review {
        case .pending, .pendingAuto, .pendingReview:
            tujiLocalized("這會取消送審並刪除合集，原始圖鑑卡片不受影響。")
        case .approved:
            tujiLocalized("這會立即將合集從公開圖鑑下架並刪除，原始圖鑑卡片不受影響。")
        default:
            tujiLocalized("這個合集會被永久刪除，原始圖鑑卡片不受影響。")
        }
    }

    private func delete(_ collection: AtlasMyCollection) async {
        guard !self.deleting else { return }
        self.deleteError = nil
        self.deleting = true
        defer { self.deleting = false }
        do {
            try await self.vm.delete(id: collection.id)
            if collection.review == .approved {
                self.feedRefresh.markNeedsReload()
            }
            self.pendingDelete = nil
        } catch {
            self.deleteError = error.localizedDescription
        }
    }
}

private struct AtlasMyCollectionRow: View {
    let collection: AtlasMyCollection

    var body: some View {
        HStack(spacing: Space.s3) {
            CollectionIdentityTile(
                collectionID: self.collection.id,
                avatarColor: self.collection.avatarColor,
                avatarImageURL: self.collection.avatarURL,
                size: 64
            )

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
    let onCreated: (AtlasMyCollection) -> Void
    private let repo: CollectionManaging

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var creating = false
    @State private var error: String?

    init(
        language: TargetLanguage,
        repo: CollectionManaging = LiveAtlasRepository.shared,
        onCreated: @escaping (AtlasMyCollection) -> Void
    ) {
        self.language = language
        self.repo = repo
        self.onCreated = onCreated
    }

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
                    Text("合集可直接加入這個語言中已確認完成的圖鑑；公開合集時會一起送審。")
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
                let collection = try await self.repo.createCollection(
                    title: trimmed,
                    description: self.description.trimmingCharacters(in: .whitespaces).isEmpty
                        ? nil : self.description,
                    targetLanguage: self.language
                )
                self.onCreated(collection)
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
    @Environment(CommunityFeedRefresh.self) private var feedRefresh
    @Environment(CollectionIdentityStore.self) private var identities

    @State private var vm: CollectionEditVM
    @State private var showConfirm = false
    @State private var showWithdrawConfirm = false
    @State private var showPicker = false
    @State private var showAvatarSources = false
    @State private var showPhotoLibrary = false
    @State private var showCamera = false
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var pendingAvatarCrop: PendingAvatarCrop?
    @State private var retryAvatarData: Data?
    @State private var avatarSelectionError: String?

    private struct PendingAvatarCrop: Identifiable {
        let id = UUID()
        let data: Data
    }

    init(collectionId: String) {
        _vm = State(initialValue: CollectionEditVM(collectionId: collectionId))
    }

    var body: some View {
        ScrollView {
            Group {
                if let collection = self.vm.collection {
                    VStack(alignment: .leading, spacing: Space.s5) {
                        self.avatarSection
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
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .onChange(of: self.avatarPickerItem) { _, item in
            guard let item else { return }
            Task {
                do {
                    if let data = try await item.loadTransferable(type: Data.self) {
                        self.avatarSelectionError = nil
                        self.pendingAvatarCrop = PendingAvatarCrop(data: data)
                    }
                } catch {
                    self.avatarSelectionError = error.localizedDescription
                }
                self.avatarPickerItem = nil
            }
        }
        .confirmationDialog(
            "更換集合頭像",
            isPresented: self.$showAvatarSources,
            titleVisibility: .visible
        ) {
            if CameraPicker.isAvailable {
                Button("拍照") { self.showCamera = true }
            }
            Button("從相簿選擇") { self.showPhotoLibrary = true }
            Button("取消", role: .cancel) {}
        }
        .photosPicker(
            isPresented: self.$showPhotoLibrary,
            selection: self.$avatarPickerItem,
            matching: .images
        )
        .fullScreenCover(isPresented: self.$showCamera) {
            CameraPicker(
                onCapture: { data in
                    self.showCamera = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        self.pendingAvatarCrop = PendingAvatarCrop(data: data)
                    }
                },
                onCancel: { self.showCamera = false }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(item: self.$pendingAvatarCrop) { pending in
            AvatarCropView(
                imageData: pending.data,
                onConfirm: { cropped in
                    self.pendingAvatarCrop = nil
                    Task {
                        let encoded = ImageDownscale.jpeg(
                            from: cropped,
                            maxPixelSize: 1600,
                            quality: 0.82
                        ) ?? cropped
                        await self.uploadAvatar(encoded)
                    }
                },
                onCancel: { self.pendingAvatarCrop = nil },
                cropFrame: .square
            )
        }
        .tujiPrompt(
            isPresented: self.$showConfirm,
            style: .confirmation,
            title: "要公開這個合集嗎？",
            message: self.vm.unpublishedMemberCount > 0
                ? "將同時送審 \(self.vm.unpublishedMemberCount) 個尚未公開的項目。"
                : "送出後會先經過審核，通過才會出現在公開圖鑑。",
            detail: "集合與所有項目全部通過後，才會一起公開。",
            // The VM owns the publish; the view decides whether the public feed
            // needs a cache-busting reload — keeping the VM free of the shared
            // refresh signal (and unit-testable).
            primary: TujiPromptAction("送出審核") {
                Task { await self.publish() }
            },
            secondary: TujiPromptAction("取消", role: .cancel) {}
        )
        .tujiPrompt(
            isPresented: self.$showWithdrawConfirm,
            style: .confirmation,
            title: "要取消公開這個合集嗎？",
            message: "合集會從公開圖鑑移除，裡面的項目仍然是公開的。",
            detail: "之後隨時可以再公開一次。",
            primary: TujiPromptAction("取消公開") {
                Task {
                    if await self.vm.withdraw() {
                        self.feedRefresh.markNeedsReload()
                    }
                }
            },
            secondary: TujiPromptAction("先不要", role: .cancel) {}
        )
    }

    private func publish() async {
        if await self.vm.submit() {
            self.feedRefresh.markNeedsReload()
        }
    }

    // MARK: Meta

    private var avatarSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("集合頭像")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.tujiInk)
            HStack(spacing: Space.s5) {
                Button {
                    self.showAvatarSources = true
                } label: {
                    VStack(spacing: Space.s2) {
                        ZStack(alignment: .bottomTrailing) {
                            LazyImage(url: self.vm.avatarPreviewURL) { state in
                                if let image = state.image {
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    RoundedRectangle(cornerRadius: Radius.md)
                                        .fill(.tujiCard)
                                        .overlay {
                                            Image(systemName: "camera.fill")
                                                .foregroundStyle(.tujiInk4)
                                        }
                                }
                            }
                            .pipeline(.shared)
                            .frame(width: 92, height: 92)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md))

                            if self.vm.uploadingAvatar {
                                ProgressView()
                                    .tint(.white)
                                    .frame(width: 30, height: 30)
                                    .background(.black.opacity(0.45), in: .circle)
                                    .padding(5)
                            }
                        }
                        Text(self.vm.avatarPreviewURL == nil ? "選擇照片" : "更換照片")
                            .font(.tujiCaption)
                            .foregroundStyle(.tujiTeal)
                    }
                }
                .buttonStyle(.plain)
                .disabled(self.vm.uploadingAvatar)

                Spacer(minLength: 0)
            }
            Text("這張照片會作為集合頭像顯示在公開列表與集合詳情。")
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk3)
            if let retryAvatarData {
                HStack(spacing: Space.s2) {
                    Text(self.vm.errorMessage ?? tujiLocalized("上傳失敗，請再試一次。"))
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiCoral)
                    Spacer(minLength: 0)
                    Button("重試上傳") {
                        Task { await self.uploadAvatar(retryAvatarData) }
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.tujiTeal)
                    .disabled(self.vm.uploadingAvatar)
                }
            } else if let avatarSelectionError {
                Text(avatarSelectionError)
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiCoral)
            }
        }
        .padding(Space.s4)
        .background(.tujiCard, in: .rect(cornerRadius: Radius.lg))
    }

    private func uploadAvatar(_ data: Data) async {
        self.retryAvatarData = data
        guard let color = await self.vm.updateAvatar(data) else { return }
        self.retryAvatarData = nil
        self.identities.publish(
            collectionID: self.vm.collectionId,
            avatarColor: color,
            avatarImageURL: self.vm.avatarPreviewURL
        )
        self.feedRefresh.markNeedsReload()
    }

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
                Text("還沒有項目。點「新增」加入你已確認完成的圖鑑。")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
            } else {
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
        VStack(spacing: 2) {
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

                if let label = item.collectionPublicationLabel {
                    Text(label)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.65), in: .capsule)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(4)
                }

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
            if collection.review.canSubmit {
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

            // Without this, publishing a 合集 is one-way: the browse feed keeps
            // it forever and the only escape is deleting the collection.
            if self.vm.canWithdraw {
                BBtn(
                    title: self.vm.withdrawing ? "收回中…" : "取消公開",
                    bg: .tujiCard,
                    fg: .tujiInk,
                    fullWidth: true,
                    icon: "arrow.uturn.backward"
                ) {
                    self.showWithdrawConfirm = true
                }
                .disabled(self.vm.withdrawing)
                .opacity(self.vm.withdrawing ? 0.6 : 1)
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
    private let repo: CollectionManaging

    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [AtlasPublicItem] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var added: Set<String> = []

    init(
        language: TargetLanguage,
        existingIds: Set<String>,
        repo: CollectionManaging = LiveAtlasRepository.shared,
        onAdd: @escaping (String) async -> Void
    ) {
        self.language = language
        self.existingIds = existingIds
        self.repo = repo
        self.onAdd = onAdd
    }

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
                            ? tujiLocalized("沒有可加入的項目。完成辨識與確認後，就能直接加入集合。")
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
                .overlay(alignment: .bottomLeading) {
                    if let label = item.collectionPublicationLabel {
                        Text(label)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.65), in: .capsule)
                            .padding(4)
                    }
                }
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
            self.candidates = try await self.repo.collectionCandidates(lang: self.language)
        } catch {
            self.loadError = error.localizedDescription
        }
        self.loading = false
    }
}
