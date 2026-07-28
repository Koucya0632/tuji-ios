import Foundation

/// Narrow seam over `StudyQueueStore` for fetching a study queue on demand — the
/// one method a coordinator needs to chain another round (再來一輪). Injected so
/// the fetch is testable and the coordinator doesn't reach `StudyQueueStore.shared`
/// (nor does the view).
///
/// `StudyQueueStore` already implements it, so it conforms for free.
@MainActor
protocol StudyQueueProviding {
    func fetch(mode: StudyMode) async throws -> [StudyQueueItem]
}

extension StudyQueueStore: StudyQueueProviding {}
