// The account's 個人筆記, read once and kept — the word page and the review
// reveal both ask here, so a note shows during review with no request of its own.
//
// Also where "does this feature exist for this account" lives: `available` is
// false under membership policy v1 and nothing about notes is drawn.

import Foundation
import Observation
import OSLog

/// How the note area on a word shows up.
enum WordNoteEntry: Equatable {
    /// Policy v1, not known yet, or a guest: nothing.
    case hidden
    /// A non-member with no note here: a lock that opens the paywall.
    case locked
    /// A non-member with a note (a refund): shown, deletable, not editable.
    case readOnly
    case editable
}

@MainActor
@Observable
final class WordNotesStore {
    static let shared = WordNotesStore()

    private(set) var phase: LoadPhase = .idle
    private(set) var available: Bool?
    private(set) var canWrite = false
    private(set) var maxLength = 500
    private(set) var notes: [String: WordNote] = [:]

    private let repository: WordNoteRepository
    private let log = Logger(subsystem: "app.tuji.ios", category: "word-notes")

    init(repository: WordNoteRepository = LiveWordNoteRepository.shared) {
        self.repository = repository
    }

    static func entry(available: Bool?, canWrite: Bool, hasNote: Bool) -> WordNoteEntry {
        guard available == true else { return .hidden }
        if canWrite { return .editable }
        return hasNote ? .readOnly : .locked
    }

    func entry(for wordId: String) -> WordNoteEntry {
        Self.entry(available: self.available, canWrite: self.canWrite, hasNote: self.notes[wordId] != nil)
    }

    func note(for wordId: String) -> WordNote? {
        guard self.available == true else { return nil }
        return self.notes[wordId]
    }

    func loadIfNeeded() async {
        guard self.phase == .idle || self.phase == .failed else { return }
        await self.reload()
    }

    func reload() async {
        let started = self.phase
        self.phase = started.reloading
        do {
            let response = try await self.repository.notes()
            self.available = response.available
            self.canWrite = response.canWrite
            self.maxLength = response.maxLength ?? 500
            self.notes = Dictionary(response.notes.map { ($0.wordId, $0) }, uniquingKeysWith: { a, _ in a })
            self.phase = .loaded
        } catch {
            self.phase = started.afterFailure
            self.log.error("word notes load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Trimmed and within `maxLength` (in characters, as the server counts).
    func isValid(_ body: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= self.maxLength
    }

    func save(_ body: String, for wordId: String) async -> MemberWriteOutcome {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            self.notes[wordId] = try await self.repository.save(wordId: wordId, body: trimmed)
            return .done
        } catch {
            return MemberWriteOutcome.from(error)
        }
    }

    /// Optimistic; put back if the server refuses.
    func delete(for wordId: String) async -> MemberWriteOutcome {
        let before = self.notes[wordId]
        self.notes[wordId] = nil
        do {
            try await self.repository.delete(wordId: wordId)
            return .done
        } catch {
            self.notes[wordId] = before
            return MemberWriteOutcome.from(error)
        }
    }

    /// The account changed: none of this is the next account's.
    func reset() {
        self.phase = .idle
        self.available = nil
        self.canWrite = false
        self.notes = [:]
    }
}
