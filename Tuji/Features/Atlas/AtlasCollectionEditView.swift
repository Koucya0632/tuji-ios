// 編輯合集 —— 名稱、簡介、頭像、成員，以及送審與收回。
//
// 它住在 `AtlasMyCollectionsView.swift` 裡，因為我的合集列表是它的入口。那個檔案
// 因此是五個畫面：列表、列（row）、建立合集 sheet、這個編輯畫面，以及成員挑選器
// ——其中三個有自己的 model，而只有第一個出現在檔名上。
//
// 成員挑選器（`AtlasCollectionItemPicker`）留在列表那邊：它是從這裡推出去的，但
// 兩邊都用得到，而且它只有一個 model 和一份清單。
//
// 這個畫面有兩種儲存模型：頭像與成員是「改了就立刻寫回伺服器」，標題與簡介要按
// 儲存。所以儲存待在導覽列（跟 `EditProfileView` 同一個位置），而且只有真的改過
// 才亮 —— 它從前是一顆浮在頁面中間的黃色按鈕，是全頁最大的東西，卻只管兩個欄位。

import Nuke
import NukeUI
import SwiftUI

// MARK: - 編輯合集

struct AtlasCollectionEditView: View {
    @Environment(CommunityFeedRefresh.self) private var feedRefresh
    @Environment(CollectionIdentityStore.self) private var identities
    @Environment(\.dismiss) private var dismiss

    @State private var vm: CollectionEditVM
    @State private var showConfirm = false
    @State private var showWithdrawConfirm = false
    @State private var showDiscardConfirm = false
    @State private var showPicker = false
    @State private var showsAllMembers = false
    @State private var avatar = ImageIntake(encoding: .collection, crop: .square(mask: .square))

