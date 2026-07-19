// Single source of truth for the signed-in user's settings. Lazy-loaded
// on the first SettingsView appearance; subsequent reads return the
// in-memory `current` snapshot.
//
// Edits apply immediately: SettingsView / pickers mutate `current` through
// `update(_:)` (or a `binding(_:)`), which updates the in-memory value right
// away and debounces a POST /api/users/settings in the background. There's
// no draft / save-button / discard step — what you tap is what's applied.

import Observation
import OSLog
import SwiftUI

/// UserDefaults key mirroring `SettingsStore.current.uiLang` for nonisolated reads.
nonisolated let tujiUILangDefaultsKey = "tuji.ui.lang"

private nonisolated let tujiLProjLock = NSLock()
private nonisolated(unsafe) var tujiLProjCache: [String: Bundle] = [:]

/// The compiled `.lproj` bundle for a uiLang code, cached. Falls back to the
/// main bundle (whose lookups yield the zh-Hant source strings) for unknown or
/// missing codes.
private nonisolated func tujiLProjBundle(_ code: String) -> Bundle {
    tujiLProjLock.lock()
    defer { tujiLProjLock.unlock() }
    if let cached = tujiLProjCache[code] { return cached }
    let bundle: Bundle =
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
        let lproj = Bundle(path: path) {
            lproj
        } else {
            .main
        }
    tujiLProjCache[code] = bundle
    return bundle
}

/// Localize a zh-Hant source string into the user's chosen in-app UI language.
///
/// The app overrides only the SwiftUI *environment* locale (see `TujiApp`), not
/// the process locale. Crucially, `String(localized:locale:)`'s `locale` param
/// only affects interpolation formatting — it does NOT choose which strings
/// table is loaded, which still follows the process language. So we resolve the
/// explicit `.lproj` bundle for the uiLang and look the key up there. Reads the
/// mirrored uiLang from UserDefaults (thread-safe, usable off the main actor).
nonisolated func tujiLocalized(_ key: String.LocalizationValue) -> String {
    let code = UserDefaults.standard.string(forKey: tujiUILangDefaultsKey)
        ?? UILanguage.deviceDefault.rawValue
    return tujiLocalized(key, lang: code)
}

/// As `tujiLocalized`, but for an explicitly supplied uiLang code (e.g. a draft
/// that carries its own language rather than the live app setting).
nonisolated func tujiLocalized(_ key: String.LocalizationValue, lang code: String) -> String {
    String(localized: key, bundle: tujiLProjBundle(code), locale: Locale(identifier: code))
}

