import Foundation

/// The 作者主頁 interface used by callers and tests. Network refresh, the
/// last-successful cache, and post-edit identity replacement stay behind it.
@MainActor
protocol AuthorProfileLoading {
    func load(handle: String, refresh: Bool) async throws -> AtlasAuthorResponse
}

@MainActor
final class AuthorProfileModule: AuthorProfileLoading {
    static let shared = AuthorProfileModule()

    private let network: AuthorReading
    private var cache: [String: AtlasAuthorResponse] = [:]
    /// A successful edit response is newer than any public edge-cache copy.
    private var editedIdentity: [String: AtlasAuthor] = [:]

    init(network: AuthorReading = LiveAtlasRepository.shared) {
        self.network = network
    }

    func load(handle: String, refresh: Bool) async throws -> AtlasAuthorResponse {
        do {
            var response = try await self.network.author(handle: handle, forceReload: refresh)
            if let identity = self.editedIdentity[handle] {
                response = AtlasAuthorResponse(
                    author: identity,
                    items: response.items,
                    collections: response.collections
                )
            }
            self.cache[handle] = response
            return response
        } catch {
            if let cached = self.cache[handle] { return cached }
            throw error
        }
    }

    /// Replaces identity directly from the authoritative Profile-edit response;
    /// the next page render never needs an onDisappear refetch to show it.
    func replace(author: AtlasAuthor) {
        self.editedIdentity[author.handle] = author
        let previous = self.cache[author.handle]
        self.cache[author.handle] = AtlasAuthorResponse(
            author: author,
            items: previous?.items ?? [],
            collections: previous?.collections ?? []
        )
    }
}
