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

    /// Coalesce rapid changes (e.g. toggling back and forth) into one POST.
    private let saveDebounce: Duration = .milliseconds(400)

    private init() {}

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
            let resp: UserSettingsResponse = try await APIClient.shared.get(.usersSettings)
            let directionChanged =
                self.current.learningDirection != resp.settings.learningDirection
            self.current = resp.settings
            OnboardingState.shared.learningDirection = resp.settings.learningDirection
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

    // MARK: - Immediate edits

    /// Mutate the live settings and persist automatically. The change is
    /// applied to `current` synchronously so the UI reflects it at once; the
    /// network write is debounced so quick successive edits collapse into a
    /// single POST.
    func update(_ mutate: (inout UserSettings) -> Void) {
        var next = self.current
        mutate(&next)
        guard next != self.current else { return }
        self.current = next
        self.scheduleSave()
    }

    /// Applies the learning target immediately. First-launch and guest flows
    /// use `persist: false`; signed-in settings changes sync to the server.
    func setLearningDirection(_ direction: LearningDirection, persist: Bool) {
        guard self.current.learningDirection != direction else { return }
        self.current.learningDirection = direction
        UserDefaults.standard.set(direction.rawValue, forKey: "tuji.learning.direction")
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
            let _: SaveSettingsResponse = try await APIClient.shared.post(
                .usersSettings,
                body: snapshot
            )
            self.log.info("settings saved")
        } catch {
            self.lastError = error
            self.log.error("settings save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
