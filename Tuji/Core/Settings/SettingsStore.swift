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
    @ObservationIgnored private var latestRequestedContext: LoadContext?
    @ObservationIgnored private var loadedContext: LoadContext?
    @ObservationIgnored private var inFlight: [LoadContext: LoadFlight] = [:]
    private var saveTask: Task<Void, Never>?
    private let repository: UserRepository
    private let defaults: UserDefaults
    private let signedInUserProvider: @MainActor () -> SessionUser?
    /// What a 學習語言 change costs. This store is the only place the direction
    /// can change, so it is the only place that has to notice — see
    /// LearningDirectionRefresh.swift for why the callers stopped saying.
    private let directionRefresh: LearningDirectionRefreshing
    private let communityCategoryMigration = CommunityStudyCategoryMigration()
    private let signposter = OSSignposter(
        subsystem: "app.tuji.ios",
        category: "settings"
    )

    private struct LoadContext: Hashable {
        let userID: UUID?
    }

    private struct LoadFlight {
        let id: UUID
        let task: Task<Void, Never>
    }

    /// Coalesce rapid changes (e.g. toggling back and forth) into one POST.
    private let saveDebounce: Duration = .milliseconds(400)

    private let learningDirectionKey = "tuji.learning.direction"

    init(
        repository: UserRepository = LiveUserRepository.shared,
        defaults: UserDefaults = .standard,
        signedInUserProvider: @escaping @MainActor () -> SessionUser? = {
            if case let .signedIn(user) = AuthService.shared.state {
                user
            } else {
                nil
            }
        },
        directionRefresh: LearningDirectionRefreshing = LiveLearningDirectionRefresher()
    ) {
        self.repository = repository
        self.defaults = defaults
        self.signedInUserProvider = signedInUserProvider
        self.directionRefresh = directionRefresh
        // Seed the learning target from the persisted choice so the launch-time
        // word preload (gated behind the splash) fetches the right language
        // before the server `load()` completes. Without this, `current` stays
        // at `.default` (.zhEn) on every cold start, so a zh-ja learner who
        // skipped the picker briefly preloads English words behind the splash
        // and only swaps once settings arrive.
        if let stored = defaults.string(forKey: self.learningDirectionKey),
           let direction = LearningDirection(rawValue: stored)
        {
            self.current.learningDirection = direction
        }
        // Same idea for the UI language: `.default` starts at the *device*
        // language (right for a first run), so re-seed from the mirror to keep
        // a returning user's stored choice from flashing the device language
        // before the server load() lands.
        if let storedLang = defaults.string(forKey: tujiUILangDefaultsKey) {
            self.current.uiLang = UILanguage(code: storedLang).rawValue
        }
    }

    /// Returns immediately on subsequent calls; only the first call hits
    /// the network.
    func loadIfNeeded() async {
        await self.loadIfNeeded(for: self.signedInUserProvider()?.id)
    }

    /// Settings belong to an account, not the process. Keying the flight by
    /// user id prevents a completed load for account A from satisfying account
    /// B after an in-process sign-out/sign-in transition.
    func loadIfNeeded(for userID: UUID?) async {
        let context = LoadContext(userID: userID)
        guard self.loadedContext != context || !self.hasLoaded else { return }
        await self.load(for: context)
    }

    /// Explicit reloads remain possible, but concurrent callers always join
    /// the same server request. Launch invokes this only after authentication
    /// resolves, so auth-dependent reconciliation observes a stable user.
    func load() async {
        await self.load(for: LoadContext(userID: self.signedInUserProvider()?.id))
    }

    private func load(for context: LoadContext) async {
        self.latestRequestedContext = context
        if self.loadedContext != context {
            self.hasLoaded = false
        }
        self.loading = true
        self.lastError = nil

        if let flight = self.inFlight[context] {
            await flight.task.value
            return
        }

        let flightID = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad(for: context, flightID: flightID)
        }
        self.inFlight[context] = LoadFlight(id: flightID, task: task)
        await task.value

        if self.inFlight[context]?.id == flightID {
            self.inFlight[context] = nil
        }
        self.refreshLoadingState()
    }

    private func performLoad(for context: LoadContext, flightID: UUID) async {
        let signpostID = self.signposter.makeSignpostID()
        let interval = self.signposter.beginInterval("settings-load", id: signpostID)
        let result: Result<UserSettings, Error>
        do {
            result = try await .success(self.repository.loadSettings())
        } catch {
            result = .failure(error)
        }
        self.signposter.endInterval("settings-load", interval)

        guard self.latestRequestedContext == context,
              self.inFlight[context]?.id == flightID
        else { return }

        switch result {
        case var .success(settings):
            // Before first-run setup completes, the server row is boilerplate
            // (uiLang / learningDirection defaults), not a choice the user
            // made. Keep both local choices so a first-time learner cannot be
            // flipped back to zh-Hant or zh-en while Setup is on screen. When
            // no direction has been selected yet, leave OnboardingState nil so
            // RootView still presents the language picker.
            let setupDone = context.userID.map {
                OnboardingState.shared.setupDone(for: $0)
            } ?? true
            settings = Self.reconcileServerSettings(
                settings,
                current: self.current,
                selectedDirection: OnboardingState.shared.learningDirection,
                setupDone: setupDone
            )
            var migrationUserID: UUID?
            var migrationNeedsSave = false
            if let userID = context.userID,
               OnboardingState.shared.setupDone(for: userID),
               !self.communityCategoryMigration.hasApplied(for: userID)
            {
                let migrated = self.communityCategoryMigration.migrated(settings)
                migrationUserID = userID
                migrationNeedsSave = migrated != settings
                settings = migrated
            }
            let directionChanged =
                self.current.learningDirection != settings.learningDirection
            self.current = settings
            self.defaults.set(settings.uiLang, forKey: tujiUILangDefaultsKey)
            if setupDone {
                OnboardingState.shared.learningDirection = settings.learningDirection
            }
            self.loadedContext = context
            self.hasLoaded = true
            if directionChanged {
                // Detached so the reloads never extend the signed-in launch gate;
                // `.serverDisagreed` is what keeps the catalog reload out of them.
                Task { await self.directionRefresh.refresh(after: .serverDisagreed) }
            }
            if let migrationUserID {
                if migrationNeedsSave {
                    do {
                        try await self.repository.saveSettings(settings)
                        self.communityCategoryMigration.markApplied(for: migrationUserID)
                        self.log.info("community study category migration saved")
                    } catch {
                        // Leave the marker unset so the migration retries on a
                        // later launch instead of silently losing the server update.
                        if self.latestRequestedContext == context,
                           self.inFlight[context]?.id == flightID
                        {
                            self.lastError = error
                        }
                        self.log.error(
                            "community study category migration failed: \(error.localizedDescription, privacy: .public)"
                        )
                    }
                } else {
                    self.communityCategoryMigration.markApplied(for: migrationUserID)
                }
            }
            self.log.info("settings loaded")
        case let .failure(error):
            self.lastError = error
            self.log.error("settings load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func refreshLoadingState() {
        guard let latestRequestedContext else {
            self.loading = false
            return
        }
        self.loading = self.inFlight[latestRequestedContext] != nil
    }

    static func reconcileServerSettings(
        _ server: UserSettings,
        current: UserSettings,
        selectedDirection: LearningDirection?,
        setupDone: Bool
    )
        -> UserSettings
    {
        guard !setupDone else { return server }
        var reconciled = server
        reconciled.uiLang = current.uiLang
        reconciled.learningDirection = selectedDirection
            ?? current.learningDirection
        return reconciled
    }

    /// Adopt settings that were already persisted server-side by the caller
    /// (first-run SetupView POSTs via UserRepository directly). Seeds `current`
    /// so downstream readers — the study-queue params, Today's theme grid —
    /// see the fresh choices immediately instead of waiting for the next
    /// server load().
    func adoptPersisted(_ settings: UserSettings) {
        let context = LoadContext(userID: self.signedInUserProvider()?.id)
        self.latestRequestedContext = context
        for flight in self.inFlight.values {
            flight.task.cancel()
        }
        self.inFlight.removeAll()
        self.loadedContext = context
        let directionChanged = self.current.learningDirection != settings.learningDirection
        self.current = settings
        self.hasLoaded = true
        self.loading = false
        self.lastError = nil
        self.defaults.set(settings.uiLang, forKey: tujiUILangDefaultsKey)
        // Normally a no-op: Setup posts the direction the onboarding picker
        // already applied. It is here because this is the third way `current`
        // can change, and "the store notices" is the whole point of the seam —
        // a fourth caller should not have to remember.
        if directionChanged {
            Task { await self.directionRefresh.refresh(after: .serverDisagreed) }
        }
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
        self.defaults.set(next.uiLang, forKey: tujiUILangDefaultsKey)
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
    ///
    /// Also drops and re-fetches everything scoped to the old direction. The two
    /// callers used to do that themselves and disagreed about what it meant —
    /// the first-run picker left the previous direction's mastery, progress and
    /// streak on screen. Fire-and-forget: the picker dismisses immediately and
    /// the stores publish as they land.
    func setLearningDirection(_ direction: LearningDirection, persist: Bool) {
        guard self.current.learningDirection != direction else { return }
        self.current.learningDirection = direction
        self.defaults.set(direction.rawValue, forKey: self.learningDirectionKey)
        if persist {
            self.scheduleSave()
        }
        Task { await self.directionRefresh.refresh(after: .userPicked) }
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
