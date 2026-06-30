import Foundation

@MainActor
protocol UserRepository {
    func loadSettings() async throws -> UserSettings
    func saveSettings(_ settings: UserSettings) async throws
    func updateProfile(_ payload: ProfileUpdatePayload) async throws -> ProfileUpdateResponse
    func deleteAccount() async throws
    func syncLocalCache(_ snapshot: SyncPayload) async throws
    func loadMe() async throws -> UserMeResponse
    func registerPushToken(_ payload: PushTokenPayload) async throws
    func unregisterPushToken(deviceId: String) async throws
}

@MainActor
struct LiveUserRepository: UserRepository {
    static let shared = LiveUserRepository()

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func loadSettings() async throws -> UserSettings {
        let response: UserSettingsResponse = try await self.api.get(.usersSettings)
        return response.settings
    }

    func saveSettings(_ settings: UserSettings) async throws {
        let _: SaveSettingsResponse = try await self.api.post(.usersSettings, body: settings)
    }

    func updateProfile(_ payload: ProfileUpdatePayload) async throws -> ProfileUpdateResponse {
        try await self.api.post(.usersProfile, body: payload)
    }

    func deleteAccount() async throws {
        struct EmptyBody: Encodable {}
        let _: SaveSettingsResponse = try await self.api.post(.usersDeleteAccount, body: EmptyBody())
    }

    func syncLocalCache(_ snapshot: SyncPayload) async throws {
        let _: SyncAckResponse = try await self.api.post(.usersSync, body: snapshot)
    }

    func loadMe() async throws -> UserMeResponse {
        try await self.api.get(.usersMe)
    }

    func registerPushToken(_ payload: PushTokenPayload) async throws {
        let _: AckResponse = try await self.api.post(.usersPushToken, body: payload)
    }

    func unregisterPushToken(deviceId: String) async throws {
        try await self.api.delete(.usersPushTokenDelete(deviceId: deviceId))
    }
}

struct SyncAckResponse: Decodable {
    let ok: Bool?
}

struct PushTokenPayload: Encodable {
    let token: String
    let deviceId: String
    let platform: String
}

struct AckResponse: Decodable {
    let ok: Bool?
}
