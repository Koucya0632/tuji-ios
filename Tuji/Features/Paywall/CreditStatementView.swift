// 點數明細 — the balance, where it came from, and the recent movements.
//
// Reached from 助手's top-right corner: asking AI spends a point or two at a
// time, and this is where those add up to something a person can check. The
// arithmetic is `CreditStatement`; this file loads a page and draws it.

import Observation
import SwiftUI

@MainActor
@Observable
final class CreditStatementModel {
    enum Refusal: Equatable {
        /// Not a 罐頭點數 account: there is no wallet to show.
        case notEnrolled
        case unreachable
    }

    private(set) var statement: CreditStatement?
    private(set) var phase: LoadPhase = .idle
    private(set) var refusal: Refusal?

    private let repository: CreditStatementReading

    init(repository: CreditStatementReading = LiveCheckInRepository()) {
        self.repository = repository
    }

    func load() async {
        self.phase = self.phase.reloading
        do {
            self.statement = try await CreditStatement(page: self.repository.loadStatement())
            self.refusal = nil
            self.phase = .loaded
        } catch {
            // What was on screen stays on screen; only a first load that fails
            // has nothing better to show than the reason.
            self.phase = self.phase.afterFailure
            guard self.statement == nil else { return }
            switch error {
            case APIError.forbidden, APIError.notFound, APIError.unauthorized: self.refusal = .notEnrolled
            default: self.refusal = .unreachable
            }
        }
    }
}

struct CreditStatementView: View {
    @Environment(StudyFocus.self) private var studyFocus
    @Environment(SettingsStore.self) private var settings
    @Environment(\.presentPaywall) private var presentPaywall

    @State private var model: CreditStatementModel

