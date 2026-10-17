import Foundation
import SwiftUI

/// AI 語法's three templates. The raw values are the server's.
enum GrammarMode: String, Codable, CaseIterable, Identifiable {
    case explain, compare, practice
    var id: String {
        self.rawValue
    }

    var title: LocalizedStringKey {
        switch self {
        case .explain: "語法解釋"
        case .compare: "近似語法"
        case .practice: "語法練習"
        }
    }

    var summary: LocalizedStringKey {
        switch self {
        case .explain: "結構拆解、規則、例句與使用場景。"
        case .compare: "分清相似說法的差異，以及能不能替換。"
        case .practice: "5 題選擇與語境判斷，每題都有解析。"
        }
    }

    var placeholder: LocalizedStringKey {
        switch self {
        case .explain: "輸入語法、句型或貼上句子"
        case .compare: "輸入語法，或問「A 和 B 有什麼差別」"
        case .practice: "輸入想練習的語法"
        }
    }
}

enum GrammarDifficulty: String, Codable, CaseIterable, Identifiable {
    case basic, advanced
    var id: String {
        self.rawValue
    }

    var title: LocalizedStringKey {
        self == .basic ? "基礎" : "進階"
    }
}

enum GrammarPracticeType: String, Codable, CaseIterable, Identifiable {
    case mixed, choice, context
    var id: String {
        self.rawValue
    }

    var title: LocalizedStringKey {
        switch self {
        case .mixed: "綜合練習"
        case .choice: "選擇練習"
        case .context: "語境判斷"
        }
    }
}

struct GrammarInput: Codable, Equatable {
    let requestId: String
    let mode: GrammarMode
    let query: String
    let context: String
    let compareWith: String
    let focus: String
    let difficulty: GrammarDifficulty
    let practiceType: GrammarPracticeType
    /// The card a next step was drafted from.
    let sourceRecordId: String?
    let uiLanguage: String
    let learningDirection: String
    let pricingVersion: String
    let maxPoints: Int
}

struct GrammarOffer: Codable, Equatable {
    struct Price: Codable, Equatable {
        let mode: GrammarMode
        let minPoints: Int
        let maxPoints: Int
    }

    /// Why generation is closed: switched off for everyone, or a member feature.
    enum Reason: String, Codable, Equatable {
        case disabled, membership
    }

    let enabled: Bool
    var reason: Reason?
    let available: Int
    let pricingVersion: String
    let modes: [Price]
}

struct GrammarLine: Codable, Equatable {
    let text: String
    let reading: String?
    let translation: String?
    let note: String?
}

/// A clarification's choice: one grammar point in what was pasted.
struct GrammarCandidate: Codable, Equatable {
    let focus: String
    let description: String
}

struct GrammarExplanation: Codable, Equatable {
    struct Summary: Codable, Equatable {
        let name: String
        let meaning: String
        let explanation: String
        let highlight: String?
    }

    struct Structure: Codable, Equatable {
        struct Part: Codable, Equatable {
            let part: String
            let role: String
        }

        let formula: String
        let parts: [Part]
        let breakdown: String?
        let forms: String?
    }

    struct Rule: Codable, Equatable {
        let title: String
        let explanation: String
    }

    struct Scene: Codable, Equatable {
        let situation: String
        let use: String
        let avoid: String?
    }

    let summary: Summary
    let structure: Structure
    let rules: [Rule]
    let examples: [GrammarLine]
    let scenes: [Scene]
}

enum GrammarVerdict: String, Codable, Equatable {
    case interchangeable, conditional, not

    var title: LocalizedStringKey {
        switch self {
        case .interchangeable: "可以替換"
        case .conditional: "有條件可替換"
        case .not: "不可替換"
        }
    }

    var symbol: String {
        switch self {
        case .interchangeable: "checkmark.circle"
        case .conditional: "exclamationmark.circle"
        case .not: "xmark.circle"
        }
    }
}

struct GrammarComparison: Codable, Equatable {
    struct Point: Codable, Equatable {
        let name: String
        let meaning: String
    }

    struct Similarity: Codable, Equatable {
        let shared: String
        let aFocus: String
        let bFocus: String
        let interchangeable: GrammarVerdict
    }

    struct Dimension: Codable, Equatable {
        let aspect: String
        let a: String
        let b: String
    }

    struct Pitfall: Codable, Equatable {
        enum Kind: String, Codable, Equatable {
            case grammar, meaning, register, unnatural

            var title: LocalizedStringKey {
                switch self {
                case .grammar: "語法錯誤"
                case .meaning: "語意改變"
                case .register: "語氣不合"
                case .unnatural: "不自然"
                }
            }
        }

        let wrong: String
        let fixed: String
        let kind: Kind
        let reason: String
    }

