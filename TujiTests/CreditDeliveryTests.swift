import Testing
@testable import Tuji

struct CreditDeliveryTests {
    @Test
    func finishRequiresADurableMatchingDelivery() {
        for state in ["credited", "duplicate", "revoked"] {
            let ack = CreditPurchaseDelivery(
                deliveryAck: true,
                status: state,
                transactionId: "123",
                environment: "sandbox"
            )
            #expect(ack.permitsFinish(transactionId: "123"))
            #expect(!ack.permitsFinish(transactionId: "456"))
        }
        #expect(!CreditPurchaseDelivery(
            deliveryAck: false,
            status: "credited",
            transactionId: "123",
            environment: "sandbox"
        ).permitsFinish(transactionId: "123"))
        #expect(!CreditPurchaseDelivery(
            deliveryAck: true,
            status: "pending",
            transactionId: "123",
            environment: "sandbox"
        ).permitsFinish(transactionId: "123"))
        #expect(!CreditPurchaseDelivery(
            deliveryAck: true,
            status: "credited",
            transactionId: "123",
            environment: "LocalTesting"
        ).permitsFinish(transactionId: "123"))
    }

    @Test
    func walletVersionsDoNotTruncateBigIntegers() {
        let benefits = CreditWallet.Benefits(
            monthlyClaimed: false,
            checkedInToday: false,
            checkInGrantedThisMonth: 0,
            hasLifetime: true
        )
        func wallet(_ version: String) -> CreditWallet {
            CreditWallet(
                available: 0,
                reserved: 0,
                paidAvailable: 0,
                giftAvailable: 0,
                walletVersion: version,
                environment: "sandbox",
                reconciliationRequired: false,
                benefits: benefits
            )
        }
        #expect(wallet("9223372036854775807").isNewer(than: wallet("9007199254740993")))
        #expect(!wallet("9").isNewer(than: wallet("10")))
    }

    @Test
    func deliveryCannotFinishAgainstAnotherStoreEnvironment() {
        let ack = CreditPurchaseDelivery(
            deliveryAck: true,
            status: "credited",
            transactionId: "123",
            environment: "sandbox"
        )
        #expect(ack.permitsFinish(transactionId: "123", environment: "sandbox"))
        #expect(!ack.permitsFinish(transactionId: "123", environment: "production"))
    }

    @Test
    func sandboxCatalogRejectsProductionAndUnknownEnvironments() {
        func catalog(_ environment: String) -> CreditCatalog {
            CreditCatalog(
                billingMode: "credits",
                environment: environment,
                purchaseEnabled: true,
                proNewPurchaseEnabled: false,
                operationsEnabled: false,
                monthlyEnabled: true,
                checkInEnabled: true,
                packs: []
            )
        }
        #expect(catalog("sandbox").matches(environment: "sandbox"))
        #expect(!catalog("production").matches(environment: "sandbox"))
        #expect(!catalog("LocalTesting").matches(environment: "sandbox"))
        #expect(!catalog("LocalTesting").matches(environment: "LocalTesting"))
    }

    @MainActor @Test
    func choosingACandidateFillsTheFormAndEditsLeaveTheSuggestion() {
        let model = CreditCaptureModel()
        model.select(CreditCandidate(id: "c1", level: "primary", label: "cat", zhHant: "貓", gloss: nil))
        #expect(model.lemma == "cat")
        #expect(model.displayZhHant == "貓")
        #expect(model.isStillSuggested(.lemma))
        model.lemma = "kitten"
        #expect(!model.isStillSuggested(.lemma))
        #expect(model.isStillSuggested(.zhHant))
        model.select(CreditCandidate(id: "c2", level: "fine", label: "tabby", zhHant: "虎斑貓", gloss: "tabby cat"))
        #expect(model.lemma == "tabby")
        #expect(model.displayGloss == "tabby cat")
        #expect(model.selectedCandidateId == "c2")
        model.lemma = "  "
        #expect(!model.canConfirm)
    }
}
