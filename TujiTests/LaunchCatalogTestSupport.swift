// The catalog half of launch, as a fake.
//
// `LaunchCoordinator` used to take `preloadCatalog` and `finalizeSignedIn` as
// two separate closures, so every test here supplied two bodies. They are one
// seam now (`CatalogWarming`), and `splitting(guest:signedIn:)` keeps the tests
// reading the way they did — one body per audience — while the production side
// gets a single named module instead of eight lines written twice inside
// `TujiApp.init`.

import Foundation
@testable import Tuji

@MainActor
final class FakeCatalogWarmer: CatalogWarming {
    private let onWarm: @MainActor (CatalogAudience) async -> Void

    /// Every audience warmed, in order, recorded on entry — which is where the
    /// two closures this replaced did their counting, so a gated body still
    /// registers before it blocks.
    private(set) var audiences: [CatalogAudience] = []

    init(onWarm: @escaping @MainActor (CatalogAudience) async -> Void = { _ in }) {
        self.onWarm = onWarm
    }

    /// One body per audience, mirroring the pair of closures this replaced.
    static func splitting(
        guest: @escaping @MainActor () async -> Void = {},
        signedIn: @escaping @MainActor (UUID) async -> Void = { _ in }
    )
        -> FakeCatalogWarmer
    {
        FakeCatalogWarmer { audience in
            switch audience {
            case .guest: await guest()
            case let .signedIn(userID): await signedIn(userID)
            }
        }
    }

    func warm(for audience: CatalogAudience) async {
        self.audiences.append(audience)
        await self.onWarm(audience)
    }

    var guestWarmings: Int {
        self.audiences.count { $0 == .guest }
    }

    func warmings(for userID: UUID) -> Int {
        self.audiences.count { $0 == .signedIn(userID: userID) }
    }
}