    init(model: CreditStatementModel = CreditStatementModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back, compactTitle: Text("點數明細"), showsRule: true)
            self.content
            self.buyBar
        }
        .background(Color.tujiPaper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        // Every visit reads again: the point of coming here from 助手 is to see
        // what the last question cost.
        .task { await self.model.load() }
        .onAppear { self.studyFocus.enter() }
        .onDisappear { self.studyFocus.exit() }
    }

    @ViewBuilder
    private var content: some View {
        if let statement = self.model.statement {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    self.balance(statement)
                    self.sources(statement)
                    self.records(statement)
                }
                .padding(.bottom, Space.s4)
            }
            .refreshable { await self.model.load() }
        } else if let refusal = self.model.refusal {
            self.refused(refusal)
        } else {
            VStack {
                TujiProgressBar(progress: nil).frame(width: 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 餘額

    /// The ink block, edge to edge — the same weight 今天's hero has, because on
    /// this screen the number is the thing.
    private func balance(_ statement: CreditStatement) -> some View {
        HStack(alignment: .bottom, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("可用罐頭點數")
                    .font(.tujiLabel)
                    .tracking(0.5)
                    .foregroundStyle(.tujiPaper.opacity(0.6))
                Text(verbatim: statement.available.formatted(.number.locale(self.locale)))
                    .font(.tujiDisplay)
                    .foregroundStyle(.tujiPaper)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(self.balanceNote(statement))
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiPaper.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image("CreditCan")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .foregroundStyle(.tujiCurrent)
                .accessibilityHidden(true)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiInk)
    }

    private func balanceNote(_ statement: CreditStatement) -> String {
        statement.reserved > 0
            ? tujiLocalized("另有 \(statement.reserved) 點保留給進行中的識別")
            : tujiLocalized("打卡與購買的點數不會過期")
    }

    // MARK: - 來源

    private func sources(_ statement: CreditStatement) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            self.heading("餘額來源")
            self.source(
                title: "每月贈點",
                detail: statement.monthlyExpires.map {
                    tujiLocalized("有效至 \(self.day($0))，每月補滿、不累積")
                } ?? tujiLocalized("每月補滿、不累積"),
                points: statement.sources.monthly
            )
            self.rule
            self.source(
                title: "打卡點數",
                detail: tujiLocalized("每天學習後領取，不會過期"),
                points: statement.sources.checkIn
            )
            self.rule
            self.source(
                title: "購買點數",
                detail: tujiLocalized("加購的點數，不會過期"),
                points: statement.sources.purchased
            )
            if statement.sources.otherGift > 0 {
                self.rule
                self.source(
                    title: "其他贈點",
                    detail: tujiLocalized("活動或補償贈送"),
                    points: statement.sources.otherGift
                )
            }
        }
        .padding(.horizontal, Space.s4)
    }

    private func source(title: LocalizedStringKey, detail: String, points: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.tujiBody(.strong))
                    .foregroundStyle(.tujiInk)
                Text(verbatim: detail)
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s2)
            Text(verbatim: points.formatted(.number.locale(self.locale)))
                .font(.tujiH3)
                .foregroundStyle(.tujiInk)
        }
        .padding(.vertical, Space.s3)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 近期紀錄

    private func records(_ statement: CreditStatement) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            self.heading("近期紀錄")
            if statement.records.isEmpty {
                Text("領到或用掉點數之後，紀錄會出現在這裡。")
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
                    .padding(.vertical, Space.s3)
            } else {
                ForEach(Array(statement.records.enumerated()), id: \.element.id) { index, record in
                    if index > 0 { self.rule }
                    self.row(record)
                }
            }
        }
        .padding(.horizontal, Space.s4)
    }

    private func row(_ record: CreditStatement.Record) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: Self.title(record.activity))
                    .font(.tujiBody(.strong))
                    .foregroundStyle(.tujiInk)
                if let date = record.date {
                    Text(verbatim: self.moment(date))
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk3)
                }
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 2) {
                // Spending is ink and a gain is teal — teal is accumulation
                // everywhere else in the app. Neither is red: using points is
                // what they are for, not a warning.
                Text(verbatim: Self.signed(record.amount))
                    .font(.tujiH3)
                    .foregroundStyle(record.amount > 0 ? Color.tujiAccumulation : .tujiInk)
                Text(tujiLocalized("餘 \(record.balanceAfter) 點"))
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
            }
        }
        .padding(.vertical, Space.s3)
        .accessibilityElement(children: .combine)
    }

    /// A gain carries its plus; a minus sign is already part of the number.
    private static func signed(_ amount: Int) -> String {
        let digits = String(amount)
        return amount > 0 ? "+" + digits : digits
    }

    static func title(_ activity: CreditStatement.Activity) -> String {
        switch activity {
        case .askedAssistant: tujiLocalized("問 AI")
        case .recognition: tujiLocalized("拍照識別")
        case .monthlyGift: tujiLocalized("每月贈點")
        case .checkIn: tujiLocalized("打卡點數")
        case .purchase: tujiLocalized("購買點數")
        case .gift: tujiLocalized("贈點")
        case .expired: tujiLocalized("點數到期")
        case .refund: tujiLocalized("退款")
        case .returned: tujiLocalized("退還點數")
        case .other: tujiLocalized("點數異動")
        }
    }

    // MARK: - 讀不到

    private func refused(_ refusal: CreditStatementModel.Refusal) -> some View {
        VStack {
            Spacer(minLength: Space.s5)
            switch refusal {
            case .notEnrolled:
                MascotEmptyState(
                    pose: .think,
                    title: "這裡會列出你的罐頭點數",
                    message: "加入會員後每月有贈點，可以用來拍照識別和問 AI。"
                )
            case .unreachable:
                TujiErrorState(title: "讀不到點數明細", message: tujiLocalized("檢查網路後再試一次。")) {
                    BBtn(title: "重試", fullWidth: false) {
                        Task { await self.model.load() }
                    }
                }
            }
            Spacer(minLength: Space.s5)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.s4)
    }

    // MARK: - 加購

    /// Pinned under the list rather than at the end of it: the reason to come
    /// here is often that the balance is low.
    private var buyBar: some View {
        BBtn(
            title: self.model.refusal == .notEnrolled ? "看看會員方案" : "加購罐頭點數",
            fullWidth: true
        ) {
            self.presentPaywall()
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .background(alignment: .top) {
            Rectangle().fill(.tujiRule).frame(height: Border.bw1)
        }
    }

    // MARK: - Bits

    private func heading(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.tujiLabel)
            .tracking(0.5)
            .foregroundStyle(.tujiInk3)
            .padding(.bottom, Space.s1)
    }

    private var rule: some View {
        Rectangle().fill(.tujiRule).frame(height: Border.bw1)
    }

    private var locale: Locale {
        self.settings.current.uiLanguage.locale
    }

    private func day(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).locale(self.locale))
    }

    private func moment(_ date: Date) -> String {
        date.formatted(
            .dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute().locale(self.locale)
        )
    }
}
