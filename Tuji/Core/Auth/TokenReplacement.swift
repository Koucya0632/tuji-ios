// Whether a token the server refused still needs replacing.
//
// Several requests go out together — a screen's reload, a return to the
// foreground — so several 401s come back together. The first replacement
// refreshes the session; the rest find the current token already different
// from the one they were refused with, and take it rather than refresh again.
// Android holds the same rule in `core:auth`'s `TokenReplacement`.

enum TokenReplacement: Equatable {
    /// The current token is not the refused one. Use it.
    case useCurrent
    /// The current token is the refused one, or there is none. Refresh.
    case refresh

    /// - Parameters:
    ///   - current: the token the session holds now, or nil when it holds none.
    ///   - rejected: the token the server refused, or nil when the refused
    ///     request carried none.
    static func decide(current: String?, rejected: String?) -> TokenReplacement {
        if let current, current != rejected { return .useCurrent }
        return .refresh
    }
}
