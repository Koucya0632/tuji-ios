import Foundation

/// The 公開作者身分 seam: read the current identity, accept a new one. Two
/// methods, so a test double for the publish gate stubs exactly what the gate
/// asks (see CONTEXT.md → architecture / role seams).
@MainActor
protocol PublicAuthorIdentityEditing {
    func publicAuthorIdentity() async throws -> PublicAuthorIdentity
    func setPublicAuthorIdentity(
        _ payload: PublicAuthorIdentityPayload
    ) async throws
        -> PublicAuthorIdentityResponse
}

extension LiveUserRepository: PublicAuthorIdentityEditing {}
