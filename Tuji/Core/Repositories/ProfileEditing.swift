import Foundation

/// Deep client module for the whole profile editor. Callers do not know the
/// multipart wire format or how a successful edit refreshes 作者主頁 state.
@MainActor
protocol ProfileEditing {
    func load() async throws -> UserMeUser?
    func edit(_ change: ProfileEditChange, avatarData: Data?) async throws -> AtlasAuthor
}

@MainActor
struct LiveProfileModule: ProfileEditing {
    static let shared = LiveProfileModule()

    private let api: APIClient
    private let profiles: AuthorProfileModule

    init(api: APIClient = .shared, profiles: AuthorProfileModule = .shared) {
        self.api = api
        self.profiles = profiles
    }

    func load() async throws -> UserMeUser? {
        let response: UserMeResponse = try await self.api.get(.usersMe)
        return response.user
    }

    func edit(_ change: ProfileEditChange, avatarData: Data?) async throws -> AtlasAuthor {
        var fields = [
            "nickname": change.nickname ?? "",
            "bio": change.bio
        ]
        if let avatar = change.avatar { fields["avatar"] = avatar }
        let response: ProfileUpdateResponse = try await self.api.upload(
            .usersProfile,
            fileField: "image",
            filename: "avatar.jpg",
            mimeType: "image/jpeg",
            data: avatarData,
            fields: fields
        )
        self.profiles.replace(author: response.author)
        return response.author
    }
}