    /// `repo` is the same seam `AtlasCollectionCreateSheet` and
    /// `AtlasCollectionItemPicker` already expose: it is what lets this screen be
    /// rendered from a fixture instead of a signed-in account.
    init(collectionId: String, repo: CollectionEditing = LiveAtlasRepository.shared) {
        _vm = State(initialValue: CollectionEditVM(collectionId: collectionId, repo: repo))
    }

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back, onLeading: self.leaveScreen) {
                TujiNavTextAction(
                    title: self.vm.savingMeta ? "儲存中…" : "儲存",
                    isEnabled: self.vm.canSaveMeta
                ) {
                    Task { await self.vm.saveMeta() }
                }
            }
            // The title shown is the screen's job, not the collection's name —
            // the name is the first editable field a few points below, and the
            // system bar was rendering it twice.
            TujiScreenTitle("編輯合集")
            ScrollView {
                Group {
                    if let collection = self.vm.collection {
                        // Each section carries its own page margin (TujiField
                        // already does), so nothing here adds a second one.
                        VStack(alignment: .leading, spacing: 0) {
                            self.avatarSection
                            self.metaSection
                            self.membersSection
                            self.submitSection(collection)
                        }
                    } else if case .loading = self.vm.phase {
                        TujiPageLoading()
                    } else {
                        self.errorState
                    }
                }
                .frame(maxWidth: .infinity)
            }
            // The 簡介 field is the last thing above the fold on a small screen,
            // so the keyboard must be dismissible by dragging the page.
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.tujiPaper)
        .navigationTitle(self.vm.collection?.title ?? tujiLocalized("編輯合集"))
        .toolbar(.hidden, for: .navigationBar)
        // `onLeading:` only intercepts the ← button. Hiding the system back item
        // is what also takes away the interactive pop gesture, so it is applied
        // exactly while there is something to lose — a clean screen keeps its
        // swipe-back (ReviewFlowView does the same for a review in progress).
        .navigationBarBackButtonHidden(self.vm.isMetaDirty)
        .task {
            self.connectAvatarUpload()
            await self.vm.load()
        }
        // Only the loaded screen can open this, so the collection's language and
        // review status are known by the time it does — no default stands in for
        // either. A `.ja` default here once scoped an 英文 author's picker to 日文.
        .sheet(isPresented: self.$showPicker) {
            if let collection = self.vm.collection {
                AtlasCollectionItemPicker(
                    language: collection.targetLanguage,
                    // What the 合集 can still take depends on where it sits in
                    // review, so the picker is told — otherwise it offers items
                    // the server will refuse (the 409 this screen used to show).
                    collectionReview: collection.review,
                    existingIds: Set(self.vm.members.map(\.id))
                ) { publicItemId in
                    let failure = await self.vm.addMember(publicItemId)
                    // A new card lands at the *end* of the roster, so a collapsed
                    // list would answer an explicit 加入 with no visible change.
                    if failure == nil { self.showsAllMembers = true }
                    return failure
                }
            }
        }
        .imageIntake(self.avatar, title: "更換合集頭像")
        .tujiPrompt(
            isPresented: self.$showConfirm,
            style: .confirmation,
            title: "要公開這個合集嗎？",
            message: self.vm.unpublishedMemberCount > 0
                ? "將同時送審 \(self.vm.unpublishedMemberCount) 張尚未公開的卡片。"
                : "送出後會先經過審核，通過才會出現在物見。",
            detail: "合集與所有卡片全部通過後，才會一起公開。",
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
            message: "合集會從物見移除，裡面的卡片仍然是公開的。",
            detail: "之後隨時可以再公開一次。",
            primary: TujiPromptAction("取消公開") {
                Task {
                    guard await self.vm.withdraw() else { return }
                    await self.mutations.refresh(after: .collectionWithdrawn)
                }
            },
            secondary: TujiPromptAction("先不要", role: .cancel) {}
        )
        // 頭像與成員存在伺服器上的那一刻就已經存了；只有這兩個欄位會跟著離開一起
        // 消失，所以只有它們需要被攔下來問。
        .tujiPrompt(
            isPresented: self.$showDiscardConfirm,
            style: .destructive,
            title: "要放棄未儲存的變更嗎？",
            message: "標題與簡介還沒有儲存。",
            // A blank title cannot be saved at all, so on that one path the
            // offer to save would be a button that does nothing.
            primary: self.vm.canSaveMeta
                ? TujiPromptAction("儲存並離開") { self.saveThenLeave() }
                : TujiPromptAction("放棄變更", role: .destructive) { self.dismiss() },
            alternative: self.vm.canSaveMeta
                ? TujiPromptAction("放棄變更", role: .destructive) { self.dismiss() }
                : nil,
            secondary: TujiPromptAction("取消", role: .cancel) {}
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

    /// The back button asks before dropping typed-but-unsaved 標題/簡介. It cannot
    /// catch the interactive back-swipe — that gesture belongs to the navigation
    /// stack — so 儲存 staying lit is still the primary signal.
    private func leaveScreen() {
        if self.vm.isMetaDirty {
            self.showDiscardConfirm = true
        } else {
            self.dismiss()
        }
    }

    private func saveThenLeave() {
        Task {
            guard await self.vm.saveMeta() else { return }
            self.dismiss()
        }
    }

    // MARK: Avatar

    /// One centred photograph, the way 編輯個人資料 does it — this used to be a
    /// 92pt square inside a paper card laid on the paper page, which drew nothing
    /// but an extra 16pt of indent that broke the app's single 24pt margin line.
    ///
    /// It draws `CollectionIdentityTile`, so what the author sees here is exactly
    /// what 物見 will show, including the generated colour when there is no photo.
    private var avatarSection: some View {
        TujiField(
            label: "合集頭像",
            footer: "這張照片會作為合集頭像顯示在公開列表與合集詳情。"
        ) {
            VStack(spacing: Space.s2) {
                Button {
                    self.avatar.begin()
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        CollectionIdentityTile(
                            collectionID: self.vm.collectionId,
                            avatarColor: self.vm.avatarColor,
                            avatarImageURL: self.vm.avatarPreviewURL,
                            size: 120
                        )
                        if self.avatar.isBusy {
                            TujiProgressBar(progress: nil)
                                .frame(width: 56)
                                .tint(.white)
                                .frame(width: 120, height: 120)
                                .background(.black.opacity(0.45))
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.tujiIcon(14, weight: .bold))
                                .foregroundStyle(.tujiInk)
                                .frame(width: 34, height: 34)
                                .background(.tujiBrandPrimary, in: .circle)
                                .overlay(Circle().stroke(.tujiPaper, lineWidth: 3))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(self.avatar.isBusy)
                .accessibilityLabel(Text("更換合集頭像"))

                Text("點一下更換照片")
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)

                // One error line for the whole avatar flow. It used to render the
                // VM's shared errorMessage, which is defined as "a failed publish
                // wins" — so a stale meta-save failure showed up here as an upload
                // failure.
                if let errorMessage = self.avatar.errorMessage {
                    HStack(spacing: Space.s2) {
                        Text(verbatim: errorMessage)
                            .font(.tujiLabel)
                            .foregroundStyle(.tujiAlert)
                            .fixedSize(horizontal: false, vertical: true)
                        if self.avatar.canRetry {
                            Button("重試上傳") {
                                Task { await self.avatar.retry() }
                            }
                            .font(.tujiLabel)
                            .foregroundStyle(.tujiInk)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, Space.s2)
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

    // MARK: Meta

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            TujiField(label: "標題") {
                TujiTextField(placeholder: "例如：生活日常", text: self.$vm.title)
            }
            TujiField(label: "簡介（選填）") {
                TujiTextField(
                    placeholder: "簡單描述這個合集",
                    text: self.$vm.description,
                    lineLimit: 2...4
                )
            }
            self.metaStatusLine
        }
        .padding(.top, Space.s4)
        .animation(Motion.ease(Motion.d2), value: self.vm.metaSaved)
    }

    /// 已儲存 appears only after a save, and disappears the moment the fields
    /// differ from the server again — the same fact 儲存 lights up for. Holding a
    /// permanent empty line for it cost 48pt of nothing between 簡介 and 卡片.
    @ViewBuilder
    private var metaStatusLine: some View {
        if self.vm.metaSaved, !self.vm.isMetaDirty {
            TujiStatusEdgeLabel(text: Text("已儲存"), edge: .tujiAccumulation)
                .padding(.horizontal, Space.s4)
                .transition(.opacity)
        }
    }

    // MARK: Members

    /// A roster, not a contact sheet: the three-column grid this used to be cut
    /// 「Computer keyboard」 down to 「Computer keyb…」, hid each card's review
    /// state under a black chip on the photograph, and gave 移除 an 18pt target.
    /// Rows are what 圖鑑管理 uses for the same objects, and they have room for
    /// the whole name, the real status label and a 44pt button.
    private var membersSection: some View {
        CollectionMemberList(
            members: self.vm.members,
            errorMessage: self.vm.memberError,
            showsAll: self.$showsAllMembers,
            onAdd: { self.showPicker = true },
            onRemove: { item in Task { await self.vm.removeMember(item.id) } }
        )
    }

    // MARK: Submit

    private func submitSection(_ collection: AtlasCollectionEdit) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                Text("公開狀態")
                    .font(.tujiLabel)
                    .tracking(0.5)
                    .foregroundStyle(.tujiInk3)
                Spacer(minLength: 0)
                TujiStatusLabel(status: collection.review)
            }
            .accessibilityElement(children: .combine)

            if let errorMessage = self.vm.errorMessage {
                Text(verbatim: errorMessage)
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiAlert)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if case let .done(moderation) = self.vm.submitState {
                Text(moderation?.published == true
                    ? tujiLocalized("已通過審核，合集現在出現在物見了。")
                    : tujiLocalized("已送出，審核通過後就會出現在物見。"))
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let note = self.reviewNote(collection.review) {
                Text(note)
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
                    .fixedSize(horizontal: false, vertical: true)
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
                if self.vm.members.isEmpty {
                    Text("合集至少要有一張卡片才能公開。")
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Without this, publishing a 合集 is one-way: the browse feed keeps
            // it forever and the only escape is deleting the collection. It wears
            // the quiet ground — 取消公開 is a utility, not this screen's call to
            // action, and on `.tujiPaper` it had no ground at all.
            if self.vm.canWithdraw {
                BBtn(
                    title: self.vm.withdrawing ? "收回中…" : "取消公開",
                    bg: .tujiPaper2,
                    fg: .tujiInk,
                    fullWidth: true,
                    icon: "arrow.uturn.backward"
                ) {
                    self.showWithdrawConfirm = true
                }
                .disabled(self.vm.withdrawing)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s6)
    }

    /// What the state means on the three branches that offer no button at all.
    /// Without this the page ends in a status chip and 64pt of nothing, and the
    /// one state that is final (`takedown`, which the server refuses to
    /// re-publish) looks exactly like the one that is merely waiting.
    private func reviewNote(_ review: AtlasReviewStatus) -> LocalizedStringKey? {
        switch review {
        case .pending, .pendingAuto, .pendingReview: "已送出，審核通過後就會出現在物見。"
        case .rejected: "未通過。修改後可以再送一次。"
        case .takedown: "已被下架，不能再次公開。"
        case .draft, .approved, .withdrawn: nil
        }
    }

    private var errorState: some View {
        TujiBlankState(
            icon: "exclamationmark.triangle",
            iconSize: 36,
            kind: .failed,
            retry: { await self.vm.load() }
        )
    }
}
