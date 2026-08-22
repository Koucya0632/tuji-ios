// View model for AtlasAuthorProfileView (作者主頁). A load-and-render screen:
// fetches the author identity + their public items behind the AuthorReading seam
// so the view stays presentation-only. Analytics tracking stays in the view (the
// codebase convention — VMs don't reach AnalyticsService).

import Foundation
import Observation

@MainActor
@Observable
final class AuthorProfileVM {
    enum Phase: Equatable {
        case loading
        case ready
        /// Reserved for an invalid or nonexistent UID. Registered accounts with
        /// no public work return a ready profile with empty collections.
        case notFound
        case failed(String)
    }

    /// The two halves of an author's public work: the sets they curated, and
    /// everything they published. Label-free on purpose — this VM stays
    /// Foundation-only, so the copy lives at the call site.
    enum Segment: Hashable, CaseIterable {
        case collections
        case items
    }

    /// One language's worth of an author's public items. A profile is a body of
    /// work, not a study feed, so nothing is filtered out by the viewer's
    /// learning direction — the languages are merely separated so a mixed
    /// portfolio stays readable, and the header's 公開項目 count still matches
    /// what is on screen.
    struct LanguageGroup: Identifiable, Equatable {
        let language: TargetLanguage
        let items: [AtlasPublicItem]

        var id: TargetLanguage {
            self.language
        }

        var count: Int {
            self.items.count
        }
    }

    let handle: String
    /// True when this is the signed-in user looking at their own page. Passed in
    /// explicitly by the caller rather than inferred by comparing handles: before
    /// the public identity is confirmed the local username is a pre-seeded
    /// placeholder, so a comparison would answer the wrong question.
    let isSelf: Bool
    private(set) var author: AtlasAuthor?
    private(set) var items: [AtlasPublicItem] = []
    private(set) var groups: [LanguageGroup] = []
    private(set) var collections: [AtlasCollection] = []
    private(set) var phase: Phase = .loading

    /// Which half of the profile is on screen. Only meaningful when
    /// `showsSegmentedControl` is true; with no collections there is nothing to
    /// switch to and the items stand alone.
    var segment: Segment = .collections

    private let profiles: AuthorProfileLoading

    init(
        handle: String,
        isSelf: Bool = false,
        profiles: AuthorProfileLoading = AuthorProfileModule.shared
    ) {
        self.handle = handle
        self.isSelf = isSelf
        self.profiles = profiles
    }

    var errorMessage: String? {
        if case let .failed(message) = self.phase { return message }
        return nil
    }

    /// A switch is only offered when there is somewhere to switch to. Most
    /// authors have no collections, and a control that advertises an empty room
    /// is worse than no control: it reads as a feature that doesn't work.
    var showsSegmentedControl: Bool {
        !self.collections.isEmpty
    }

    /// What to render. Falls back to the items whenever the control is absent,
    /// so `segment` can never strand the page on an empty 合集 tab.
    var visibleSegment: Segment {
        self.showsSegmentedControl ? self.segment : .items
    }

    func load() async {
        self.phase = .loading
        do {
            let response = try await self.profiles.load(handle: self.handle, refresh: self.isSelf)
            self.author = response.author
            self.items = response.items
            self.groups = Self.grouped(response.items)
            self.collections = response.collections
            // Curated work is the stronger signal, so it leads when it exists.
            // Reset on every load: a reload that drops the last collection must
            // not leave the page pointing at a tab that no longer exists.
            self.segment = response.collections.isEmpty ? .items : .collections
            self.phase = .ready
        } catch APIError.notFound {
            self.clear()
            self.phase = .notFound
        } catch {
            self.clear()
            self.phase = .failed(tujiUserMessage(for: error))
        }
    }

    private func clear() {
        self.author = nil
        self.items = []
        self.groups = []
        self.collections = []
    }

    /// Groups by language in order of first appearance. The server sends items
    /// newest-first, so the language the author published in most recently leads
    /// — deterministic, and it puts their current work at the top.
    private static func grouped(_ items: [AtlasPublicItem]) -> [LanguageGroup] {
        var order: [TargetLanguage] = []
        var buckets: [TargetLanguage: [AtlasPublicItem]] = [:]
        for item in items {
            if buckets[item.targetLanguage] == nil { order.append(item.targetLanguage) }
            buckets[item.targetLanguage, default: []].append(item)
        }
        return order.map { LanguageGroup(language: $0, items: buckets[$0] ?? []) }
    }
}
