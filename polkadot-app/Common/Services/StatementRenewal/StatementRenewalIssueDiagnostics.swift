import Foundation
import IssueMonitoring
import StatementDelivery

/// Reports a statement kind going a whole period without a published copy: the peer may have missed it, which is
/// what renewal exists to prevent. Once per lapse; a complete run without a gap resets it.
struct StatementRenewalIssueDiagnostics: Sendable {
    private static let lapseKey = "missed-period"

    let chatRequestsMissedPeriod: IssueDiagnostic
    let chatAcceptancesMissedPeriod: IssueDiagnostic

    func record(_ report: StatementDurabilityRenewalReport) {
        record(report.chatRequests, in: chatRequestsMissedPeriod)
        record(report.chatAcceptances, in: chatAcceptancesMissedPeriod)
    }
}

extension StatementRenewalIssueDiagnostics {
    static func make(reporter: IssueReporting) -> Self {
        guard IssueMonitoringFactory.isReportingSupported else {
            return Self(
                chatRequestsMissedPeriod: NoopIssueDiagnostic(),
                chatAcceptancesMissedPeriod: NoopIssueDiagnostic()
            )
        }

        return Self(
            chatRequestsMissedPeriod: ThresholdIssueDiagnostic(
                flow: "chat-request",
                kind: "renewal-missed-period",
                reporter: reporter
            ),
            chatAcceptancesMissedPeriod: ThresholdIssueDiagnostic(
                flow: "chat-acceptance",
                kind: "renewal-missed-period",
                reporter: reporter
            )
        )
    }
}

private extension StatementRenewalIssueDiagnostics {
    func record(_ summary: OutgoingStatementRenewalSummary, in diagnostic: IssueDiagnostic) {
        guard summary.isComplete else { return }

        guard summary.statementsWithMissedPeriods > 0 else {
            diagnostic.recordRecovery(for: Self.lapseKey)
            return
        }

        diagnostic.recordFailure(
            for: Self.lapseKey,
            error: nil,
            counters: [
                "statements": summary.statementsWithMissedPeriods,
                "missedPeriods": summary.missedPeriods
            ]
        )
    }
}
