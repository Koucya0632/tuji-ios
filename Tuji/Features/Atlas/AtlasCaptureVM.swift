// View model for 拍照快速新增 (AtlasCaptureView). Owns the whole
// upload → AI 識別 → 校正 → confirm pipeline state so the view stays
// presentation-only and the pipeline rules (candidate auto-apply, quota
// gating, confirm-payload assembly) are plain unit-testable code.
// Abandoning a capture is "throw the VM away" — the view swaps in a fresh
// instance instead of hand-clearing a dozen fields.
//
// Every method that does work is `async` and the View owns the `Task`. This was
// the odd one out among the atlas view models: `requestRecognize` was
// synchronous and spawned a `Task {}` it dropped on the floor, so the rule that
// protects the user's paid AI allowance — each mode recognises at most once, an
// incomplete cache gets exactly one repair — could not be awaited, and therefore
// was not tested. (`submit()` was the mirror image: `async`, awaiting nothing.)

import Observation
import SwiftUI
import UIKit

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
    /// Which recognition depth produced the on-screen candidates, so the mode
    /// buttons can show a selected state. nil until the first recognition runs.
    private(set) var activeMode: AtlasRecognitionMode?
    private(set) var busy: Busy?
    private(set) var errorMessage: String?
    private(set) var successMessage: String?
    /// The frame kept around to seed the 圖鑑 progress placeholder. Parking the
    /// bytes for a retry is `ImageIntake`'s job, not a second copy here.
    private(set) var localThumbnail: UIImage?

    /// Each recognition mode (primary / escalate) runs at most once and its
    /// candidates are kept here — a re-run barely differs and just burns another
    /// AI call, so tapping a mode again re-shows its cached set for free.
    private var candidatesByMode: [AtlasRecognitionMode: [AtlasCandidate]] = [:]
    /// An incomplete legacy cache gets one explicit repair attempt per mode.
    /// If that provider still cannot supply a gloss, later taps reuse the result
    /// instead of repeatedly spending the user's AI allowance.
    private var glossRepairAttemptedModes: Set<AtlasRecognitionMode> = []

    // MARK: - Correction form

    /// Only the two names are user-editable; primaryLabel / fineLabel /
    /// partOfSpeech / category stay populated from the AI candidate via
    /// apply(_:) and ride through on confirm without cluttering the UI.
    var lemma = ""
    var displayZhHant = ""
    /// The name field the user actually edits when the UI is ja/en (their
    /// own-language gloss). displayZhHant still rides through as the Chinese
    /// base column. Empty (and unused) for Chinese UIs.
    var displayGloss = ""
    private(set) var primaryLabel = ""
    private(set) var fineLabel = ""
    private(set) var partOfSpeech = "noun"
    private(set) var category = ""

    /// Raised on quota dead-ends (402, or a Free 高精度 tap) so the view can
    /// present the paywall instead of a raw error.
    var showPaywall = false

    private let store: AtlasStore
    /// Quota *numbers* come from `store.entitlement`; the Pro/Free *verdict*
    /// comes from here, so 拍照 cannot disagree with 設定 about who is Pro.
    private let entitlement: any EffectiveEntitlementReading
    /// The 生成佇列 the confirmed capture is handed to. Injected rather than
    /// reached statically, so the seam the store arrives on survives the handoff.
    private let queue: AtlasCaptureQueue
    /// `{ uiLang, learningDirection }` — the read seam `SettingsStore` conforms
    /// to. Read live at call time: an in-app language switch must take effect on
    /// the next question asked, not on the next VM.
    private let language: any LanguageContext

    init(
        store: AtlasStore = .shared,
        entitlement: (any EffectiveEntitlementReading)? = nil,
        queue: AtlasCaptureQueue = .shared,
        language: any LanguageContext = SettingsStore.shared
    ) {
        self.store = store
        // Defaulted from the same store the VM was handed, so a test that
        // stands the VM up over a fake store gets a matching verdict for free.
        self.entitlement = entitlement ?? LiveEffectiveEntitlement(atlas: store)
        self.queue = queue
        self.language = language
    }

    // MARK: - Quota / entitlement gates

    /// 自製圖鑑 room, counting the captures 生成佇列 is still working on. The
    /// server's snapshot cannot know about those — it counts confirmed items —
    /// so a gate reading it alone let a second capture through at capacity − 1.
    var capacity: AtlasCapacityReadout {
        AtlasCapacityReadout.of(self.store.entitlement, inFlight: self.queue.inFlightCount)
    }

    /// At the tier's 自製圖鑑 capacity — capture is blocked until the user frees a
    /// slot or upgrades. Unknown entitlement resolves to "allow" (server enforces).
    var atCapacity: Bool {
        !self.capacity.canCapture
    }

    var capacityMessage: String {
        self.capacity.message(isPro: self.isPro)
    }

    /// Remaining ordinary AI recognitions this month; nil = unknown.
    var remainingPrimaryThisMonth: Int? {
        AtlasQuotas.remainingPrimaryAi(self.store.entitlement)
    }

    /// The tier's monthly ordinary-AI allowance (Free 30 / Pro 500); nil = unknown.
    var primaryLimitPerMonth: Int? {
        self.store.entitlement?.primaryAiSoftLimitMonthly
    }

    var isPro: Bool {
        self.entitlement.isPro
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

    // MARK: - Correction form shape

    /// Which second field the form asks for. One module answers this and the
    /// gloss-repair question below, so the two cannot disagree about the same
    /// {UILanguage × TargetLanguage} cell.
    var secondField: CaptureSecondField {
        CaptureCorrectionFields.second(
            ui: UILanguage(code: self.language.uiLang),
            target: self.language.learningDirection.targetLanguage
        )
    }

    // MARK: - Pipeline

    /// Fresh tier / usage so capture gating and remaining-quota copy are current
    /// when the sheet opens.
    func prepareOnOpen() async {
        await self.store.refreshEntitlement()
    }

    /// Upload one frame the intake has already cropped and encoded, then
    /// immediately kick AI recognition so the flow feels one-shot.
    func handlePicked(data: Data) async {
        self.busy = .upload
        self.errorMessage = nil
        self.successMessage = nil
        do {
            self.localThumbnail = UIImage(data: data)
            let response = try await self.store.uploadImage(
                data: data,
                filename: "atlas-photo.jpg",
                mimeType: "image/jpeg"
            )
            self.uploadedImage = response.image
            self.busy = nil
            // Candidates ride back with the upload (recognition runs inline
            // server-side) — no separate recognize round trip on the first pass.
            // Cache them so a later 普通識別 tap re-shows the same set for free.
            self.candidatesByMode[.primary] = response.candidates ?? []
            self.applyCandidates(response.candidates ?? [], mode: .primary)
        } catch {
            self.busy = nil
            self.errorMessage = error.localizedDescription
        }
    }

    /// 普通識別 / 高精度識別 tap. A mode is recognized at most once; if we already
    /// have its candidates, re-show them for free rather than spending another
    /// AI call (the result barely changes on a re-run). An empty / failed result
    /// isn't treated as final, so it can still be retried.
    func requestRecognize(_ mode: AtlasRecognitionMode) async {
        guard let image = self.uploadedImage else { return }
        if let cached = self.candidatesByMode[mode], !cached.isEmpty {
            if self.needsGlossRefresh(cached), !self.glossRepairAttemptedModes.contains(mode) {
                self.glossRepairAttemptedModes.insert(mode)
                await self.recognize(imageId: image.id, mode: mode)
            } else {
                self.applyCandidates(cached, mode: mode)
            }
            return
        }
        await self.recognize(imageId: image.id, mode: mode)
    }

    /// Candidates saved by older upload responses may have their target label
    /// but no UI-language meaning. Let an explicit tap repair that incomplete
    /// cache instead of showing it forever.
    private func needsGlossRefresh(_ candidates: [AtlasCandidate]) -> Bool {
        guard CaptureCorrectionFields.needsGloss(
            ui: UILanguage(code: self.language.uiLang),
            target: self.language.learningDirection.targetLanguage
        )
        else { return false }
        return candidates.contains { candidate in
            candidate.gloss?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
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
            self.applyCandidates(response.candidates, mode: mode)
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

    func applyCandidates(_ list: [AtlasCandidate], mode: AtlasRecognitionMode) {
        self.activeMode = mode
        self.candidates = list.sorted { $0.rank < $1.rank }
        if let best = self.candidates.first(where: { $0.levelKind == .fine }) ?? self.candidates.first {
            self.apply(best)
        }
        // No "已辨識…" success banner — only surface the empty-result guidance so
        // the user knows to fill the fields in manually.
        self.successMessage = list.isEmpty
            ? tujiLocalized("沒有自動辨識到，請手動填寫或按「普通識別」重試。")
            : nil
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
        // The ja/en gloss the user edits, only when the model returned one
        // (cross-language capture: UI language ≠ target). No zh fallback — a
        // Chinese value must never land in display_ja/en; monolingual and
        // Chinese-UI captures leave this empty so confirm sends nil.
        if let gloss = candidate.gloss, overwrite || self.displayGloss.isEmpty {
            self.displayGloss = gloss
        }
        self.suggestion = Suggestion(
            lemma: self.lemma,
            zhHant: self.displayZhHant,
            gloss: self.displayGloss
        )
    }

    /// What the last applied candidate left in each field, so the correction
    /// form can mark a value as the model's guess rather than the user's.
    ///
    /// Held as values and compared, not as "has the user typed here" flags: a
    /// field the user edited and then changed back really is the model's
    /// suggestion again, and an edit-event flag would keep claiming otherwise.
    struct Suggestion: Equatable {
        var lemma: String
        var zhHant: String
        var gloss: String
    }

    private(set) var suggestion: Suggestion?

    enum SuggestedField {
        case lemma, zhHant, gloss
    }

    func isStillSuggested(_ field: SuggestedField) -> Bool {
        guard let s = self.suggestion else { return false }
        return switch field {
        case .lemma: !s.lemma.isEmpty && s.lemma == self.lemma
        case .zhHant: !s.zhHant.isEmpty && s.zhHant == self.displayZhHant
        case .gloss: !s.gloss.isEmpty && s.gloss == self.displayGloss
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
            displayGloss: self.displayGloss.isEmpty ? nil : self.displayGloss,
            partOfSpeech: self.partOfSpeech.isEmpty ? nil : self.partOfSpeech,
            category: self.category.isEmpty ? nil : self.category
        )
    }

    /// Hand the heavy tail (confirm → createCards → sync) to 生成佇列 and return.
    /// The caller dismisses the cover immediately; the 圖鑑 page shows a 生成中
    /// placeholder until the queue finishes.
    ///
    /// Not `async`: it was, and it awaited nothing — the work it commits outlives
    /// the sheet by design, and saying `await` about it claimed otherwise.
    func submit() {
        guard let image = self.uploadedImage else { return }
        self.queue.enqueue(
            imageId: image.id,
            payload: self.confirmPayload,
            thumbnail: self.localThumbnail
        )
    }

    /// Best-effort delete of the just-uploaded image when the user abandons this
    /// capture (X / 換一張), so an unconfirmed photo is never kept in 自制圖鑑.
    func discardUploadedImage() async {
        guard let image = self.uploadedImage else { return }
        try? await self.store.deleteImage(id: image.id)
    }

    /// Non-blocking heads-up when an existing custom word already uses this
    /// lemma (case/whitespace-insensitive). The user can still submit a
    /// second card on purpose (e.g. a different specimen of the same word),
    /// but shouldn't be left guessing why 圖鑑 shows "Flower" twice.
    var duplicateLemmaWarning: String? {
        let trimmed = self.lemma.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let exists = self.store.items.contains {
            $0.lemma.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(trimmed) == .orderedSame
        }
        return exists ? tujiLocalized("你已經有一張「\(trimmed)」的卡片，這會再新增一張。") : nil
    }

    func candidateLabel(_ candidate: AtlasCandidate) -> String {
        let pct = Int((candidate.confidence * 100).rounded())
        // Cross-language ja/en captures carry the interface-language meaning
        // in `gloss`; Chinese captures have no gloss and fall back to zhHant.
        let meaning = [candidate.gloss, candidate.zhHant]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        if let meaning {
            return "\(candidate.label) · \(meaning) · \(pct)%"
        }
        return "\(candidate.label) · \(pct)%"
    }
}
