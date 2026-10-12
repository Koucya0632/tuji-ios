// 點數明細 — what the account holds, where it came from, and where it went.
//
// The server keeps one append-only ledger for every point movement
// (`/api/credits/ledger`), and it returns the current wallet beside each page.
// This turns that pair into what the screen prints. It is a value so the three
// things worth getting right — which movements are worth a row, what each one
// is called, and the balance after it — are asked without a screen.

import Foundation

/// One page of the ledger, newest first, with the wallet as of the read.
struct CreditLedgerPage: Decodable, Equatable {
    struct Entry: Decodable, Equatable, Identifiable {
        let id: String
        /// grant / reserve / commit / release / expire / refund / refund_reverse / compensate.
        let kind: String
        /// The change in points held. Zero for a reserve or a release, which
        /// move points between available and held without creating or spending any.
        let amount: Int
        /// What the movement was for — see `CreditStatement.Activity.init`.
        let reference: String
        let createdAt: String
    }

    let entries: [Entry]
    let wallet: CreditWallet
}

struct CreditStatement: Equatable {
    /// What a ledger movement was, in the app's own vocabulary. The wire has a
    /// `kind` and a free-form `reference`; this is the one place the two are read.
    enum Activity: Equatable {
        case askedAssistant
        case recognition
        case monthlyGift
        case checkIn
        case purchase
        case gift
        case expired
        case refund
        case returned
        case other

        init(kind: String, reference: String) {
            switch kind {
            case "commit":
                self = reference.hasPrefix("assistant:") ? .askedAssistant
                    : reference.hasPrefix("ai:") ? .recognition : .other
            case "grant":
                self = reference.hasPrefix("benefit:monthly") ? .monthlyGift
                    : reference.hasPrefix("benefit:check_in") ? .checkIn
                    : reference.hasPrefix("apple:") || reference.hasPrefix("play:") ? .purchase : .gift
            case "expire": self = .expired
            case "refund": self = .refund
            // A failed operation's points coming back, or a refund undone.
            case "compensate", "refund_reverse": self = .returned
            default: self = .other
            }
        }
    }

    struct Record: Equatable, Identifiable {
        let id: String
        let activity: Activity
        let date: Date?
        /// Signed: negative is spent.
        let amount: Int
        /// Points held once this movement had happened.
        let balanceAfter: Int
    }

    /// Where the spendable points came from. The three add up to `available`
    /// except for one-off adjustments, which land in `otherGift`.
    struct Sources: Equatable {
        let monthly: Int
        let checkIn: Int
        let purchased: Int
        let otherGift: Int
    }

    let available: Int
    /// Held by an operation still running. Not spendable, not yet spent.
    let reserved: Int
    let sources: Sources
    /// When this month's gift lapses.
    let monthlyExpires: Date?
    let records: [Record]

    init(page: CreditLedgerPage) {
        let wallet = page.wallet
        let monthly = wallet.monthlyAvailable ?? 0
        let checkIn = wallet.checkInAvailable ?? 0
        self.available = wallet.available
        self.reserved = wallet.reserved
        self.sources = Sources(
            monthly: monthly,
            checkIn: checkIn,
            purchased: wallet.paidAvailable,
            otherGift: max(0, wallet.giftAvailable - monthly - checkIn)
        )
        self.monthlyExpires = wallet.nextMonthlyResetAt.flatMap(Wire.parseISO)

        // The ledger carries changes, not balances. Walking back from what is
        // held now gives the balance after each one: the newest movement left
        // exactly today's total, and each older one left that minus everything
        // since. Held points count — a reservation has not spent anything.
        var balance = wallet.available + wallet.reserved
        var records: [Record] = []
        for entry in page.entries {
            // A reserve or a release changes no total; it would be a row that
            // says "0 點".
            if entry.amount != 0 {
                records.append(Record(
                    id: entry.id,
                    activity: Activity(kind: entry.kind, reference: entry.reference),
                    date: Wire.parseISO(entry.createdAt),
                    amount: entry.amount,
                    balanceAfter: balance
                ))
            }
            balance -= entry.amount
        }
        self.records = records
    }
}
