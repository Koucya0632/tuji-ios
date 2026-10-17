import Foundation

/// Only unacknowledged requests live on the device. Results belong to 語法紀錄 on the server.
@MainActor
protocol GrammarJournaling {
    func pending(owner: String) -> [GrammarInput]
    func save(_ input: GrammarInput, owner: String)
    func remove(id: String, owner: String)
}

@MainActor
struct DefaultsGrammarJournal: GrammarJournaling {
    var defaults: UserDefaults = .standard
    private func key(_ owner: String) -> String {
        "grammar.pending.v1.\(owner)"
    }

    func pending(owner: String) -> [GrammarInput] {
        guard let data = self.defaults.data(forKey: self.key(owner)) else { return [] }
        return (try? JSONDecoder().decode([GrammarInput].self, from: data)) ?? []
    }

    func save(_ input: GrammarInput, owner: String) {
        var values = self.pending(owner: owner).filter { $0.requestId != input.requestId }
        values.append(input)
        self.write(values, owner: owner)
    }

    func remove(id: String, owner: String) {
        self.write(self.pending(owner: owner).filter { $0.requestId != id }, owner: owner)
    }

    private func write(_ values: [GrammarInput], owner: String) {
        if values.isEmpty { self.defaults.removeObject(forKey: self.key(owner)) }
        else if let data = try? JSONEncoder().encode(values) { self.defaults.set(data, forKey: self.key(owner)) }
    }
}

/// One run through a practice set, or through the questions it got wrong.
struct GrammarAttempt: Codable, Equatable, Identifiable {
    let id: String
    /// Only the first run counts as the score. Redoing, or answering after the
    /// answers were already read, is practice.
    let isFirst: Bool
    let questionIds: [String]
    /// Question id → the option first confirmed for it. Fixed once confirmed.
    var answers: [String: String] = [:]

    var finished: Bool {
        self.questionIds.allSatisfy { self.answers[$0] != nil }
    }
}

/// How far one practice set got on this device. Never sent to the server and never
/// mixed into the generated set; another device starts the set fresh.
struct GrammarPracticeProgress: Codable, Equatable {
    var attempts: [GrammarAttempt] = []
    /// 查看題目與解析 was opened before the first run was finished.
    var revealed = false
}

@MainActor
protocol GrammarProgressStoring {
    func progress(owner: String, learning: String, setId: String) -> GrammarPracticeProgress
    func save(_ progress: GrammarPracticeProgress, owner: String, learning: String, setId: String)
    func remove(owner: String, learning: String, setId: String)
}

@MainActor
struct DefaultsGrammarProgress: GrammarProgressStoring {
    var defaults: UserDefaults = .standard
    private func key(_ owner: String, _ learning: String, _ setId: String) -> String {
        "grammar.practice.v1.\(owner).\(learning).\(setId)"
    }

    func progress(owner: String, learning: String, setId: String) -> GrammarPracticeProgress {
        guard let data = self.defaults.data(forKey: self.key(owner, learning, setId)) else { return .init() }
        return (try? JSONDecoder().decode(GrammarPracticeProgress.self, from: data)) ?? .init()
    }

    func save(_ progress: GrammarPracticeProgress, owner: String, learning: String, setId: String) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        self.defaults.set(data, forKey: self.key(owner, learning, setId))
    }

    func remove(owner: String, learning: String, setId: String) {
        self.defaults.removeObject(forKey: self.key(owner, learning, setId))
    }
}
