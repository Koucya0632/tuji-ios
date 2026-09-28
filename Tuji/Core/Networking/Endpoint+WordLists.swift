// 個人詞表 endpoints (tuji-web app/api/users/word-lists, and the study queue's
// `?list=`). All private and fresh: a word added a moment ago must be in the
// very next read and the very next session.

import Foundation

extension Endpoint {
    var wordListDescriptor: EndpointDescriptor {
        switch self {
        case let .usersWordLists(learning, word):
            EndpointDescriptor(
                path: "/api/users/word-lists",
                queryItems: [URLQueryItem(name: "learning", value: learning)]
                    + (word.map { [URLQueryItem(name: "word", value: $0)] } ?? []),
                policy: .privateFresh
            )
        case let .usersWordList(id):
            EndpointDescriptor(path: "/api/users/word-lists/\(id)", policy: .privateFresh)
        case let .usersWordListWords(id):
            EndpointDescriptor(path: "/api/users/word-lists/\(id)/words", policy: .privateFresh)
        case let .usersWordListOrder(learning):
            EndpointDescriptor(
                path: "/api/users/word-lists/order",
                queryItems: [URLQueryItem(name: "learning", value: learning)],
                policy: .privateFresh
            )
        case let .studyWordListQueue(listId, mode, limit, lang, learning):
            // `list` replaces the theme filter: a list is its own selection.
            EndpointDescriptor(
                path: "/api/study/queue",
                queryItems: [
                    URLQueryItem(name: "mode", value: mode),
                    URLQueryItem(name: "limit", value: String(limit)),
                    URLQueryItem(name: "new", value: String(limit)),
                    URLQueryItem(name: "list", value: listId),
                    URLQueryItem(name: "lang", value: lang),
                    URLQueryItem(name: "learning", value: learning)
                ],
                policy: .privateFresh
            )
        default:
            preconditionFailure("\(self) is not a 個人詞表 endpoint")
        }
    }
}
