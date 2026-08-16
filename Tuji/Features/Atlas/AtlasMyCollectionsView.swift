// 作者端「我的合集」：列出自己的合集 + 建立，並在編輯頁更換公開頭像、挑選成員、送審。
//
// 成員只能來自作者自己「已通過」的公開項目（後端強制）；合集背景圖不再顯示，
// 合集頭像照片則用於列表與詳情。送審只審標題 + 簡介的文字。

import Nuke
import NukeUI
import SwiftUI

// MARK: - 我的合集列表

struct AtlasMyCollectionsView: View {
    @Environment(\.targetLanguage) private var currentLanguage
    @Environment(CommunityFeedRefresh.self) private var feedRefresh

    @State private var vm = MyCollectionsVM()
    @State private var pendingDelete: AtlasMyCollection?
    @State private var deleteError: String?
    @State private var deleting = false

    @Binding var showCreate: Bool

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
        return ScrollView {
            VStack(spacing: 0) {
                if let deleteError {
                    Text(deleteError)
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiAlert)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, Space.s3)
                }
                if self.vm.showsPlaceholder {
                    TujiSkeletonRows(count: 3, height: 88)
                        .padding(.top, Space.s3)
                } else if self.visibleCollections.isEmpty {
                    self.emptyState
                        .padding(.top, Space.s5)
                } else {
                    ForEach(Array(self.visibleCollections.enumerated()), id: \.element.id) { index, collection in
                        if index > 0 {
                            Rectangle()
                                .fill(.tujiRule)
                                .frame(height: Border.bw1)
                                .padding(.horizontal, Space.s4)
                        }
                        TujiSwipeRow(
                            actionLabel: "刪除",
                            systemImage: "trash",
                            action: { self.pendingDelete = collection }
                        ) {
                            NavigationLink {
                                // Kept even though `.task` re-runs on pop: that is
                                // SwiftUI's teardown behaviour, not a contract. The VM
                                // coalesces whichever of the two arrives second.
                                AtlasCollectionEditView(collectionId: collection.id)
                                    .onDisappear { Task { await self.vm.load() } }
                            } label: {
                                AtlasMyCollectionRow(collection: collection)
                                    .padding(.horizontal, Space.s4)
                                    .padding(.vertical, Space.s3)
                            }
                            .tujiRowStyle()
                        }
                    }
                }
            }
            .padding(.bottom, Space.s6)
        }
        .background(.tujiPaper)
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
                .font(.tujiIcon(40))
                .foregroundStyle(.tujiInk3)
            Text(self.vm.loadError == nil
                ? self.emptyTitle
                : tujiLocalized("載入失敗，請稍後再試"))
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk3)
                .multilineTextAlignment(.center)
            if self.vm.loadError != nil {
                BBtn(title: "重試", fullWidth: false) { Task { await self.vm.load() } }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.s5)
        .padding(.horizontal, Space.s4)
    }

    private func deleteMessage(for collection: AtlasMyCollection) -> String {
        switch collection.review {
        case .pending, .pendingAuto, .pendingReview:
            tujiLocalized("這會取消送審並刪除合集，原始圖鑑卡片不受影響。")
        case .approved:
            tujiLocalized("這會立即將合集從物見下架並刪除，原始圖鑑卡片不受影響。")
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
            await LiveAtlasMutationRefresher(feed: self.feedRefresh)
                .refresh(after: .collectionDeleted(wasPublic: collection.review == .approved))
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
                size: 56
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(self.collection.title)
                    .font(.tujiH3)
                    .foregroundStyle(.tujiInk)
                    .lineLimit(1)
                Text(tujiLocalized("\(self.collection.itemCount) 字"))
                    .font(.tujiLabel)
                    .tracking(0.5)
                    .foregroundStyle(.tujiInk3)
            }
            Spacer(minLength: Space.s2)
            TujiStatusLabel(status: self.collection.review)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 建立合集

private struct AtlasCollectionCreateSheet: View {
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

// MARK: - 編輯合集

struct AtlasCollectionEditView: View {
    @Environment(CommunityFeedRefresh.self) private var feedRefresh
    @Environment(CollectionIdentityStore.self) private var identities

    @State private var vm: CollectionEditVM
    @State private var showConfirm = false
    @State private var showWithdrawConfirm = false
    @State private var showPicker = false
    @State private var avatar = ImageIntake(encoding: .collection, crop: .square(mask: .square))

    init(collectionId: String) {
        _vm = State(initialValue: CollectionEditVM(collectionId: collectionId))
    }

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back)
            // The title shown is the screen's job, not the collection's name —
            // the name is the first editable field a few points below, and the
            // system bar was rendering it twice.
            TujiScreenTitle("編輯合集")
            ScrollView {
                Group {
                    if let collection = self.vm.collection {
                        VStack(alignment: .leading, spacing: Space.s4) {
                            self.avatarSection
                            self.metaSection
                            self.membersSection
                            self.submitSection(collection)
                        }
                        .padding(.horizontal, Space.s4)
                        .padding(.bottom, Space.s4)
                    } else if case .loading = self.vm.phase {
                        TujiPageLoading()
                    } else {
                        self.errorState
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.tujiPaper)
        .navigationTitle(self.vm.collection?.title ?? tujiLocalized("編輯合集"))
        .toolbar(.hidden, for: .navigationBar)
        .task {
            self.connectAvatarUpload()
            await self.vm.load()
        }
        // Only the loaded screen can open this, so the collection's language is
        // known by the time it does — no default stands in for it.
        .sheet(isPresented: self.$showPicker) {
            if let language = self.vm.language {
                AtlasCollectionItemPicker(
                    language: language,
                    existingIds: Set(self.vm.members.map(\.id))
                ) { publicItemId in
                    await self.vm.addMember(publicItemId)
                }
            }
        }
        .imageIntake(self.avatar, title: "更換合集頭像")
        .tujiPrompt(
            isPresented: self.$showConfirm,
            style: .confirmation,
            title: "要公開這個合集嗎？",
            message: self.vm.unpublishedMemberCount > 0
                ? "將同時送審 \(self.vm.unpublishedMemberCount) 個尚未公開的項目。"
                : "送出後會先經過審核，通過才會出現在物見。",
            detail: "合集與所有項目全部通過後，才會一起公開。",
            // The VM owns the publish; what a publish refreshes is
            // AtlasMutationRefresh's call. The view only hands over the
            // environment's feed signal, so the VM stays unit-testable.
            primary: TujiPromptAction("送出審核") {
                Task { await self.publish() }
            },
            secondary: TujiPromptAction("取消", role: .cancel) {}
        )
        .tujiPrompt(
            isPresented: self.$showWithdrawConfirm,
            style: .confirmation,
            title: "要取消公開這個合集嗎？",
            message: "合集會從物見移除，裡面的項目仍然是公開的。",
            detail: "之後隨時可以再公開一次。",
            primary: TujiPromptAction("取消公開") {
                Task {
                    guard await self.vm.withdraw() else { return }
                    await self.mutations.refresh(after: .collectionWithdrawn)
                }
            },
            secondary: TujiPromptAction("先不要", role: .cancel) {}
        )
    }

    /// Stateless — the view's only contribution is the environment's feed signal.
    private var mutations: AtlasMutationRefreshing {
        LiveAtlasMutationRefresher(feed: self.feedRefresh)
    }

    private func publish() async {
        guard await self.vm.submit() else { return }
        await self.mutations.refresh(after: .collectionPublished)
    }

    // MARK: Meta

    private var avatarSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("合集頭像")
                .font(.tujiBodySm(.strong))
                .foregroundStyle(.tujiInk)
            HStack(spacing: Space.s4) {
                Button {
                    self.avatar.begin()
                } label: {
                    VStack(spacing: Space.s2) {
                        ZStack(alignment: .bottomTrailing) {
                            LazyImage(url: self.vm.avatarPreviewURL) { state in
                                if let image = state.image {
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    RoundedRectangle(cornerRadius: Radius.r0)
                                        .fill(.tujiPaper)
                                        .overlay {
                                            Image(systemName: "camera.fill")
                                                .foregroundStyle(.tujiInk3)
                                        }
                                }
                            }
                            .pipeline(.shared)
                            .frame(width: 92, height: 92)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: Radius.r0))

                            if self.avatar.isBusy {
                                TujiProgressBar(progress: nil).frame(width: 56)
                                    .tint(.white)
                                    .frame(width: 30, height: 30)
                                    .background(.black.opacity(0.45), in: .circle)
                                    .padding(5)
                            }
                        }
                        Text(self.vm.avatarPreviewURL == nil ? "選擇照片" : "更換照片")
                            .font(.tujiLabel)
                            .foregroundStyle(.tujiBrandSecondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(self.avatar.isBusy)

                Spacer(minLength: 0)
            }
            Text("這張照片會作為合集頭像顯示在公開列表與合集詳情。")
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
            // One error line for the whole avatar flow. It used to render the
            // VM's shared errorMessage, which is defined as "a failed publish
            // wins" — so a stale meta-save failure showed up here as an upload
            // failure.
            if let errorMessage = self.avatar.errorMessage {
                HStack(spacing: Space.s2) {
                    Text(errorMessage)
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiAlert)
                    Spacer(minLength: 0)
                    if self.avatar.canRetry {
                        Button("重試上傳") {
                            Task { await self.avatar.retry() }
                        }
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiBrandSecondary)
                    }
                }
            }
        }
        .padding(Space.s3)
        .background(.tujiPaper, in: .rect(cornerRadius: Radius.r0))
    }

    /// The upload needs the VM plus two environment values, none of which a
    /// `@State` initializer can see — so it is connected from `.task`, where
    /// they are reachable, and captured as plain references.
    private func connectAvatarUpload() {
        let vm = self.vm
        let identities = self.identities
        let feed = self.feedRefresh
        self.avatar.onDeliver { data in
            guard let color = await vm.updateAvatar(data) else { return .rejected(nil) }
            identities.publish(
                collectionID: vm.collectionId,
                avatarColor: color,
                avatarImageURL: vm.avatarPreviewURL
            )
            // Only a 合集 that is actually on the wall needs the wall's cache
            // busted; this used to fire unconditionally, for drafts too.
            await LiveAtlasMutationRefresher(feed: feed).refresh(
                after: .collectionAvatarChanged(isPublic: vm.collection?.review == .approved)
            )
            return .accepted
        }
    }

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("標題").font(.tujiLabel).foregroundStyle(.tujiInk3)
            TextField("標題", text: self.$vm.title)
                .textFieldStyle(.roundedBorder)
            Text("簡介").font(.tujiLabel).foregroundStyle(.tujiInk3).padding(.top, Space.s2)
            TextField("簡介（選填）", text: self.$vm.description, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
            HStack {
                if self.vm.metaSaved {
                    Text("已儲存").font(.tujiLabel).foregroundStyle(.tujiInk3)
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
                    .font(.tujiBodySm(.strong))
                    .foregroundStyle(.tujiInk)
                Spacer()
                Button {
                    self.showPicker = true
                } label: {
                    Label("新增", systemImage: "plus.circle.fill")
                        .font(.tujiBodySm(.strong))
                        .foregroundStyle(.tujiBrandSecondary)
                }
                .buttonStyle(.plain)
            }
            if self.vm.members.isEmpty {
                Text("還沒有項目。點「新增」加入你已確認完成的圖鑑。")
                    .font(.tujiLabel)
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
                    Rectangle().fill(.tujiPaper)
                    LazyImage(url: item.imageURL) { state in
                        if let image = state.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "photo").foregroundStyle(.tujiInk3)
                        }
                    }
                    .pipeline(.shared)
                }
                .frame(height: 84)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Radius.r0))

                if let label = item.collectionPublicationLabel {
                    Text(label)
                        .font(.tujiLabel)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.65), in: .rect(cornerRadius: Radius.r0))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(4)
                }

                Button {
                    Task { await self.vm.removeMember(item.id) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.tujiIcon(18))
                        .foregroundStyle(.white, .black.opacity(0.5))
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
            Text(item.lemma)
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk2)
                .lineLimit(1)
        }
    }

    // MARK: Submit

    private func submitSection(_ collection: AtlasCollectionEdit) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("公開狀態").font(.tujiLabel).foregroundStyle(.tujiInk3)
                Spacer()
                Text(collection.review.label)
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk)
            }
            if let errorMessage = self.vm.errorMessage {
                Text(errorMessage).font(.tujiLabel).foregroundStyle(.tujiAlert)
            }
            if case let .done(moderation) = self.vm.submitState {
                Text(moderation?.published == true
                    ? tujiLocalized("已通過審核，合集現在出現在物見了。")
                    : tujiLocalized("已送出，審核通過後就會出現在物見。"))
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
            }
            if collection.review.canSubmit {
                BBtn(
                    title: self.vm.isSubmitting ? "送出中…" : "公開合集",
                    bg: .tujiBrandPrimary,
                    fg: .tujiInk,
                    fullWidth: true,
                    icon: "square.and.arrow.up"
                ) {
                    self.showConfirm = true
                }
                .disabled(!self.vm.canSubmit)
                .opacity(self.vm.canSubmit ? 1 : 0.6)
                if self.vm.members.isEmpty {
                    Text("合集至少要有一個項目才能公開。")
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk3)
                }
            }

            // Without this, publishing a 合集 is one-way: the browse feed keeps
            // it forever and the only escape is deleting the collection.
            if self.vm.canWithdraw {
                BBtn(
                    title: self.vm.withdrawing ? "收回中…" : "取消公開",
                    bg: .tujiPaper,
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
                .font(.tujiIcon(36))
                .foregroundStyle(.tujiInk3)
            Text(tujiLocalized("載入失敗，請稍後再試"))
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk3)
            BBtn(title: "重試", fullWidth: false) { Task { await self.vm.load() } }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.s5)
    }
}

