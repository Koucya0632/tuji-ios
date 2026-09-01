// Durable outbox for /api/study/answer writes that exhausted their in-session
// retries (offline, server down). Before this, such ratings were only counted
// into CompleteView's 未同步 notice and then lost — the user's session showed
// as saved while the SRS schedule silently never learned about it.
//
// Owner-tagged payloads are appended to a JSON file in Application Support and
// replayed only while that same account is active. The backend tolerates
// duplicate answers, so a crash between POST-success and file-save can at worst
// replay one answer twice.

import Foundation
import OSLog

@MainActor
final class StudyAnswerOutbox {
    static let shared = StudyAnswerOutbox()

    private struct Entry: Codable {
        let id: UUID
        let ownerUserID: UUID
        let payload: StudyAnswerPayload
    }

    private var entries: [Entry]
    private var replaying = false

    private let fileURL: URL
    private let activeUserID: @MainActor () -> UUID?
    private let log = Logger(subsystem: "app.tuji.ios", category: "answer-outbox")

    /// `fileURL` is injectable so tests can point at a scratch file.
    init(
        fileURL: URL? = nil,
        activeUserID: @escaping @MainActor () -> UUID? = {
            AuthService.shared.session.signedInUser?.id
        }
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.activeUserID = activeUserID
        self.entries = Self.load(from: self.fileURL)
    }

    /// Compatibility projection used by the completion UI and focused tests.
    /// Ownership stays in `entries` and is never discarded during replay.
    var pending: [StudyAnswerPayload] {
        guard let ownerUserID = self.activeUserID() else { return [] }
        return Array(
            self.entries.lazy
                .filter { $0.ownerUserID == ownerUserID }
                .map(\.payload)
        )
    }

    var count: Int {
        self.pending.count
    }

    /// Park an answer whose in-session retries all failed. Persisted
    /// immediately so a force-quit doesn't lose it.
    func add(_ payload: StudyAnswerPayload) {
        guard let ownerUserID = self.activeUserID() else {
            self.log.error("refusing to park an answer without an active account")
            return
        }
        self.entries.append(Entry(id: UUID(), ownerUserID: ownerUserID, payload: payload))
        self.save()
        self.log.info("parked answer for card \(payload.cardId, privacy: .public) (\(self.entries.count) pending)")
    }

    /// Re-send everything in order. Successes leave the outbox; the first
    /// failure stops the pass (same network, later ones would fail too) and
    /// keeps the rest for the next trigger. Reentrancy-guarded — launch and
    /// foreground triggers can overlap.
    func replay(using repository: StudyRepository = LiveStudyRepository.shared) async {
        guard !self.replaying, let ownerUserID = self.activeUserID() else { return }
        self.replaying = true
        defer { self.replaying = false }
        let ownedCount = self.entries.count(where: { $0.ownerUserID == ownerUserID })
        guard ownedCount > 0 else { return }
        self.log.info("replaying \(ownedCount) parked answers")
        while self.activeUserID() == ownerUserID,
              let entry = self.entries.first(where: { $0.ownerUserID == ownerUserID })
        {
            var next = entry.payload
            next.ownerUserId = ownerUserID
            do {
                _ = try await repository.submitAnswer(next)
                guard self.activeUserID() == ownerUserID,
                      let index = self.entries.firstIndex(where: { $0.id == entry.id })
                else { return }
                self.entries.remove(at: index)
                self.save()
            } catch {
                self.log.info("replay stopped: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
    }

    /// Sign-out is a hard account boundary. Even though entries are owner-tagged,
    /// clear them so no pending payload survives into another session or backup.
    func reset() {
        self.entries.removeAll()
        self.save()
    }

    // MARK: - Disk

    private static func defaultFileURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("study-answer-outbox.json")
    }

    private static func load(from url: URL) -> [Entry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        if let entries = try? JSONDecoder().decode([Entry].self, from: data) {
            return entries
        }
        // Pre-account-binding files cannot be attributed safely. Quarantine
        // them instead of silently replaying their payloads under whoever logs
        // in after the update.
        if (try? JSONDecoder().decode([StudyAnswerPayload].self, from: data)) != nil {
            let quarantineURL = url.appendingPathExtension("unowned")
            try? FileManager.default.removeItem(at: quarantineURL)
            try? FileManager.default.moveItem(at: url, to: quarantineURL)
        }
        return []
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(self.entries)
            try data.write(to: self.fileURL, options: .atomic)
        } catch {
            self.log.error("outbox save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
