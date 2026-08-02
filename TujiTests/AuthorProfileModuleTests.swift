import Testing
@testable import Tuji

@MainActor
struct AuthorProfileModuleTests {
    @Test
    func offlineLoadReturnsTheLastSuccessfulProfile() async throws {
        let network = AuthorNetworkFake()
        let module = AuthorProfileModule(network: network)
        let first = try await module.load(handle: "TJ00000042", refresh: false)
        network.result = .failure(AuthorProfileModuleTestError.offline)

        let cached = try await module.load(handle: "TJ00000042", refresh: true)

        #expect(cached == first)
    }

    @Test
    func offlineWithoutCacheFailsExplicitly() async {
        let network = AuthorNetworkFake()
        network.result = .failure(AuthorProfileModuleTestError.offline)
        let module = AuthorProfileModule(network: network)

        await #expect(throws: AuthorProfileModuleTestError.self) {
            _ = try await module.load(handle: "TJ00000042", refresh: true)
        }
    }

    @Test
    func editResponseWinsOverAStalePublicIdentity() async throws {
        let network = AuthorNetworkFake()
        let module = AuthorProfileModule(network: network)
        let edited = author(name: "新暱稱", avatar: "https://example.com/new.webp")
        module.replace(author: edited)

        let loaded = try await module.load(handle: "TJ00000042", refresh: true)

        #expect(loaded.author == edited)
        #expect(loaded.items.count == 1)
    }

    private func author(name: String, avatar: String = "face") -> AtlasAuthor {
        AtlasAuthor(
            handle: "TJ00000042",
            displayName: name,
            avatar: avatar,
            bio: "簽名",
            joinedAt: nil,
            publishedCount: 1,
            saveCount: 2
        )
    }
}

private enum AuthorProfileModuleTestError: Error {
    case offline
}

@MainActor
private final class AuthorNetworkFake: AuthorReading {
    var result: Result<AtlasAuthorResponse, Error> = .success(
        AtlasAuthorResponse(
            author: AtlasAuthor(
                handle: "TJ00000042",
                displayName: "舊暱稱",
                avatar: "face",
                bio: nil,
                joinedAt: nil,
                publishedCount: 1,
                saveCount: 2
            ),
            items: [
                AtlasPublicItem(
                    id: "i1",
                    slug: "item-1",
                    lemma: "cat",
                    displayZhHant: "貓",
                    targetLanguage: .en,
                    category: nil,
                    imageUrl: nil,
                    author: nil,
                    publishedAt: nil
                )
            ]
        )
    )

    func author(handle _: String, forceReload _: Bool) async throws -> AtlasAuthorResponse {
        try self.result.get()
    }
}
