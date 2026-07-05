// Durable outbox for /api/study/answer writes that exhausted their in-session
// retries (offline, server down). Before this, such ratings were only counted
// into CompleteView's 未同步 notice and then lost — the user's session showed
// as saved while the SRS schedule silently never learned about it.
//
// Payloads are appended to a JSON file in Application Support and replayed on
// app launch / foreground. The backend tolerates duplicate answers, so a crash
// between POST-success and file-save can at worst replay one answer twice.

import Foundation
import OSLog

@MainActor
final class StudyAnswerOutbox {
    static let shared = StudyAnswerOutbox()

    private(set) var pending: [StudyAnswerPayload]
    private var replaying = false

    private let fileURL: URL
    private let log = Logger(subsystem: "app.tuji.ios", category: "answer-outbox")

    /// `fileURL` is injectable so tests can point at a scratch file.
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.pending = Self.load(from: self.fileURL)
    }

    var count: Int {
        self.pending.count
    }

    /// Park an answer whose in-session retries all failed. Persisted
    /// immediately so a force-quit doesn't lose it.
    func add(_ payload: StudyAnswerPayload) {
        self.pending.append(payload)
        self.save()
        self.log.info("parked answer for card \(payload.cardId, privacy: .public) (\(self.pending.count) pending)")
    }

    /// Re-send everything in order. Successes leave the outbox; the first
    /// failure stops the pass (same network, later ones would fail too) and
    /// keeps the rest for the next trigger. Reentrancy-guarded — launch and
    /// foreground triggers can overlap.
    func replay(using repository: StudyRepository = LiveStudyRepository.shared) async {
        guard !self.replaying, !self.pending.isEmpty else { return }
        self.replaying = true
        defer { self.replaying = false }
        self.log.info("replaying \(self.pending.count) parked answers")
        while let next = self.pending.first {
            do {
                _ = try await repository.submitAnswer(next)
                self.pending.removeFirst()
                self.save()
            } catch {
                self.log.info("replay stopped: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
    }

    // MARK: - Disk

    private static func defaultFileURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("study-answer-outbox.json")
    }

    private static func load(from url: URL) -> [StudyAnswerPayload] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([StudyAnswerPayload].self, from: data)) ?? []
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(self.pending)
            try data.write(to: self.fileURL, options: .atomic)
        } catch {
            self.log.error("outbox save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
