// Where one capture sits, in the single vocabulary every screen reads.
//
// There used to be two client-side answers to that question and nothing
// relating them. 生成佇列 kept a `Stage` (confirming / creating / enriching /
// done / failed) that the 卡片 grid rendered; the server's `AtlasImageStatus`
// (uploaded / processing / … / cards_ready) was what 圖鑑管理 rendered. Both
// describe the same photo at the same moment, so a capture in flight read
// 「生成中」 in one place and 「已上傳」 in the other — and a job restored after
// an app kill announced 「生成中」 from the start even when its own `itemId`
// checkpoint proved the server had already confirmed it.
//
// `CONTEXT.md` is careful to keep `AtlasImageStatus` (pipeline status) apart
// from `AtlasReviewStatus` (the moderation gate) because conflating them once
// put 未完成 next to 已完成. This is the third vocabulary, folded in: the
// in-flight job wins, because a job that is still running knows something the
// row it has not written yet cannot.

import Foundation

/// Why a capture job stopped, in the only two kinds a screen must tell apart:
/// one another attempt could fix, and one it could not.
/// `Hashable` because `AtlasShelfRow` carries one and is itself `Hashable` —
/// SwiftUI selection and `ForEach` identity both need it.
enum CaptureFailure: Hashable {
    /// The account is out of 自製圖鑑 slots. 重試 can only fail the same way —
    /// the user has to free a slot or upgrade. Carries the server's own copy
    /// when it sent some.
    case atCapacity(String?)
    /// Network, server, decode. Worth another attempt.
    case transient

    /// The server answers a spent quota with 402, and the capture flow already
    /// routes that to the paywall during 識別. After enqueue it used to be
    /// flattened into one untyped failure, so a dead end wore a retry's costume.
    init(_ error: Error) {
        if let api = error as? APIError, case let .paymentRequired(message) = api {
            self = .atCapacity(message)
        } else {
            self = .transient
        }
    }

    var isRetryable: Bool {
        if case .transient = self { return true }
        return false
    }
}

enum CaptureProgress: Hashable {
    /// confirm → createCards. The fraction is real work completed, not a sweep.
    case generating(Double)
    /// The card exists; its detail page is being filled in.
    case enriching(Double)
    case ready
    case failed(CaptureFailure)

    /// What a screen says about this capture. One home for the copy, so the
    /// grid tile and the 圖鑑管理 row cannot disagree about one photo.
    var label: String {
        switch self {
        case .generating: tujiLocalized("生成中")
        case .enriching: tujiLocalized("補充詳情中")
        case .ready: tujiLocalized("已加入圖鑑")
        case let .failed(failure):
            switch failure {
            case let .atCapacity(message):
                message ?? tujiLocalized("自製圖鑑已達上限，刪除一些後再試。")
            case .transient: tujiLocalized("生成失敗，點一下重試")
            }
        }
    }

    /// The determinate fraction, or nil where there is nothing honest to show.
    var fraction: Double? {
        switch self {
        case let .generating(value), let .enriching(value): value
        case .ready: 1
        case .failed: nil
        }
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    /// Only a transient failure offers 重試. Offering it for a spent quota is
    /// offering the impossible.
    var canRetry: Bool {
        if case let .failed(failure) = self { return failure.isRetryable }
        return false
    }
}
