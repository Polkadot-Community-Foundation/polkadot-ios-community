import Foundation
import StatementDelivery

@testable import polkadot_app

/// Hands out renewers that report a fixed summary per statement kind.
struct StatementRenewerProviderStub: StatementRenewerProviding {
    let chatRequests: OutgoingStatementRenewalSummary
    let chatAcceptances: OutgoingStatementRenewalSummary

    func makeChatRequestRenewer() async throws -> OutgoingStatementRenewing {
        FixedStatementRenewer(summary: chatRequests)
    }

    func makeChatAcceptanceRenewer() async throws -> OutgoingStatementRenewing {
        FixedStatementRenewer(summary: chatAcceptances)
    }
}

struct FixedStatementRenewer: OutgoingStatementRenewing {
    let summary: OutgoingStatementRenewalSummary

    func renew() async -> OutgoingStatementRenewalSummary {
        summary
    }
}
