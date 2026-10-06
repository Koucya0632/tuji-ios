// 打卡 — opened from 首頁's streak chip.
//
// Three blocks: the streak, today's points, and the month. Studying is the
// check-in (one word-card answer, the rule the streak already used), so the
// calendar is the streak drawn out day by day, and the points card is only the
// tap that collects what today's studying earned. The decisions are in
// `CheckInDecision`; this file is the drawing.
//
// No flame, no gradient, no medal. A filled square is a day you studied, in
// 累積 blue like every other "what you have built up" mark in the app, and
// today wears the 瞳黃 focus stroke because it is the day still in play.

import SwiftUI

struct CheckInSheet: View {
    let model: CheckInModel
    /// The streak 首頁 already has, shown until the calendar's own copy lands.
    let fallbackStreak: StudyStreak?
    /// Close the sheet and start studying.
    let onStudy: () -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(\.presentPaywall) private var presentPaywall
    @State private var claimedTick = 0

    private var streak: StudyStreak? {
        self.model.calendar?.streak ?? self.fallbackStreak
    }

    private var reward: CheckInDecision.Reward {
        self.model.reward(fallbackStudiedToday: (self.streak?.todayCount ?? 0) > 0)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                self.hero
                if self.reward != .hidden {
                    self.rewardCard
                }
                self.calendarSection
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s5)
        }
        .sensoryFeedback(.success, trigger: self.claimedTick)
        .task {
            async let reward: Void = self.model.loadReward()
            async let calendar: Void = self.model.loadCalendar()
            _ = await (reward, calendar)
        }
    }

    // MARK: - Streak

    private var hero: some View {
        let current = self.streak?.current ?? 0
        return HStack(alignment: .bottom, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("連續學習")
                    .font(.tujiLabel)
                    .tracking(2)
                    .foregroundStyle(.tujiInk3)
                HStack(alignment: .firstTextBaseline, spacing: Space.s1) {
                    Text("\(current)")
                        .font(.tujiDisplay)
                        .foregroundStyle(current > 0 ? .tujiAccumulation : .tujiInk3)
                        .contentTransition(.numericText())
                    Text("天")
                        .font(.tujiH2)
                        .foregroundStyle(.tujiInk)
                }
            }
            Spacer(minLength: 0)
            MascotFigure(
                pose: (self.streak?.todayCount ?? 0) > 0 ? .cheer : .wave,
                size: 88,
                grounding: .none
            )
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Today's points

    private var rewardCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            // One row while the sentence fits beside the button; the button
            // drops underneath once it doesn't (ja / en, large type) rather
            // than squeezing the sentence into a narrow column.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s3) {
                    self.rewardLabel
                    Spacer(minLength: Space.s2)
                    self.rewardAction
                }
                VStack(alignment: .leading, spacing: Space.s3) {
                    self.rewardLabel
                    self.rewardAction
                }
            }
            if let message = self.model.message {
                Text(verbatim: message)
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiAlert)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(.tujiPaper2)
    }

    private var rewardLabel: some View {
        HStack(spacing: Space.s3) {
            Image("CreditCan")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .foregroundStyle(.tujiInk)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(self.rewardTitle)
                    .font(.tujiBody(.strong))
                    .foregroundStyle(.tujiInk)
                if let detail = self.rewardDetail {
                    Text(detail)
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk2)
                }
            }
        }
    }

    private var rewardTitle: LocalizedStringKey {
        switch self.reward {
        case .hidden, .locked: "每日打卡點數"
        case .needsStudy: "今天還沒學習"
        case .claimable, .claimed: "今天已打卡"
        case .capped: "本月點數已領滿"
        }
    }

    private var rewardDetail: LocalizedStringKey? {
        switch self.reward {
        case .hidden: nil
        case let .locked(daily): "永久會員每天學習可領 \(daily) 點罐頭點數"
        case let .needsStudy(daily): "學一題就算打卡，可領 \(daily) 點"
        case let .claimable(points): "\(points) 點罐頭點數等你領取"
        case .claimed: "今天的點數已入帳，明天再來"
        case let .capped(cap): "每月最多 \(cap) 點，下個月再來"
        }
    }

    @ViewBuilder
    private var rewardAction: some View {
        switch self.reward {
        case .hidden, .capped:
            EmptyView()
        case .locked:
            self.pill("升級", primary: false) { self.presentPaywall() }
        case .needsStudy:
            self.pill("去學習", primary: true) { self.onStudy() }
        case let .claimable(points):
            self.pill("領取 +\(points)", primary: true) {
                Task {
                    await self.model.claim()
                    if self.model.reward(fallbackStudiedToday: true) == .claimed { self.claimedTick += 1 }
                }
            }
            .disabled(self.model.claiming)
        case .claimed:
            Image(systemName: "checkmark")
                .font(.tujiIcon(18, weight: .semibold))
                .foregroundStyle(.tujiAccumulation)
                .accessibilityLabel(Text("已領取"))
        }
    }

    private func pill(_ title: LocalizedStringKey, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.tujiBody(.strong))
                .foregroundStyle(.tujiInk)
                .lineLimit(1)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s2)
                .background(primary ? .tujiBrandPrimary : .tujiPaper)
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    // MARK: - Month

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text(verbatim: self.monthTitle)
                    .font(.tujiH3)
                    .foregroundStyle(.tujiInk)
                Spacer()
                self.monthButton("chevron.left", label: "上個月", enabled: self.model.canShowEarlier, offset: -1)
                self.monthButton("chevron.right", label: "下個月", enabled: self.model.canShowLater, offset: 1)
            }
            if self.model.calendarFailed {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("月曆暫時載入不了")
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk2)
                    Button("重試") { Task { await self.model.loadCalendar() } }
                        .font(.tujiBody(.strong))
                        .foregroundStyle(.tujiInk)
                }
            } else {
                StudyMonthGrid(
                    month: self.model.calendar,
                    firstWeekday: self.firstWeekday,
                    locale: self.settings.current.uiLanguage.locale
                )
            }
        }
    }

    private func monthButton(_ icon: String, label: LocalizedStringKey, enabled: Bool, offset: Int) -> some View {
        Button {
            Task { await self.model.showMonth(offset: offset) }
        } label: {
            Image(systemName: icon)
                .font(.tujiIcon(16, weight: .semibold))
                .foregroundStyle(enabled ? .tujiInk2 : .tujiInk3.opacity(0.4))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
    }

    private var firstWeekday: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = self.settings.current.uiLanguage.locale
        return calendar.firstWeekday
    }

    private var monthTitle: String {
        let month = self.model.calendar?.month ?? StudyMonthGrid.currentMonth()
        guard let (y, m) = MonthGrid.parse(month),
              let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: y, month: m, day: 15))
        else { return month }
        let f = DateFormatter()
        f.locale = self.settings.current.uiLanguage.locale
        f.setLocalizedDateFormatFromTemplate("yMMMM")
        return f.string(from: date)
    }
}

