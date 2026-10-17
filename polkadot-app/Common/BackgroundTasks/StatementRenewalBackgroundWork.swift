import BackgroundExecution
import Coinage
import Foundation
import StatementDelivery

/// One background run: borrow the dashboard services (booting them headless when the app was not running), renew
/// statements and allowances while a recycling pass runs alongside, then give the services back.
struct StatementRenewalBackgroundWork: Sendable {
    func callAsFunction() async -> BackgroundTaskWorkOutcome {
        let manager = await DashboardServices.manager
        let launchKind = await manager.hasCoordinator ? "warm" : "cold"

        guard let lease = await manager.acquireDurability() else {
            return .skipped(reason: "notReady launchKind=\(launchKind)")
        }

        // Released after the run unwinds, never from the expiration handler, so stopping durability cannot race a
        // claim that is still in flight.
        defer { lease.release() }

        async let renewal = lease.coordinator.durabilityRenewal.renewAll()
        async let recycling = lease.coordinator.coinageService.runRecyclingPass()

        let fields = await Self.logFields(launchKind: launchKind, renewal: renewal, recycling: recycling)
        return .completed(logFields: fields)
    }
}

private extension StatementRenewalBackgroundWork {
    static func logFields(
        launchKind: String,
        renewal: StatementDurabilityRenewalReport,
        recycling: RecyclingPassOutcome
    ) -> String {
        [
            "launchKind=\(launchKind)",
            fields(prefix: "requests", renewal.chatRequests),
            fields(prefix: "acceptances", renewal.chatAcceptances),
            fields(recycling)
        ].joined(separator: " ")
    }

    static func fields(prefix: String, _ summary: OutgoingStatementRenewalSummary) -> String {
        guard summary.isComplete else { return "\(prefix)=incomplete" }

        return "\(prefix)Due=\(summary.due) \(prefix)Renewed=\(summary.republished) "
            + "\(prefix)Failed=\(summary.failed) \(prefix)MissedPeriods=\(summary.missedPeriods)"
    }

    static func fields(_ outcome: RecyclingPassOutcome) -> String {
        switch outcome {
        case .notReady:
            "recycling=notReady"
        case .failed:
            "recycling=failed"
        case let .completed(evaluatedCoins, gated, submitted):
            "recycleCoins=\(evaluatedCoins) recycleGated=\(gated) recycleSubmitted=\(submitted)"
        }
    }
}
