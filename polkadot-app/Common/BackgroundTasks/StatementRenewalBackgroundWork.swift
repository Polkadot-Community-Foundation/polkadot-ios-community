import BackgroundExecution
import Foundation
import StatementDelivery

/// One background run: borrow the dashboard services (booting them headless when the app was not running) and renew
/// statements and allowances. Coinage setup inside the durability part also starts the recycling evaluator's own
/// schedule, which recycles for as long as the process runs.
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

        let renewal = await lease.coordinator.durabilityRenewal.renewAll()

        return .completed(logFields: Self.logFields(launchKind: launchKind, renewal: renewal))
    }
}

private extension StatementRenewalBackgroundWork {
    static func logFields(launchKind: String, renewal: StatementDurabilityRenewalReport) -> String {
        [
            "launchKind=\(launchKind)",
            fields(prefix: "requests", renewal.chatRequests),
            fields(prefix: "acceptances", renewal.chatAcceptances)
        ].joined(separator: " ")
    }

    static func fields(prefix: String, _ summary: OutgoingStatementRenewalSummary) -> String {
        guard summary.isComplete else { return "\(prefix)=incomplete" }

        return "\(prefix)Due=\(summary.due) \(prefix)Renewed=\(summary.republished) "
            + "\(prefix)Failed=\(summary.failed) \(prefix)MissedPeriods=\(summary.missedPeriods)"
    }
}