@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    private(set) var current: UserSettings = .default
    private(set) var loading: Bool = false
    private(set) var saving: Bool = false
    private(set) var lastError: Error?

    private let log = Logger(subsystem: "app.tuji.ios", category: "settings")
    /// True once the first server load has completed. TodayView reads this to
    /// avoid flashing the "pick themes" empty state before settings arrive.
    private(set) var hasLoaded: Bool = false
    private var saveTask: Task<Void, Never>?
    private let repository: UserRepository

    /// Coalesce rapid changes (e.g. toggling back and forth) into one POST.
    private let saveDebounce: Duration = .milliseconds(400)

    private let learningDirectionKey = "tuji.learning.direction"

    private init(repository: UserRepository = LiveUserRepository.shared) {
        self.repository = repository
        // Seed the learning target from the persisted choice so the launch-time
        // word preload (gated behind the splash) fetches the right language
        // before the server `load()` completes. Without this, `current` stays
        // at `.default` (.zhEn) on every cold start, so a zh-ja learner who
        // skipped the picker briefly preloads English words behind the splash
        // and only swaps once settings arrive.
        if let stored = UserDefaults.standard.string(forKey: self.learningDirectionKey),
           let direction = LearningDirection(rawValue: stored)
        {
            self.current.learningDirection = direction
        }
        // Same idea for the UI language: `.default` starts at the *device*
        // language (right for a first run), so re-seed from the mirror to keep
        // a returning user's stored choice from flashing the device language
        // before the server load() lands.
        if let storedLang = UserDefaults.standard.string(forKey: tujiUILangDefaultsKey) {
            self.current.uiLang = UILanguage(code: storedLang).rawValue
        }
    }

    /// Returns immediately on subsequent calls; only the first call hits
    /// the network.
    func loadIfNeeded() async {
        guard !self.hasLoaded else { return }
        await self.load()
    }

    func load() async {
        self.loading = true
        self.lastError = nil
        defer { self.loading = false }
        do {
            var settings = try await self.repository.loadSettings()
            // Before first-run setup completes, the server row is boilerplate
            // (uiLang defaults to zh-Hant), not a choice the user made. Keep
            // the locally detected device language so a ja/en-device user's
            // onboarding doesn't flip to Chinese mid-setup — SetupView then
            // persists the surviving value.
            if case let .signedIn(user) = AuthService.shared.state,
               !OnboardingState.shared.setupDone(for: user.id)
            {
                settings.uiLang = self.current.uiLang
            }
            let directionChanged =
                self.current.learningDirection != settings.learningDirection
            self.current = settings
            UserDefaults.standard.set(settings.uiLang, forKey: tujiUILangDefaultsKey)
            OnboardingState.shared.learningDirection = settings.learningDirection
            self.hasLoaded = true
            if directionChanged {
                WordsStore.shared.invalidate()
                MasteryStore.shared.invalidate()
                ProgressStore.shared.invalidate()
                StudyStatsStore.shared.invalidate()
                async let wordsLoad: Void = WordsStore.shared.reload()
                async let masteryLoad: Void = MasteryStore.shared.reload()
                async let progressLoad: Void = ProgressStore.shared.reload()
                async let statsLoad: Void = StudyStatsStore.shared.reload()
                _ = await (wordsLoad, masteryLoad, progressLoad, statsLoad)
            }
            self.log.info("settings loaded")
        } catch {
            self.lastError = error
            self.log.error("settings load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Adopt settings that were already persisted server-side by the caller
    /// (first-run SetupView POSTs via UserRepository directly). Seeds `current`
    /// so downstream readers — the study-queue params, Today's theme grid —
    /// see the fresh choices immediately instead of waiting for the next
    /// server load().
    func adoptPersisted(_ settings: UserSettings) {
        self.current = settings
        self.hasLoaded = true
        UserDefaults.standard.set(settings.uiLang, forKey: tujiUILangDefaultsKey)
    }

    // MARK: - Immediate edits

    /// Mutate the live settings and persist automatically. The change is
    /// applied to `current` synchronously so the UI reflects it at once; the
    /// network write is debounced so quick successive edits collapse into a
    /// single POST.
    func update(_ mutate: (inout UserSettings) -> Void) {
        var next = self.current
        mutate(&next)
        guard next != self.current else { return }
        let uiLangChanged = next.uiLang != self.current.uiLang
        self.current = next
        UserDefaults.standard.set(next.uiLang, forKey: tujiUILangDefaultsKey)
        self.scheduleSave()
        // Static UI chrome switches live via the environment locale, but the
        // category names (`nameZh`) and word Chinese (`chinese`) are localized
        // server-side and cached per uiLang. Refetch them so 圖鑑 themes and
        // word cards follow the interface language too. No `invalidate()`: the
        // dataset is identical (only Traditional vs Simplified differs), so the
        // old text stays on screen until the new payload lands — no empty flash.
        if uiLangChanged {
            Task {
                async let categories: Void = CategoriesStore.shared.reload()
                async let words: Void = WordsStore.shared.reload()
                _ = await (categories, words)
            }
        }
    }

    /// Applies the learning target immediately. First-launch and guest flows
    /// use `persist: false`; signed-in settings changes sync to the server.
    func setLearningDirection(_ direction: LearningDirection, persist: Bool) {
        guard self.current.learningDirection != direction else { return }
        self.current.learningDirection = direction
        UserDefaults.standard.set(direction.rawValue, forKey: self.learningDirectionKey)
        if persist {
            self.scheduleSave()
        }
    }

    /// Two-way binding for SwiftUI controls (e.g. Toggle). Reading returns the
    /// live value; writing routes through `update(_:)` so it auto-saves.
    func binding<Value>(_ keyPath: WritableKeyPath<UserSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.current[keyPath: keyPath] },
            set: { newValue in self.update { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func scheduleSave() {
        self.saveTask?.cancel()
        let snapshot = self.current
        let debounce = self.saveDebounce
        self.saveTask = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            if Task.isCancelled { return }
            await self?.persist(snapshot)
        }
    }

    private func persist(_ snapshot: UserSettings) async {
        self.saving = true
        self.lastError = nil
        defer { self.saving = false }
        do {
            try await self.repository.saveSettings(snapshot)
            self.log.info("settings saved")
        } catch {
            self.lastError = error
            self.log.error("settings save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