    struct Substitution: Codable, Equatable {
        let situation: String
        let a: GrammarLine
        let b: GrammarLine
        let verdict: GrammarVerdict
        let explanation: String
    }

    let a: Point
    let b: Point
    let chosenBecause: String?
    let summary: String
    let similarity: Similarity
    let dimensions: [Dimension]
    let pitfalls: [Pitfall]
    let substitutions: [Substitution]
}

struct GrammarPractice: Codable, Equatable {
    struct Question: Codable, Equatable, Identifiable {
        enum Kind: String, Codable, Equatable {
            case choice, context

            var title: LocalizedStringKey {
                self == .choice ? "選擇練習" : "語境判斷"
            }
        }

        struct Option: Codable, Equatable, Identifiable {
            let id: String
            let text: String
        }

        struct Explanation: Codable, Equatable {
            let optionId: String
            let reason: String
        }

        let id: String
        let kind: Kind
        let context: String?
        let prompt: String
        let options: [Option]
        let solution: String
        let answer: String
        let explanations: [Explanation]
        let point: String

        func reason(for option: String) -> String? {
            self.explanations.first { $0.optionId == option }?.reason
        }
    }

    let focus: String
    let difficulty: GrammarDifficulty
    let questions: [Question]
    let takeaways: [String]
}

enum GrammarContent: Decodable, Equatable {
    case explain(GrammarExplanation)
    case compare(GrammarComparison)
    case practice(GrammarPractice)

    private enum CodingKeys: String, CodingKey { case mode }
    init(from decoder: Decoder) throws {
        let mode = try decoder.container(keyedBy: CodingKeys.self).decode(GrammarMode.self, forKey: .mode)
        switch mode {
        case .explain: self = try .explain(GrammarExplanation(from: decoder))
        case .compare: self = try .compare(GrammarComparison(from: decoder))
        case .practice: self = try .practice(GrammarPractice(from: decoder))
        }
    }

    /// What 語法紀錄 lists it under.
    var title: String {
        switch self {
        case let .explain(value): value.summary.name
        case let .compare(value): "\(value.a.name) ／ \(value.b.name)"
        case let .practice(value): value.focus
        }
    }

    var gist: String {
        switch self {
        case let .explain(value): value.summary.meaning
        case let .compare(value): value.summary
        case let .practice(value): value.takeaways.first ?? ""
        }
    }
}

struct GrammarReply: Decodable, Equatable {
    let outcome: String
    let message: String
    let candidates: [GrammarCandidate]
    let content: GrammarContent?
}

struct GrammarRecord: Decodable, Identifiable, Equatable {
    enum Status: String, Decodable { case pending, completed, clarification, failed, deleted }
    let id: String
    let status: Status
    let input: GrammarInput?
    let result: GrammarReply?
    let charged: Int
    let favorite: Bool
    let createdAt: String
    let templateVersion: String
    let error: String?
}

struct GrammarRecords: Decodable {
    let records: [GrammarRecord]
    let nextCursor: String?
}

@MainActor
protocol GrammarStudying {
    func offer() async throws -> GrammarOffer
    func generate(_ input: GrammarInput) async throws -> GrammarRecord
    func record(id: String) async throws -> GrammarRecord
    func records(learning: String, favorite: Bool, mode: GrammarMode?, cursor: String?) async throws -> GrammarRecords
    func favorite(id: String, value: Bool) async throws -> GrammarRecord
    func delete(id: String) async throws
}

@MainActor
struct LiveGrammarRepository: GrammarStudying {
    var api: APIClient = .shared
    private struct Envelope: Decodable { let record: GrammarRecord }
    func offer() async throws -> GrammarOffer {
        try await self.api.get(.grammarOffer)
    }

    func generate(_ input: GrammarInput) async throws -> GrammarRecord {
        let value: Envelope = try await self.api.post(.grammarGenerate, body: input)
        return value.record
    }

    func record(id: String) async throws -> GrammarRecord {
        let value: Envelope = try await self.api.get(.grammarRecord(id: id))
        return value.record
    }

    func records(learning: String, favorite: Bool, mode: GrammarMode?, cursor: String?) async throws -> GrammarRecords {
        try await self.api.get(.grammarRecords(
            learning: learning,
            favorite: favorite,
            mode: mode?.rawValue,
            cursor: cursor
        ))
    }

    func favorite(id: String, value: Bool) async throws -> GrammarRecord {
        struct Body: Encodable { let favorite: Bool }
        let result: Envelope = try await self.api.patch(.grammarRecord(id: id), body: Body(favorite: value))
        return result.record
    }

    func delete(id: String) async throws {
        try await self.api.delete(.grammarRecord(id: id))
    }
}
