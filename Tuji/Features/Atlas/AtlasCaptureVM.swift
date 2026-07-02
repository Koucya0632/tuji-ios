// View model for 拍照快速新增 (AtlasCaptureView). Owns the whole
// upload → AI 識別 → 校正 → confirm pipeline state so the view stays
// presentation-only and the pipeline rules (candidate auto-apply, quota
// gating, confirm-payload assembly) are plain unit-testable code.
// Abandoning a capture is "throw the VM away" — the view swaps in a fresh
// instance instead of hand-clearing a dozen fields.

import Observation
import PhotosUI
import SwiftUI

@MainActor
@Observable
final class AtlasCaptureVM {
    enum Busy {
        case upload, recognize
    }

    // MARK: - Pipeline state

    private(set) var uploadedImage: AtlasImageSummary?
    private(set) var candidates: [AtlasCandidate] = []
    private(set) var selectedCandidateId: String?
    private(set) var busy: Busy?
    private(set) var errorMessage: String?
    private(set) var successMessage: String?
    /// The downscaled frame kept around to seed the 圖鑑 progress placeholder.
    private(set) var localThumbnail: UIImage?
    /// The last picked/cropped frame, retained so a failed upload (weak network)
    /// can be retried without re-picking the photo.
    private(set) var lastUploadData: Data?

    /// Each recognition mode (primary / escalate) runs at most once and its
    /// candidates are kept here — a re-run barely differs and just burns another
    /// AI call, so tapping a mode again re-shows its cached set for free.
    private var candidatesByMode: [AtlasRecognitionMode: [AtlasCandidate]] = [:]

    // MARK: - Correction form

    /// Only the two names are user-editable; primaryLabel / fineLabel /
    /// partOfSpeech / category stay populated from the AI candidate via
    /// apply(_:) and ride through on confirm without cluttering the UI.
    var lemma = ""
    var displayZhHant = ""
    private(set) var primaryLabel = ""
    private(set) var fineLabel = ""
    private(set) var partOfSpeech = "noun"
    private(set) var category = ""

    /// Raised on quota dead-ends (402, or a Free 高精度 tap) so the view can
    /// present the paywall instead of a raw error.
    var showPaywall = false

    private let store: AtlasStore

    init(store: AtlasStore = .shared) {
        self.store = store
    }

    // MARK: - Quota / entitlement gates

    /// At the tier's 自製圖鑑 capacity — capture is blocked until the user frees a
    /// slot or upgrades. Unknown entitlement resolves to "allow" (server enforces).
    var atCapacity: Bool {
        !AtlasQuotas.canCreateItem(self.store.entitlement)
    }

    var capacityMessage: String {
        guard let limit = self.store.entitlement?.atlasSlotsLimit else {
            return tujiLocalized("自製圖鑑已達上限，刪除一些後再新增。")
        }
        return self.isPro
            ? tujiLocalized("自製圖鑑已達上限（\(limit)），刪除一些後再新增。")
            : tujiLocalized("自製圖鑑已達免費上限（\(limit)），升級 Pro 可擴充，或刪除一些。")
    }

    /// Remaining ordinary AI recognitions this month; nil = unknown.
    var remainingPrimaryThisMonth: Int? {
        AtlasQuotas.remainingPrimaryAi(self.store.entitlement)
    }

    var isPro: Bool {
        self.store.entitlement?.isPro ?? false
    }

    /// 高精度 availability (Pro-only). A Free tap should route to the paywall
    /// instead of spending a call the server would 402.
    var precisionAvailable: Bool {
        AtlasQuotas.precisionAvailable(self.store.entitlement)
    }

