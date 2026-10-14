import Foundation

/// What the assistant home hands to a new conversation. Entering is always free;
/// even a paid intent must go through the conversation's explicit AI offer.
enum AssistantChatEntry: Hashable {
    case conversation
    case text(String)
    case intent(AssistantIntent)

    var focusesComposer: Bool {
        self == .conversation || self == .intent(.lookupPrompt)
    }

    static func question(_ draft: String) -> Self? {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : .text(text)
    }
}
