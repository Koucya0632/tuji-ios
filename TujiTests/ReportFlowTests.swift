// Pins the 檢舉 flow shared by 物見詳情, 合集詳情 and 作者主頁.
//
// THE RED LINE: 「已收到檢舉」 must mean the server accepted it. Two of the three
// screens used to set that flag *before* the write and swallow the result with
// `try?`, so a 檢舉 that 401'd, 429'd or never left the device told the user it
// had been received — and the moderation queue never saw it. Nobody could catch
// that, because both screens held `private let reporter =
// LiveAtlasRepository.shared` with no init seam for a fake to replace.
//
// The other half of the contract is that one module now serves all three
// targets, so the three cannot drift apart again.

import Testing
@testable import Tuji

@MainActor
struct ReportFlowTests {
    @Test("a failed 檢舉 never reads as sent")
    func failureIsNotSent() async {
        let fake = FakeReportSubmitting()
        fake.result = .failure(ReportFakeError.boom)
        let flow = ReportFlow(submitter: fake)

        await flow.submit(.item(slug: "s1"), reason: .spam)

        #expect(!flow.isSent)
        #expect(flow.errorMessage != nil)
    }

    @Test("a 檢舉 is only sent once the server has accepted it")
    func successIsSent() async {
        let fake = FakeReportSubmitting()
        let flow = ReportFlow(submitter: fake)

        await flow.submit(.item(slug: "s1"), reason: .spam)

        #expect(flow.isSent)
        #expect(fake.submitted.count == 1)
    }

    @Test("all three targets reach the submitter unchanged")
    func everyTargetIsCarried() async {
        let fake = FakeReportSubmitting()
        let flow = ReportFlow(submitter: fake)

        await flow.submit(.item(slug: "item-1"), reason: .spam)
        await flow.submit(.collection(slug: "coll-1"), reason: .inappropriate)
        await flow.submit(.author(handle: "TJ00000001"), reason: .spam)

        #expect(fake.submitted == [
            .item(slug: "item-1"),
            .collection(slug: "coll-1"),
            .author(handle: "TJ00000001")
        ])
    }

    @Test("beginning a 檢舉 presents the sheet and remembers the target")
    func beginPresents() {
        let flow = ReportFlow(submitter: FakeReportSubmitting())

        flow.begin(.collection(slug: "c9"))

        #expect(flow.isPresented)
        #expect(flow.target == .collection(slug: "c9"))
    }

    @Test("a retry after a failure can still succeed")
    func retryAfterFailureSucceeds() async {
        // The screens disable the row only on `isSent`, so a failed attempt
        // must leave the flow usable rather than stuck in `.failed`.
        let fake = FakeReportSubmitting()
        fake.result = .failure(ReportFakeError.boom)
        let flow = ReportFlow(submitter: fake)
        await flow.submit(.author(handle: "TJ1"), reason: .spam)
        #expect(!flow.isSent)

        fake.result = .success(())
        await flow.submit(.author(handle: "TJ1"), reason: .spam)

        #expect(flow.isSent)
        #expect(flow.errorMessage == nil)
    }
}

private enum ReportFakeError: Error {
    case boom
}

@MainActor
private final class FakeReportSubmitting: ReportSubmitting {
    var result: Result<Void, Error> = .success(())
    private(set) var submitted: [ReportTarget] = []

    func submit(_ target: ReportTarget, reason _: AtlasReportReason, detail _: String?) async throws {
        self.submitted.append(target)
        try self.result.get()
    }
}
