// 個人筆記 wire models — /api/users/word-notes (tuji-web lib/word-notes).
// `available` is false under membership policy v1; `canWrite` is false for a
// non-member, who can still read and delete what they wrote.

import Foundation

struct WordNote: Decodable, Hashable {
    let wordId: String
    let body: String
    let updatedAt: String
}

struct WordNotesResponse: Decodable {
    let available: Bool
    let canWrite: Bool
    let maxLength: Int?
    let notes: [WordNote]
}

struct WordNoteSaveResponse: Decodable {
    let note: WordNote
}

struct WordNotePayload: Encodable {
    let body: String
}
