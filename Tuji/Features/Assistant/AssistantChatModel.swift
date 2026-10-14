// 助手 — the conversation.
//
// It holds the messages and nothing else: what a message *means* belongs to the
// responder behind `AssistantResponding`. The conversation lives in memory for
// as long as the screen is on the stack and is not written anywhere — there is
// nothing in it the app does not already have.

import Observation
import SwiftUI

struct AssistantMessage: Identifiable, Equatable {
    enum Body: Equatable {
        case user(String)
        case mascot(AssistantReply)
    }

    let id: Int
    let body: Body
}

@MainActor
@Observable
final class AssistantChatModel {
    private(set) var messages: [AssistantMessage] = []
    /// A reply is on its way. Only 收藏的合集 takes long enough to see it.
    private(set) var replying = false

    private let responder: AssistantResponding
    private var task: Task<Void, Never>?
    private var nextId = 0
    /// Which question the pending reply answers — see `ask`.
    private var asked = 0
    private var started = false

    init(responder: AssistantResponding = TieredAssistantResponder()) {
        self.responder = responder
        self.append(.mascot(responder.greeting()))
    }

    /// The chips under the conversation: whatever the cat last offered.
    var suggestions: [AssistantIntent] {
        guard case let .mascot(reply) = self.messages.last?.body else { return [] }
        return reply.suggestions
    }

    /// A pushed detail's return fires onAppear again; the original question
    /// belongs to this conversation's creation, never to its next appearance.
    @discardableResult
    func start(_ entry: AssistantChatEntry) -> Bool {
        guard !self.started else { return false }
        self.started = true
        switch entry {
        case .conversation: break
        case let .text(text): self.send(text)
        case let .intent(.askModel(question)):
            // An entry cannot authorize spending. Let the responder offer AI.
            self.send(question)
        case let .intent(intent): self.choose(intent)
        }
        return true
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.append(.user(trimmed))
        self.ask { await $0.reply(toText: trimmed) }
    }

    func choose(_ intent: AssistantIntent) {
        self.append(.user(intent.chipTitle))
        self.ask { await $0.reply(to: intent) }
    }

    /// Await whatever is in flight (ADR-0001: a seam reaches only as far as a
    /// test can await).
    func settle() async {
        await self.task?.value
    }

    // MARK: - Internals

    /// One reply per question, and only for the latest one. A second question
    /// asked while the first is still reading the network would otherwise get
    /// its answer first and the stale one underneath it.
    private func ask(_ question: @escaping @MainActor (AssistantResponding) async -> AssistantReply?) {
        self.task?.cancel()
        self.asked += 1
        let ticket = self.asked
        self.replying = true
        self.task = Task { [weak self] in
            guard let self else { return }
            let reply = await question(self.responder)
            guard ticket == self.asked else { return }
            self.replying = false
            if let reply { self.append(.mascot(reply)) }
        }
    }

    private func append(_ body: AssistantMessage.Body) {
        self.messages.append(AssistantMessage(id: self.nextId, body: body))
        self.nextId += 1
    }
}
