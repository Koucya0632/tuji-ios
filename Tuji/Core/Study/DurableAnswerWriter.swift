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
