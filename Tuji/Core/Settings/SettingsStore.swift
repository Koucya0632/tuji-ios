// Single source of truth for the signed-in user's settings. Lazy-loaded
// on the first SettingsView appearance; subsequent reads return the
// in-memory `current` snapshot. SettingsView edits the `draft` copy
// and calls `save()` to persist via POST /api/users/settings.

import Observation
import OSLog
import SwiftUI

@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    private(set) var current: UserSettings = .default
    var draft: UserSettings = .default
    private(set) var loading: Bool = false
    private(set) var saving: Bool = false
    private(set) var lastError: Error?

    private let log = Logger(subsystem: "app.tuji.ios", category: "settings")
    private var hasLoaded: Bool = false

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
            self.current = resp.settings
            self.draft = resp.settings
            self.hasLoaded = true
            self.log.info("settings loaded")
        } catch {
            self.lastError = error
            self.log.error("settings load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    var dirty: Bool {
        self.current != self.draft
    }

    func save() async {
        guard self.dirty else { return }
        self.saving = true
        self.lastError = nil
        defer { self.saving = false }
        do {
            let resp: SaveSettingsResponse = try await APIClient.shared.post(
                .usersSettings,
                body: self.draft
            )
            self.current = resp.settings ?? self.draft
            self.draft = self.current
            self.log.info("settings saved")
        } catch {
            self.lastError = error
            self.log.error("settings save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Discards any in-flight edits.
    func revertDraft() {
        self.draft = self.current
    }
}
