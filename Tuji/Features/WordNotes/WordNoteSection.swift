// 我的筆記 on the word page. Hidden under membership v1 and for guests; a lock
// for a non-member; read-only for a non-member who already wrote one.

import SwiftUI

struct WordNoteSection: View {
    let wordId: String

    @Environment(WordNotesStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(\.presentPaywall) private var presentPaywall
    @State private var showEditor = false
    @State private var confirmDelete = false
    private let access: any MemberAccessReading = LiveMemberAccess()

    private var level: MemberAccessLevel {
        self.access.level(.wordNote, hasOwnData: self.store.note(for: self.wordId) != nil)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Always drawn, so the `.task` below runs — see `TaskAnchor`.
            TaskAnchor()
            if !self.auth.isGuest {
                switch self.level {
                case .hidden:
                    EmptyView()
                case .locked:
                    Button { self.presentPaywall() } label: {
                        self.card {
                            Label("會員可以為每個字寫下自己的筆記", systemImage: "lock.fill")
                                .font(.tujiBodySm)
                                .foregroundStyle(.tujiInk3)
                        }
                    }
                    .buttonStyle(.plain)
                case .readOnly:
                    self.card {
                        self.noteText
                        HStack {
                            Button { self.presentPaywall() } label: {
                                Text("成為會員才能編輯")
                                    .font(.tujiLabel)
                                    .underline()
                                    .foregroundStyle(.tujiInk2)
                            }
                            Spacer()
                            Button("刪除筆記", role: .destructive) { self.confirmDelete = true }
                                .font(.tujiLabel)
                                .foregroundStyle(.tujiAlert)
                        }
                        .buttonStyle(.plain)
                    }
                case .open:
                    Button { self.showEditor = true } label: {
                        self.card {
                            if self.store.note(for: self.wordId) != nil {
                                self.noteText
                            } else {
                                Text("寫下你自己的記法、例句或提醒…")
                                    .font(.tujiBodySm)
                                    .foregroundStyle(.tujiInk3)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("編輯筆記"))
                }
            }
        }
        .task {
            guard !self.auth.isGuest, self.access.level(.wordNote, hasOwnData: true) != .hidden else { return }
            await self.store.loadIfNeeded()
        }
        .sheet(isPresented: self.$showEditor) {
            // Hosted here, so a refused save opens 付費頁 on top of the editor.
            WordNoteEditorSheet(wordId: self.wordId).paywallHost()
        }
        .tujiPrompt(
            isPresented: self.$confirmDelete,
            style: .destructive,
            title: "刪除這則筆記？",
            primary: TujiPromptAction("刪除", role: .destructive) {
                let wordId = self.wordId
                Task { _ = await self.store.delete(for: wordId) }
            },
            secondary: TujiPromptAction("取消", role: .cancel) {}
        )
    }

    private var noteText: some View {
        Text(verbatim: self.store.note(for: self.wordId)?.body ?? "")
            .font(.tujiBody)
            .foregroundStyle(.tujiInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("我的筆記")
                .font(.tujiLabel)
                .tracking(2)
                .foregroundStyle(.tujiInk3)
            content()
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiPaper2, in: .rect(cornerRadius: Radius.r0))
        .contentShape(.rect)
    }
}

/// Writing or rewriting one note. Saving an empty note is not offered — deleting is.
struct WordNoteEditorSheet: View {
    let wordId: String

    @Environment(WordNotesStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentPaywall) private var presentPaywall
    @State private var text = ""
    @State private var working = false
    @State private var error: String?

    private var count: Int {
        self.text.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    var body: some View {
        TujiSheetShell(title: "我的筆記", height: 460) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    TujiField(label: "筆記") {
                        TujiTextField(
                            placeholder: "寫下你自己的記法、例句或提醒…",
                            text: self.$text,
                            lineLimit: 4...10,
                            errorMessage: self.error
                        )
                    }
                    Text(verbatim: "\(self.count) / \(self.store.maxLength)")
                        .font(.tujiLabel)
                        .foregroundStyle(self.count > self.store.maxLength ? .tujiAlert : .tujiInk3)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, Space.s4)
                    BBtn(title: self.working ? "儲存中…" : "儲存", fullWidth: true) {
                        Task { await self.save() }
                    }
                    .disabled(self.working || !self.store.isValid(self.text))
                    .padding(.horizontal, Space.s4)
                    if self.store.note(for: self.wordId) != nil {
                        Button("刪除筆記", role: .destructive) {
                            Task { await self.remove() }
                        }
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiAlert)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s5)
            }
        }
        .onAppear { self.text = self.store.note(for: self.wordId)?.body ?? "" }
    }

    private func save() async {
        self.working = true
        defer { self.working = false }
        await self.handle(self.store.save(self.text, for: self.wordId))
    }

    private func remove() async {
        self.working = true
        defer { self.working = false }
        await self.handle(self.store.delete(for: self.wordId))
    }

    private func handle(_ outcome: MemberWriteOutcome) {
        switch outcome {
        case .done, .missing:
            self.dismiss()
        case .needsUpgrade:
            self.presentPaywall()
        case .atLimit:
            self.error = tujiLocalized("已達上限")
        case let .failed(message):
            self.error = message
        }
    }
}

/// The note, read-only, where review reveals the answer. Nothing at all when
/// there is none — the reveal is not the place to invite writing one.
struct WordNoteLine: View {
    let wordId: String
    @Environment(WordNotesStore.self) private var store
    private let access: any MemberAccessReading = LiveMemberAccess()

    /// A note is shown wherever the feature exists — a refunded non-member
    /// still reads their own notes.
    private var visible: Bool {
        self.access.level(.wordNote, hasOwnData: true) != .hidden
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Always drawn, so the `.task` below runs — see `TaskAnchor`.
            TaskAnchor()
            if self.visible, let note = self.store.note(for: self.wordId) {
                HStack(alignment: .top, spacing: Space.s2) {
                    Image(systemName: "note.text")
                        .font(.tujiIcon(13, weight: .semibold))
                        .foregroundStyle(.tujiInk3)
                        .accessibilityLabel(Text("我的筆記"))
                    Text(verbatim: note.body)
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk2)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .task {
            guard self.visible else { return }
            await self.store.loadIfNeeded()
        }
    }
}
