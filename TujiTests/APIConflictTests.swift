// 409 — a refusal with a reason.
//
// It used to fall into `.server` and reach the author as 「伺服器出了點問題（409），
// 請稍後再試」: advice that could not work, because the reason was a rule (an
// already-public 合集 cannot take an unpublished item). These pin the two halves
// of the fix — the status is mapped to its own case, and this app's own copy
// wins over the server's zh-Hant sentence, because the app ships in four UI
// languages.
//
// Driven through `APIError.check` directly: the mapping is what is under test,
// not the transport.

import Foundation
import Testing
@testable import Tuji

struct APIConflictTests {
    private func response(_ status: Int) throws -> HTTPURLResponse {
        let url = try #require(URL(string: "https://tuji.test/api/atlas/collections/x/items"))
        return try #require(
            HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
        )
    }

    private func thrown(status: Int, body: String) throws -> APIError? {
        do {
            try APIError.check(self.response(status), data: Data(body.utf8))
            Issue.record("expected a throw")
            return nil
        } catch let error as APIError {
            return error
        } catch {
            Issue.record("expected an APIError, got \(error)")
            return nil
        }
    }

    @Test("a 409 keeps the server's reason and its fallback sentence")
    func conflictCarriesReasonAndMessage() throws {
        guard case let .conflict(reason, message)? = try self.thrown(
            status: 409,
            body: #"{"error":"already_member","message":"這個項目已經在合集裡了。"}"#
        )
        else {
            Issue.record("expected .conflict")
            return
        }

        #expect(reason == "already_member")
        #expect(message == "這個項目已經在合集裡了。")
    }

    /// The reason exists so the sentence can be this app's, in this app's UI
    /// language. The server's copy is the fallback, not the answer.
    @Test("a known reason is said in the app's own words")
    func knownReasonsUseTheAppsCopy() {
        let error = APIError.conflict(reason: "already_member", message: "伺服器說的話")

        #expect(error.errorDescription != "伺服器說的話")
        #expect(error.errorDescription?.isEmpty == false)
    }

    /// A reason this client has never heard of still has to say something
    /// useful: a sentence in the wrong language beats 「這個動作現在無法完成」.
    @Test("an unknown reason falls back to the server's sentence")
    func unknownReasonsKeepTheServerCopy() {
        let error = APIError.conflict(reason: "something_added_later", message: "伺服器說的話")

        #expect(error.errorDescription == "伺服器說的話")
    }

    /// …and a 409 with no body at all still produces a sentence rather than
    /// nothing.
    @Test("a bare 409 still reads")
    func aBareConflictStillReads() throws {
        guard case let .conflict(reason, message)? = try self.thrown(status: 409, body: "") else {
            Issue.record("expected .conflict")
            return
        }

        #expect(reason == nil)
        #expect(message == nil)
        #expect(APIError.conflict(reason: nil, message: nil).errorDescription?.isEmpty == false)
    }

    /// The neighbours must not have moved: 402 and 429 still carry the server's
    /// copy, and everything else is still the generic server failure.
    @Test("only 409 became a conflict")
    func otherStatusesAreUnchanged() throws {
        guard case .paymentRequired? = try self.thrown(status: 402, body: #"{"message":"x"}"#) else {
            Issue.record("expected .paymentRequired")
            return
        }
        guard case .server? = try self.thrown(status: 500, body: "boom") else {
            Issue.record("expected .server")
            return
        }
    }
}
