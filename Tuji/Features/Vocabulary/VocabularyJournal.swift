import Foundation

/// Only unacknowledged requests live on the device. Results belong to server history.
@MainActor
protocol VocabularyJournaling {
    func pending(owner: String) -> [VocabularyInput]
    func save(_ input: VocabularyInput, owner: String)
    func remove(id: String, owner: String)
}

@MainActor
struct DefaultsVocabularyJournal: VocabularyJournaling {
    var defaults: UserDefaults = .standard
    private func key(_ owner: String) -> String {
        "vocabulary.pending.v1.\(owner)"
    }

    func pending(owner: String) -> [VocabularyInput] {
        guard let data = self.defaults.data(forKey: self.key(owner)) else { return [] }
        return (try? JSONDecoder().decode([VocabularyInput].self, from: data)) ?? []
    }

    func save(_ input: VocabularyInput, owner: String) {
        var values = self.pending(owner: owner).filter { $0.requestId != input.requestId }
        values.append(input)
        self.write(values, owner: owner)
    }

    func remove(id: String, owner: String) {
        self.write(self.pending(owner: owner).filter { $0.requestId != id }, owner: owner)
    }

    private func write(_ values: [VocabularyInput], owner: String) {
        if values.isEmpty { self.defaults.removeObject(forKey: self.key(owner)) }
        else if let data = try? JSONEncoder().encode(values) { self.defaults.set(data, forKey: self.key(owner)) }
    }
}
