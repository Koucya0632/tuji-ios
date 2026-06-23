// Client-side "next review in …" formatting for the 圖鑑 grid, plus a tolerant
// ISO8601 parser for the schedule timestamps.
//
// The countdown strings mirror the backend `humanizeWhen` / `humanizeInterval`
// (lib/srs.ts) verbatim so the app and web read the same. They're zh-only on
// the backend too, so we keep them as plain (non-localized) literals here.
//
// Why parse ISO by hand: APIClient's JSONDecoder uses `.iso8601`, whose default
// ISO8601DateFormatter rejects fractional seconds — but the server's
// `Date.toISOString()` always emits `.SSS`. Decoding nextReviewAt as a Date
// would throw and sink the whole mastery payload, so we decode it as a String
// and parse it here, tolerating both forms.

import Foundation

enum ReviewSchedule {
    /// Due now or already past.
    static func isOverdue(_ date: Date, now: Date = .now) -> Bool {
        date <= now
    }

    /// "復習期" when due, else a relative countdown ("3 天後", "約 2 週後", …).
    static func countdownLabel(until date: Date, now: Date = .now) -> String {
        if self.isOverdue(date, now: now) { return "復習期" }
        return self.humanizeInterval(days: date.timeIntervalSince(now) / 86_400)
    }

    /// Port of lib/srs.ts `humanizeInterval`.
    private static func humanizeInterval(days: Double) -> String {
        if days < 1 {
            let mins = Int((days * 24 * 60).rounded())
            if mins < 60 { return "\(mins) 分鐘後" }
            let hours = Int((Double(mins) / 60).rounded())
            return "\(hours) 小時後"
        }
        if days < 7 { return "\(Int(days.rounded())) 天後" }
        if days < 30 { return "約 \(Int((days / 7).rounded())) 週後" }
        if days < 365 { return "約 \(Int((days / 30).rounded())) 個月後" }
        return String(format: "約 %.1f 年後", days / 365)
    }

    // MARK: - ISO parsing

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain = ISO8601DateFormatter()

    /// Parse an ISO8601 timestamp with or without fractional seconds.
    static func parseISO(_ string: String) -> Date? {
        self.isoFractional.date(from: string) ?? self.isoPlain.date(from: string)
    }
}
