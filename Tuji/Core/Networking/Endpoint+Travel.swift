// 跟著 Moira 去旅遊 endpoints (tuji-web app/api/travel, the study queue's
// `?spot=`, and a spot's 「大家拍的」).
//
// The map is public and the same for everyone, so it caches like the
// dictionary. A spot's queue is the caller's own progress and must be fresh.

import Foundation

extension Endpoint {
    var travelDescriptor: EndpointDescriptor {
        switch self {
        case let .travel(lang, learning):
            EndpointDescriptor(
                path: "/api/travel",
                queryItems: [
                    URLQueryItem(name: "lang", value: lang),
                    URLQueryItem(name: "learning", value: learning)
                ],
                policy: .publicCached
            )
        case let .studySpotQueue(spotId, mode, limit, lang, learning):
            // `spot` replaces the theme filter, as `list` does: the spot's
            // words are the whole selection.
            EndpointDescriptor(
                path: "/api/study/queue",
                queryItems: [
                    URLQueryItem(name: "mode", value: mode),
                    URLQueryItem(name: "limit", value: String(limit)),
                    URLQueryItem(name: "new", value: String(limit)),
                    URLQueryItem(name: "spot", value: spotId),
                    URLQueryItem(name: "lang", value: lang),
                    URLQueryItem(name: "learning", value: learning)
                ],
                policy: .privateFresh
            )
        case let .travelSpotPhotos(spotId):
            // The same answer for everyone (the server drops nothing per user;
            // the client hides its own and blocked authors), like the 物見 feed.
            EndpointDescriptor(path: "/api/travel/spots/\(spotId)/photos", policy: .publicCached)
        default:
            preconditionFailure("\(self) is not a 旅遊 endpoint")
        }
    }
}
