import Foundation

extension Endpoint {
    /// Private and fresh: what it holds depends on the caller's membership. The
    /// word detail itself stays edge-cached; only this slice is per-caller.
    var wordInsightsDescriptor: EndpointDescriptor {
        guard case let .wordInsights(id, lang, learning) = self else {
            preconditionFailure("\(self) is not the 詞條延伸內容 endpoint")
        }
        return EndpointDescriptor(
            path: "/api/words/\(id)/insights",
            queryItems: [
                URLQueryItem(name: "lang", value: lang),
                URLQueryItem(name: "learning", value: learning)
            ],
            policy: .privateFresh
        )
    }
}
