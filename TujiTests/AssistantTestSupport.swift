// Fixtures and fakes shared by the 助手 suites.

import Foundation
@testable import Tuji

enum AssistantFixture {
    static func word(
        _ id: String,
        word: String? = nil,
        chinese: String = "",
        category: String = "kitchen",
        authorHandle: String? = nil
    )
        -> CardWord
    {
        CardWord(
            id: id,
            word: word ?? id,
            chinese: chinese,
            imageUrl: "",
            category: category,
            pronunciation: "",
            authorHandle: authorHandle
        )
    }
}

@MainActor
final class AssistantDictionary: LocalDictionaryReading {
    var words: [CardWord]
    init(_ words: [CardWord] = []) {
        self.words = words
    }
}
