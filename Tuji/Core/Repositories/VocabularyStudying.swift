import Foundation

enum VocabularyMode: String, Codable, CaseIterable, Identifiable {
    case lookup, analysis, mnemonic
    var id: String {
        self.rawValue
    }

    var title: String {
        switch self {
        case .lookup: tujiLocalized("查詞")
        case .analysis: tujiLocalized("單詞深度解析")
        case .mnemonic: tujiLocalized("助記")
        }
    }

    var summary: String {
        switch self {
        case .lookup: tujiLocalized("快速看懂詞義，順手掌握相關表達。")
        case .analysis: tujiLocalized("從近義詞到搭配，一次講透一個詞。")
        case .mnemonic: tujiLocalized("用一眼能記住的聯想，降低背詞難度。")
        }
    }
}

struct VocabularyInput: Codable, Equatable {
    let requestId: String
    let mode: VocabularyMode
    let query: String
    let context: String
    let selectedSense: String
    let uiLanguage: String
    let learningDirection: String
    let pricingVersion: String
    let maxPoints: Int
}

struct VocabularyOffer: Decodable, Equatable {
    struct Price: Decodable, Equatable {
        let mode: VocabularyMode
        let minPoints: Int
        let maxPoints: Int
    }

    /// Why generation is closed: switched off for everyone, or a member feature.
    /// Too few points is not a reason here — the app compares `available` itself.
    enum Reason: String, Decodable, Equatable {
        case disabled, membership
    }

    let enabled: Bool
    var reason: Reason?
    let available: Int
    let pricingVersion: String
    let modes: [Price]
}

struct VocabularyHeadword: Codable, Equatable {
    let text: String
    let reading: String?
    let partOfSpeech: String
    let meaning: String
}

struct VocabularyLine: Codable, Equatable {
    let text: String
    let reading: String?
    let translation: String?
    let note: String?
}

struct VocabularyCandidate: Codable, Equatable {
    let term: String
    let meaning: String
}

struct VocabularyLookup: Codable, Equatable {
    struct Sense: Codable, Equatable {
        let term: String
        let meaning: String
        let explanation: String
        let relevant: Bool
    }

    struct Related: Codable, Equatable {
        let term: String
        let relation: String
    }

    let headword: VocabularyHeadword
    let senses: [Sense]
    let expressions: [VocabularyLine]
    let related: [Related]
}

struct VocabularyAnalysis: Codable, Equatable {
    struct Comparison: Codable, Equatable {
        let term: String
        let difference: String
        let whenToUse: String
        let examples: [VocabularyLine]
    }

    struct Usage: Codable, Equatable {
        let title: String
        let explanation: String
    }

    struct Collocation: Codable, Equatable {
        let phrase: String
        let meaning: String
        let pattern: String
    }

    let headword: VocabularyHeadword
    let comparisons: [Comparison]
    let usage: [Usage]
    let examples: [VocabularyLine]
    let collocations: [Collocation]
}

struct VocabularyMnemonic: Codable, Equatable {
    struct Quiz: Codable, Equatable {
        let question: String
        let answer: String
        let hint: String
    }

    let headword: VocabularyHeadword
    let association: String
    let technique: String
    let retelling: String
    let example: VocabularyLine
    let quiz: Quiz
}

enum VocabularyContent: Decodable, Equatable {
    case lookup(VocabularyLookup)
    case analysis(VocabularyAnalysis)
    case mnemonic(VocabularyMnemonic)

    private enum CodingKeys: String, CodingKey { case mode }
    init(from decoder: Decoder) throws {
        let mode = try decoder.container(keyedBy: CodingKeys.self).decode(VocabularyMode.self, forKey: .mode)
        switch mode {
        case .lookup: self = try .lookup(VocabularyLookup(from: decoder))
        case .analysis: self = try .analysis(VocabularyAnalysis(from: decoder))
        case .mnemonic: self = try .mnemonic(VocabularyMnemonic(from: decoder))
        }
    }

    var headword: VocabularyHeadword {
        switch self {
        case let .lookup(value): value.headword
        case let .analysis(value): value.headword
        case let .mnemonic(value): value.headword
        }
    }
}

struct VocabularyReply: Decodable, Equatable {
    let outcome: String
    let message: String
    let candidates: [VocabularyCandidate]
    let content: VocabularyContent?
}

struct VocabularyRecord: Decodable, Identifiable, Equatable {
    enum Status: String, Decodable { case pending, completed, clarification, failed, deleted }
    let id: String
    let status: Status
    let input: VocabularyInput?
    let result: VocabularyReply?
    let charged: Int
    let favorite: Bool
    let createdAt: String
    let templateVersion: String
    let error: String?
}

struct VocabularyRecords: Decodable {
    let records: [VocabularyRecord]
    let nextCursor: String?
}

@MainActor
protocol VocabularyStudying {
    func offer() async throws -> VocabularyOffer
    func generate(_ input: VocabularyInput) async throws -> VocabularyRecord
    func record(id: String) async throws -> VocabularyRecord
    func records(learning: String, favorite: Bool, cursor: String?) async throws -> VocabularyRecords
    func favorite(id: String, value: Bool) async throws -> VocabularyRecord
    func delete(id: String) async throws
}

@MainActor
struct LiveVocabularyRepository: VocabularyStudying {
    var api: APIClient = .shared
    private struct Envelope: Decodable { let record: VocabularyRecord }
    func offer() async throws -> VocabularyOffer {
        try await self.api.get(.vocabularyOffer)
    }

    func generate(_ input: VocabularyInput) async throws -> VocabularyRecord {
        let value: Envelope = try await self.api.post(.vocabularyGenerate, body: input)
        return value.record
    }

    func record(id: String) async throws -> VocabularyRecord {
        let value: Envelope = try await self.api.get(.vocabularyRecord(id: id))
        return value.record
    }

    func records(learning: String, favorite: Bool, cursor: String?) async throws -> VocabularyRecords {
        try await self.api.get(.vocabularyRecords(learning: learning, favorite: favorite, cursor: cursor))
    }

    func favorite(id: String, value: Bool) async throws -> VocabularyRecord {
        struct Body: Encodable { let favorite: Bool }
        let result: Envelope = try await self.api.patch(.vocabularyRecord(id: id), body: Body(favorite: value))
        return result.record
    }

    func delete(id: String) async throws {
        try await self.api.delete(.vocabularyRecord(id: id))
    }
}