// MARK: - 成員挑選

private struct AtlasCollectionItemPicker: View {
    let onAdd: (String) async -> Bool

    @State private var model: CollectionCandidatesModel

    init(
        language: TargetLanguage,
        existingIds: Set<String>,
        repo: CollectionManaging = LiveAtlasRepository.shared,
        onAdd: @escaping (String) async -> Bool
    ) {
        _model = State(initialValue: CollectionCandidatesModel(
            language: language,
            existingIds: existingIds,
            repo: repo
        ))
        self.onAdd = onAdd
    }

    var body: some View {
        // No 完成 button: every tap adds its item immediately, so there was never
        // anything for 完成 to confirm — it only ever meant 關閉.
        TujiFormSheet(title: "加入項目") {
            ScrollView {
                Group {
                    if self.model.loading {
                        TujiPageLoading()
                    } else if self.model.available.isEmpty {
                        VStack(spacing: Space.s3) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.tujiIcon(36)).foregroundStyle(.tujiInk3)
                            Text(self.model.loadError == nil
                                ? tujiLocalized("沒有可加入的項目。完成辨識與確認後，就能直接加入合集。")
                                : tujiLocalized("載入失敗，請稍後再試"))
                                .font(.tujiLabel)
                                .foregroundStyle(.tujiInk3)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, Space.s5)
                        .padding(.horizontal, Space.s4)
                    } else {
                        VStack(spacing: Space.s3) {
                            if let addError = self.model.addError {
                                Text(addError)
                                    .font(.tujiLabel)
                                    .foregroundStyle(.tujiAlert)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: Space.s3), count: 3),
                                spacing: Space.s3
                            ) {
                                ForEach(self.model.available) { item in
                                    self.cell(item)
                                }
                            }
                        }
                        .padding(Space.s3)
                    }
                }
                // Without this the ScrollView shrinks to the spinner's width and
                // .tujiPaper only paints a strip down the middle of the sheet.
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task { await self.model.load() }
        }
    }

    private func cell(_ item: AtlasPublicItem) -> some View {
        let isAdded = self.model.isAdded(item.id)
        return Button {
            Task { await self.model.add(item.id, using: self.onAdd) }
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Rectangle().fill(.tujiPaper)
                    LazyImage(url: item.imageURL) { state in
                        if let image = state.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "photo").foregroundStyle(.tujiInk3)
                        }
                    }
                    .pipeline(.shared)
                }
                .frame(height: 84)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Radius.r0))
                .overlay(alignment: .bottomLeading) {
                    if let label = item.collectionPublicationLabel {
                        Text(label)
                            .font(.tujiLabel)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.65), in: .rect(cornerRadius: Radius.r0))
                            .padding(4)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.tujiIcon(18))
                        .foregroundStyle(isAdded ? .white : .white, isAdded ? .tujiAccumulation : .black.opacity(0.5))
                        .padding(4)
                }
                Text(item.lemma)
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk2)
                    .lineLimit(1)
            }
            .opacity(isAdded ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isAdded)
    }
}