// MARK: - Grid

/// The month as squares. Before the first answer arrives it draws the current
/// month empty, so the sheet does not jump when the data lands.
struct StudyMonthGrid: View {
    let month: StudyCalendarMonth?
    let firstWeekday: Int
    let locale: Locale

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Space.s1), count: 7)

    /// YYYY-MM on the phone's calendar — the zone every request states.
    static func currentMonth(now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let c = calendar.dateComponents([.year, .month], from: now)
        return String(format: "%04d-%02d", c.year ?? 2026, c.month ?? 1)
    }

    var body: some View {
        let grid = MonthGrid(month: self.month?.month ?? Self.currentMonth(), firstWeekday: self.firstWeekday)
        let studied = Set(self.month?.studiedDays ?? [])
        VStack(spacing: Space.s2) {
            self.weekdayHeader
            LazyVGrid(columns: self.columns, spacing: Space.s1) {
                ForEach(Array((grid?.cells ?? []).enumerated()), id: \.offset) { _, day in
                    if let day, let grid {
                        let date = grid.date(day)
                        self.cell(
                            day: day,
                            studied: studied.contains(date),
                            today: date == self.month?.today,
                            future: self.month.map { date > $0.today } ?? false
                        )
                    } else {
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
    }

    private var weekdayHeader: some View {
        // Index-keyed: English's very-short symbols repeat ("S", "T").
        let f = DateFormatter()
        f.locale = self.locale
        let symbols = f.veryShortStandaloneWeekdaySymbols ?? ["日", "一", "二", "三", "四", "五", "六"]
        let start = self.firstWeekday - 1
        let labels = Array(symbols[start...] + symbols[..<start])
        return HStack(spacing: Space.s1) {
            ForEach(labels.indices, id: \.self) { i in
                Text(labels[i])
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func cell(day: Int, studied: Bool, today: Bool, future: Bool) -> some View {
        // The square is the shape, the number rides on it: a Text given an
        // aspect ratio sizes to its glyphs and the rows collapse.
        Rectangle()
            .fill(studied ? Color.tujiAccumulation : Color.clear)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Text("\(day)")
                    .font(.tujiBodySm(.strong))
                    .foregroundStyle(studied ? .tujiPaper : future ? .tujiInk3.opacity(0.5) : .tujiInk2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .overlay {
                if today { Rectangle().strokeBorder(.tujiCurrent, lineWidth: Border.bw2) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(day)"))
            .accessibilityValue(studied ? Text("已學習") : Text(verbatim: ""))
    }
}
