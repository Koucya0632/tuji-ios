import Observation

/// Tiny cross-screen signal carrying the last confirmed server mutation.
/// The explore and saved shelves both apply it immediately without guessing.
@MainActor
@Observable
final class CollectionBookmarkStore {
    struct Change: Equatable {
        let collection: AtlasCollection
        let saved: Bool
    }

    private(set) var revision = 0
    private(set) var lastChange: Change?

    func publish(collection: AtlasCollection, saved: Bool) {
        self.lastChange = Change(collection: collection, saved: saved)
        self.revision += 1
    }
}
