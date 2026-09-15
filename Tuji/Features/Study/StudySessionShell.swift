// The view half of the study session shell — see `StudySession.swift` for what
// it decides and why it exists.
//
// Three pieces, because a flow places them in three different spots: the
// modifier wraps the whole screen, the nav bar sits wherever that flow draws
// its top edge (複習 inside a `GeometryReader` that budgets for it, 學新字 above
// a preview that has no session yet), and the finish screen replaces the
// question area once the queue drains.

import SwiftUI

extension View {
    /// Wraps a study flow: leaving, 報錯, study focus and the session's
    /// analytics.
    ///
    /// Belongs on the flow's **root**, outside every sheet the flow raises —
    /// `wordDetailPresentation` is an environment value, and a sheet only
    /// inherits what was set above the view that presents it.
    func studySessionShell(_ shell: StudySessionShell) -> some View {
        modifier(StudySessionShellModifier(shell: shell))
    }
}

private struct StudySessionShellModifier: ViewModifier {
    @Bindable var shell: StudySessionShell

    @Environment(\.dismiss) private var dismiss
    @Environment(StudyFocus.self) private var studyFocus

    func body(content: Content) -> some View {
        content
            .environment(\.wordDetailPresentation, .sheet)
            .tujiPrompt(
                isPresented: self.$shell.confirmingExit,
                style: .confirmation,
                title: self.shell.kind == .review ? "要離開這次複習嗎？" : "要離開這次學習嗎？",
                message: self.shell.kind == .review
                    ? "已答的進度會保留，未完成的字下次還會出現。"
                    : "完成全部步驟的字會保留，其餘下次重新開始。",
                primary: TujiPromptAction("先離開") {
                    self.shell.confirmLeave()
                    self.dismiss()
                },
                secondary: TujiPromptAction(
                    self.shell.kind == .review ? "繼續複習" : "繼續學習",
                    role: .cancel
                ) {}
            )
            .tujiPrompt(
                isPresented: self.$shell.showsCustomCardNotice,
                style: .confirmation,
                title: "自制卡片暫不支援報錯",
                message: "報錯僅適用於官方單字內容。自制卡片如有問題，可以到自制圖鑑刪除重拍，或透過「我的」頁的意見收集告訴我們。",
                primary: TujiPromptAction("知道了") {}
            )
            .fullScreenCover(item: self.$shell.reportDraft) { draft in
                StudyReportSheet(draft: draft)
            }
            .onAppear {
                self.studyFocus.enter()
                AnalyticsService.shared.track(.studyStart, category: self.shell.kind.wireName)
            }
            // Not only the 先離開 prompt: a swipe-back, a deep link, anything
            // that removes the screen has to take the beats and the audio with
            // it. Safe to key on disappearing because nothing in a session
            // pushes over it — a full-screen cover and a sheet leave it on
            // screen (verified on iOS 26), and word detail opens as a sheet.
            .onDisappear {
                self.studyFocus.exit()
                self.shell.session.leave()
            }
    }
}

/// The session's top edge: ✕ and the 報錯 menu.
///
/// Drawn in the content rather than by the system: on iOS 26 a toolbar item is
/// a floating glass circle, and two white discs at the top of a study screen
/// are the platform talking over it.
struct StudySessionNavBar: View {
    let shell: StudySessionShell
    /// Whether ✕ asks first. Nothing is lost before the first card or after the
    /// last, so only a session in progress needs to.
    var confirmsExit: Bool = true
    var offersReport: Bool = true

    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        TujiNavBar(
            leading: .close,
            onLeading: {
                if self.shell.close(confirming: self.confirmsExit) {
                    self.dismiss()
                }
            }
        ) {
            if self.offersReport {
                Menu {
                    Button("報錯", systemImage: "exclamationmark.bubble") {
                        self.shell.report(uiLang: self.settings.current.uiLang)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.tujiIcon(19, weight: .semibold))
                        .foregroundStyle(.tujiInk)
                        .frame(width: 44, height: 48)
                        .contentShape(.rect)
                }
                .accessibilityLabel(Text("更多"))
            }
        }
    }
}

/// What a finished session shows, and the refresh that finishing it owes.
///
/// A streak milestone wins: it happens at most a few times a year and the
/// summary is always one tap away behind it. It can be crossed by a 學新字
/// write as easily as by a 複習 one — the server attaches it to whichever
/// answer crosses the threshold — and the branch used to be missing from
/// 學新字 entirely, so those milestones were shown nowhere.
struct StudySessionFinish<Summary: View>: View {
    let shell: StudySessionShell
    let onFinish: () -> Void
    /// Runs when the post-session refresh lands.
    var onRefreshed: @MainActor () -> Void = {}
    @ViewBuilder let summary: Summary

    var body: some View {
        Group {
            if let milestone = self.shell.session.writes.milestone {
                MilestoneView(milestone: milestone, onFinish: self.onFinish)
            } else {
                self.summary
            }
        }
        // On the group, not on each branch: a milestone that lands after the
        // summary appeared switches the branch, and that is still one finish.
        .onAppear {
            AnalyticsService.shared.track(.studyComplete, category: self.shell.kind.wireName)
        }
        // The refresh hangs off the finish, not off whichever screen celebrates
        // it — a milestone session used to refresh nothing.
        .refreshesFinishedSession(draining: self.shell.session.writes, then: self.onRefreshed)
    }
}
