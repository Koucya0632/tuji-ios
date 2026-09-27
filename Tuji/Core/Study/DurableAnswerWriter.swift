// One durable SRS answer write: a few bounded retries against the network,
// then — on exhaustion — park the payload in the offline outbox (replayed on
// next launch/foreground by StudyAnswerOutbox). Non-throwing: parking IS the
// terminal fallback, so every call resolves to a `StudyWriteOutcome` the caller
// must handle.
//
// This consolidates the retry+park policy that used to live in TWO places with
// two code bodies — StudyRepository.submitAnswerBestEffort (which returned Void
// and dropped the mastery delta) and ReviewFlowCoordinator.persist (which
// re-hand-rolled the same loop precisely because it needed that delta). The
// writer keeps the delta by returning `.synced(response)`, so both study flows
// read one interface instead of duplicating durability.

import Foundation
import OSLog

private let log = Logger(subsystem: "app.tuji.ios", category: "answer-writer")

/// The result of a durable answer write. Exhaustive so callers can't silently
/// ignore a parked write (the bug that made offline new-word sessions look
/// fully saved).
enum StudyWriteOutcome {
    /// The server accepted the answer; the response carries any mastery /
    /// milestone deltas.
    case synced(StudyAnswerResponse)
    /// Every retry failed; the payload was parked in the durable outbox and
    /// will replay later. No response is available.
    case parked
    /// The server refused this answer for good (see `AnswerWriteFailure`).
    /// Neither retried nor parked: it would never succeed, and a parked
    /// permanent failure used to wedge the whole outbox behind it.
    case rejected
}

/// Which write failures are permanent. A permanent failure will never succeed
/// on replay — the card is gone (404), the account may not write it (403), the
/// write needs a plan (402), the request itself is refused (other 4xx). Those
/// must be dropped, not retried: `StudyAnswerOutbox.replay` stops at the first
/// failure, so one parked permanent failure blocked every answer queued behind
/// it, forever.
///
/// Everything else is transient and keeps the old retry-then-park behaviour:
/// offline, 5xx, 408/429, and 401 (the next attempt carries a refreshed
/// token). Unknown errors count as transient — dropping an answer is the worse
/// mistake of the two.
enum AnswerWriteFailure {
    static func isPermanent(_ error: Error) -> Bool {
        guard let api = error as? APIError else { return false }
        switch api {
        case .forbidden, .notFound, .paymentRequired, .conflict:
            return true
        case let .server(status, _):
            return (400..<500).contains(status) && status != 408 && status != 429
        case .unauthorized, .rateLimited, .atCapacity, .decoding, .transport, .missingBaseURL:
            return false
        }
    }
}

@MainActor
protocol DurableAnswerWriting {
    /// Submit one answer durably. Never throws — a write that can't reach the
    /// server is parked and reported as `.parked`.
    func submitAnswer(_ payload: StudyAnswerPayload) async -> StudyWriteOutcome
}

@MainActor
struct DurableAnswerWriter: DurableAnswerWriting {
    /// The network primitive. Injected (defaults to the live client) so the
    /// writer's retry/park behaviour is testable without hitting the network.
    var repository: StudyRepository = LiveStudyRepository.shared
    /// Where exhausted writes are parked. Injected so tests can point at a
    /// scratch file and assert what got parked.
    var outbox: StudyAnswerOutbox = .shared

    /// Network attempts before parking; backoff between them is 400ms, 800ms.
    private static let maxAttempts = 3

    func submitAnswer(_ payload: StudyAnswerPayload) async -> StudyWriteOutcome {
        for attempt in 0..<Self.maxAttempts {
            do {
                return try await .synced(self.repository.submitAnswer(payload))
            } catch where AnswerWriteFailure.isPermanent(error) {
                log.error(
                    "answer for card \(payload.cardId, privacy: .public) refused for good: \(error.localizedDescription, privacy: .public)"
                )
                return .rejected
            } catch {
                log.warning(
                    "answer write attempt \(attempt + 1, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                )
                if attempt < Self.maxAttempts - 1 {
                    try? await Task.sleep(for: .milliseconds(400 * (attempt + 1)))
                }
            }
        }
        // Retries exhausted — a dropped SRS write is user-visible damage (the
        // word stays 未學 and the daily goal miscounts), so park it durably.
        self.outbox.add(payload)
        return .parked
    }
}
