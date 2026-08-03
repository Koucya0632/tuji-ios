// 建立合集. The create sheet used to hold this itself — its own repository, its
// own `creating` flag, and a validation rule spelled out three times (once to
// disable the button, once as a guard, once as the trim that produced the
// payload) which disagreed with itself: the non-empty branch shipped the
// *untrimmed* description. `FakeCollectionManaging.createCollection` throwing
// `NotImplemented` in the tests was the tell that nothing could reach it.

import Foundation
import Observation

@MainActor
@Observable
final class CollectionCreateModel {
    /// The two fields the view binds and edits directly.
    var title = ""
    var description = ""

    private(set) var creating = false
    private(set) var errorMessage: String?

    let language: TargetLanguage

    private let repo: CollectionManaging

    init(language: TargetLanguage, repo: CollectionManaging = LiveAtlasRepository.shared) {
        self.language = language
        self.repo = repo
    }

    /// One rule, read by the button and enforced by `create()` — they can no
    /// longer drift apart.
    var canCreate: Bool {
        !self.creating && !self.trimmedTitle.isEmpty
    }

    private var trimmedTitle: String {
        self.title.trimmingCharacters(in: .whitespaces)
    }

    /// Blank-after-trimming means "no description", and what is sent is always
    /// the trimmed text. Matches `CollectionEditVM`, which the sheet did not.
    private var trimmedDescription: String? {
        let trimmed = self.description.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Returns the created 合集, or nil if validation blocked it or the server
    /// refused — in which case `errorMessage` explains.
    func create() async -> AtlasMyCollection? {
        guard self.canCreate else { return nil }
        self.creating = true
        self.errorMessage = nil
        defer { self.creating = false }
        do {
            return try await self.repo.createCollection(
                title: self.trimmedTitle,
                description: self.trimmedDescription,
                targetLanguage: self.language
            )
        } catch {
            self.errorMessage = error.localizedDescription
            return nil
        }
    }
}
