// One 檢舉 flow — the reason sheet, the write, and what the menu row says
// afterwards — shared by 物見詳情, 合集詳情 and 作者主頁.
//
// All three used to spell out the same sheet: the same 460pt height, the same
// `AtlasReportReason.allCases` mapping, the same footer line. They diverged in
// the way duplicated flows do, and here the divergence was the write itself:
//
//   - 物見詳情 went through `AtlasPublicDetailVM.report`, which awaited the call
//     and only then marked it sent.
//   - 合集詳情 and 作者主頁 each held `private let reporter =
//     LiveAtlasRepository.shared` — no init seam, so no test could substitute it
//     — set `reportSent = true` *before* the call, and swallowed the result with
//     `try?`. A 檢舉 that 401'd, 429'd or never left the device rendered as
//     「已收到檢舉」.
//
// Same shape as `AvatarPicker`: an @Observable module plus a view modifier that
// hosts the presentation, so a screen keeps only the button that calls `begin`
// and whatever it renders from `phase`.

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ReportFlow {
    enum Phase: Equatable {
        case idle
        case sending
        /// The server accepted it. Only reachable after a successful await.
        case sent
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var target: ReportTarget?
    /// Drives the reason sheet. Settable because `.tujiSheet` needs a binding.
    var isPresented = false

    private let submitter: any ReportSubmitting

    init(submitter: any ReportSubmitting = LiveAtlasRepository.shared) {
        self.submitter = submitter
    }

    /// True once this screen's 檢舉 has been accepted — the menu row uses it to
    /// say 「已收到檢舉」 and disable itself.
    var isSent: Bool {
        self.phase == .sent
    }

    var errorMessage: String? {
        if case let .failed(message) = self.phase { return message }
        return nil
    }

    func begin(_ target: ReportTarget) {
        self.target = target
        self.isPresented = true
    }

    /// Takes the target explicitly rather than reading `self.target`: the sheet
    /// dismisses as the callback fires, and a flow that read its own state
    /// asynchronously would race that teardown — the same trap
    /// [[TujiPrompt]] set by clearing its backing state before the action runs.
    func submit(_ target: ReportTarget, reason: AtlasReportReason) async {
        self.phase = .sending
        do {
            try await self.submitter.submit(target, reason: reason, detail: nil)
            self.phase = .sent
        } catch {
            self.phase = .failed(error.localizedDescription)
        }
    }
}

private struct ReportSheetModifier: ViewModifier {
    let flow: ReportFlow

    func body(content: Content) -> some View {
        content
            // Five options plus the footer line; the default height clips the last.
            .tujiSheet(isPresented: Binding(
                get: { self.flow.isPresented },
                set: { self.flow.isPresented = $0 }
            ), title: "檢舉原因", height: 460) {
                TujiOptionSheet(
                    options: AtlasReportReason.allCases.map {
                        TujiOptionSheet<AtlasReportReason?>.Option(
                            Optional($0),
                            verbatim: $0.label
                        )
                    },
                    selection: AtlasReportReason?.none,
                    footer: "檢舉會送給審核人員，對方不會知道是誰檢舉的。"
                ) { picked in
                    guard let picked, let target = self.flow.target else { return }
                    Task { await self.flow.submit(target, reason: picked) }
                }
            }
    }
}

extension View {
    /// Hosts the 檢舉 reason sheet. The screen keeps only the menu row that calls
    /// `flow.begin(_:)` and whatever it renders from `flow.isSent` /
    /// `flow.errorMessage`.
    func reportSheet(_ flow: ReportFlow) -> some View {
        self.modifier(ReportSheetModifier(flow: flow))
    }
}
