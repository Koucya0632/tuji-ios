// 封鎖 — the account's list of authors whose public work should never surface.
//
// Tuji has no comments, no messages and no follows, so blocking cannot mean
// "stop them contacting me". It means "stop surfacing them to me", and it is
// deliberately one-way and invisible to the person blocked.
//
// **Discovery only.** Anything already saved stays: those words are already in
// the blocker's own 圖鑑 with their own SRS history, and the author is just
// their provenance. Removing them would destroy the blocker's study progress to
// punish someone else — the same reasoning that makes 取消公開 reversible
// rather than destructive.
//
// The list lives on the server (so it follows the account across devices) but is
// applied here, on the client. The four public 物見 endpoints are anonymous and
// share one CDN cache — `by-lemma` is hit on every word detail view at
// s-maxage=3600 — and a per-user filter would force `private, no-store` on all
// of them. A block list is small and changes rarely, so carrying it is cheap and
// the caches survive.

import Foundation
import Observation
import OSLog

/// Narrow seam so the store is testable without the network (ADR-0001).
@MainActor
protocol BlockListing {
    func blockedHandles() async throws -> [String]
    func block(handle: String) async throws
    func unblock(handle: String) async throws
}

@MainActor
@Observable
final class BlockStore {
    static let shared = BlockStore()

    private(set) var handles: Set<String> = []
    private(set) var loaded = false

    private let repo: BlockListing
    private let log = Logger(subsystem: "app.tuji.ios", category: "blocks")

    /// Not private: the seam only pays for itself if a test can stand a store up
    /// over a fake (ADR-0001). Production still goes through `.shared`.
    init(repo: BlockListing = LiveBlockRepository.shared) {
        self.repo = repo
    }

    /// Handles are the immutable TJ-UID, so a case-insensitive compare is safe
    /// and spares every caller from worrying about how it was spelled.
    func isBlocked(_ handle: String?) -> Bool {
        guard let handle, !handle.isEmpty, !self.handles.isEmpty else { return false }
        return self.handles.contains(handle.lowercased())
    }

    func loadIfNeeded() async {
        guard !self.loaded else { return }
        await self.reload()
    }

    func reload() async {
        do {
            let list = try await self.repo.blockedHandles()
            self.handles = Set(list.map { $0.lowercased() })
            self.loaded = true
        } catch {
            // Best-effort: a failed load must not make the feed unusable. It
            // fails *open* (nothing hidden) rather than closed — the alternative
            // is an empty 物見 whenever the network hiccups.
            self.log.error("block list load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Optimistic: the row disappears immediately, and only a server failure
    /// puts it back. Blocking is reversible, so an over-eager hide is cheap;
    /// a block that visibly does nothing is not.
    @discardableResult
    func block(handle: String) async -> Bool {
        let key = handle.lowercased()
        guard !key.isEmpty else { return false }
        self.handles.insert(key)
        do {
            try await self.repo.block(handle: handle)
            self.loaded = true
            return true
        } catch {
            self.handles.remove(key)
            self.log.error("block failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    @discardableResult
    func unblock(handle: String) async -> Bool {
        let key = handle.lowercased()
        let wasBlocked = self.handles.remove(key) != nil
        do {
            try await self.repo.unblock(handle: handle)
            return true
        } catch {
            if wasBlocked { self.handles.insert(key) }
            self.log.error("unblock failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Runs on sign-out beside `AtlasStore.reset()`, or the next account
    /// inherits this one's blocks.
    func reset() {
        self.handles = []
        self.loaded = false
    }
}

@MainActor
struct LiveBlockRepository: BlockListing {
    static let shared = LiveBlockRepository()

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func blockedHandles() async throws -> [String] {
        let response: BlockListResponse = try await self.api.get(.usersBlocks)
        return response.handles
    }

    func block(handle: String) async throws {
        let _: AckResponse = try await self.api.post(
            .usersBlocks,
            body: BlockRequest(handle: handle)
        )
    }

    func unblock(handle: String) async throws {
        try await self.api.delete(.usersBlock(handle: handle))
    }
}

struct BlockListResponse: Decodable {
    let handles: [String]
}

struct BlockRequest: Encodable {
    let handle: String
}
