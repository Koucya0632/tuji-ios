// One `SceneProgressBook` per account, one file each:
// Application Support/scenes/<account id>.json.
//
// Only this device keeps it (場面練習方案 §5: the first version does not sync).
// Signing out drops the book in memory and leaves the file, so the next account
// starts from its own file and switching back finds this one where it was.

import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class SceneProgressStore {
    static let shared = SceneProgressStore()

    private(set) var accountId: UUID?
    private(set) var book = SceneProgressBook()

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let log = Logger(subsystem: "app.tuji.ios", category: "scenes")

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("scenes", isDirectory: true)
    }

    /// Load `account`'s book. Safe to call on every appearance: the same
    /// account is a no-op, so an unsaved edit is never read back over.
    func use(account: UUID) {
        guard account != self.accountId else { return }
        self.accountId = account
        self.book = self.read(account) ?? SceneProgressBook()
    }

    func update(_ change: (inout SceneProgressBook) -> Void) {
        guard let account = self.accountId else {
            self.log.error("scene progress changed with no account")
            return
        }
        change(&self.book)
        self.write(self.book, for: account)
    }

    /// Sign-out. The book in memory is the signed-out account's; its file stays.
    func reset() {
        self.accountId = nil
        self.book = SceneProgressBook()
    }

    private func fileURL(_ account: UUID) -> URL {
        self.directory.appendingPathComponent(account.uuidString.lowercased() + ".json")
    }

    private func read(_ account: UUID) -> SceneProgressBook? {
        guard let data = try? Data(contentsOf: self.fileURL(account)) else { return nil }
        do {
            return try JSONDecoder().decode(SceneProgressBook.self, from: data)
        } catch {
            self.log.error("scene progress unreadable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func write(_ book: SceneProgressBook, for account: UUID) {
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(book).write(to: self.fileURL(account), options: .atomic)
        } catch {
            self.log.error("scene progress not saved: \(error.localizedDescription, privacy: .public)")
        }
    }
}