    /// 確認並生成卡片 enabled: not busy and both editable names filled.
    var canSubmit: Bool {
        self.busy == nil
            && !self.lemma.trimmingCharacters(in: .whitespaces).isEmpty
            && !self.displayZhHant.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Pipeline

    /// Fresh tier / usage so capture gating and remaining-quota copy are current
    /// when the sheet opens, plus a rewarded-ad warm-up for Free users so the
    /// card-gen gate is instant.
    func prepareOnOpen() async {
        await self.store.refreshEntitlement()
        if self.store.entitlement?.adsRequiredForCardGeneration == true {
            Ads.rewarded.preload()
        }
    }

    /// Resolve a PhotosPicker selection to raw bytes for the crop step.
    /// Returns nil (and sets the error banner) when the item can't be read.
    func loadPhotoData(_ item: PhotosPickerItem) async -> Data? {
        self.errorMessage = nil
        self.successMessage = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw AtlasCaptureError.missingPhotoData
            }
            return data
        } catch {
            self.errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Upload one captured/picked frame, then immediately kick AI recognition so
    /// the flow feels one-shot.
    func handlePicked(data: Data) async {
        self.busy = .upload
        self.errorMessage = nil
        self.successMessage = nil
        // Retain the frame so a failed upload can be retried in place.
        self.lastUploadData = data
        do {
            let encoded = ImageDownscale.jpeg(from: data) ?? data
            self.localThumbnail = UIImage(data: encoded)
            let response = try await self.store.uploadImage(
                data: encoded,
                filename: "atlas-photo.jpg",
                mimeType: "image/jpeg"
            )
            self.uploadedImage = response.image
            self.lastUploadData = nil
            self.busy = nil
            // Candidates ride back with the upload (recognition runs inline
            // server-side) — no separate recognize round trip on the first pass.
            // Cache them so a later AI 識別 tap re-shows the same set for free.
            self.candidatesByMode[.primary] = response.candidates ?? []
            self.applyCandidates(response.candidates ?? [])
        } catch {
            self.busy = nil
            self.errorMessage = error.localizedDescription
        }
    }

    /// AI 識別 / 高精度 tap. A mode is recognized at most once; if we already
    /// have its candidates, re-show them for free rather than spending another
    /// AI call (the result barely changes on a re-run). An empty / failed result
    /// isn't treated as final, so it can still be retried.
    func requestRecognize(_ mode: AtlasRecognitionMode) {
        guard let image = self.uploadedImage else { return }
        if let cached = self.candidatesByMode[mode], !cached.isEmpty {
            self.applyCandidates(cached)
        } else {
            Task { await self.recognize(imageId: image.id, mode: mode) }
        }
    }

    /// Run recognition once for a mode and cache the result; repeat taps re-show
    /// the cache via `requestRecognize`.
    private func recognize(imageId: String, mode: AtlasRecognitionMode) async {
        self.busy = .recognize
        self.errorMessage = nil
        self.successMessage = nil
        defer { self.busy = nil }
        do {
            let response = try await self.store.recognize(imageId: imageId, mode: mode)
            self.candidatesByMode[mode] = response.candidates
            self.applyCandidates(response.candidates)
        } catch {
            // A 402 means the monthly AI quota is spent — send them to the paywall
            // rather than showing a raw error. Transient 429s stay as a message.
            if let apiError = error as? APIError, case .paymentRequired = apiError {
                self.showPaywall = true
            } else {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func applyCandidates(_ list: [AtlasCandidate]) {
        self.candidates = list.sorted { $0.rank < $1.rank }
        if let best = self.candidates.first(where: { $0.levelKind == .fine }) ?? self.candidates.first {
            self.apply(best)
        }
        self.successMessage = list.isEmpty
            ? tujiLocalized("沒有自動辨識到，請手動填寫或按「AI 識別」重試。")
            : tujiLocalized("已辨識，確認名稱後即可生成卡片。")
    }

    /// `overwrite` is true when the user taps a candidate chip — their explicit
    /// choice replaces the name fields. It's false for the auto-apply after
    /// recognition, which only fills empty fields so it never clobbers a name
    /// the user already typed.
    func apply(_ candidate: AtlasCandidate, overwrite: Bool = false) {
        self.selectedCandidateId = candidate.id
        if candidate.levelKind == .fine {
            self.fineLabel = candidate.label
        } else {
            self.primaryLabel = candidate.label
        }
        if overwrite || self.lemma.isEmpty { self.lemma = candidate.label }
        if overwrite || self.displayZhHant.isEmpty {
            self.displayZhHant = candidate.zhHant ?? candidate.label
        }
    }

    /// Payload assembled from the correction form. Split from submit() so the
    /// fallback rules (lemma stands in for a missing primaryLabel, blank
    /// optionals drop to nil) stay unit-testable.
    var confirmPayload: AtlasConfirmPayload {
        AtlasConfirmPayload(
            selectedCandidateId: self.selectedCandidateId,
            targetLanguage: nil,
            primaryLabel: self.primaryLabel.isEmpty ? self.lemma : self.primaryLabel,
            fineLabel: self.fineLabel.isEmpty ? nil : self.fineLabel,
            lemma: self.lemma,
            displayZhHant: self.displayZhHant,
            partOfSpeech: self.partOfSpeech.isEmpty ? nil : self.partOfSpeech,
            category: self.category.isEmpty ? nil : self.category
        )
    }

    /// Hand the heavy tail (confirm → createCards → sync) to the background
    /// queue. Free watches a rewarded ad first; Pro skips it (that's the "無廣告"
    /// benefit) — best-effort, never blocks the card (pricing plan §3). Returns
    /// once the job is enqueued so the caller can dismiss the cover; the 圖鑑
    /// page shows a 製作中 placeholder until the queue finishes.
    func submit() async {
        guard let image = self.uploadedImage else { return }
        if self.store.entitlement?.adsRequiredForCardGeneration == true {
            await Ads.rewarded.showRewardedAd()
        }
        AtlasCaptureQueue.shared.enqueue(
            imageId: image.id,
            payload: self.confirmPayload,
            thumbnail: self.localThumbnail
        )
    }

    /// Best-effort delete of the just-uploaded image when the user abandons this
    /// capture (X / 換一張), so an unconfirmed photo is never kept in 自制圖鑑.
    func discardUploadedImage() {
        guard let image = self.uploadedImage else { return }
        let store = self.store
        Task { try? await store.deleteImage(id: image.id) }
    }

    func candidateLabel(_ candidate: AtlasCandidate) -> String {
        let pct = Int((candidate.confidence * 100).rounded())
        if let zh = candidate.zhHant, !zh.isEmpty {
            return "\(candidate.label) · \(zh) · \(pct)%"
        }
        return "\(candidate.label) · \(pct)%"
    }
}

enum AtlasCaptureError: LocalizedError {
    case missingPhotoData

    var errorDescription: String? {
        switch self {
        case .missingPhotoData: tujiLocalized("讀取照片失敗")
        }
    }
}
