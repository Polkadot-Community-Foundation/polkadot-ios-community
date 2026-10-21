import Foundation
import StatementDelivery

protocol StatementDurabilityRenewing: Sendable {
    func renewAll() async -> StatementDurabilityRenewalReport
}

protocol AllowanceSlotsRenewing: Sendable {
    func renewAllowanceSlots() async
}

protocol StatementRenewerProviding: Sendable {
    func makeChatRequestRenewer() async throws -> OutgoingStatementRenewing
    func makeChatAcceptanceRenewer() async throws -> OutgoingStatementRenewing
}

struct StatementDurabilityRenewalReport: Sendable, Equatable {
    let chatRequests: OutgoingStatementRenewalSummary
    let chatAcceptances: OutgoingStatementRenewalSummary

    static let cancelled = StatementDurabilityRenewalReport(chatRequests: .incomplete, chatAcceptances: .incomplete)
}

/// Every trigger goes through here, so concurrent ones share one run instead of publishing twice.
actor StatementDurabilityRenewalService {
    private let allowances: AllowanceSlotsRenewing
    private let renewers: StatementRenewerProviding
    private let issues: StatementRenewalIssueDiagnostics
    private let logger: LoggerProtocol

    private var inFlight: Task<StatementDurabilityRenewalReport, Never>?

    init(
        allowances: AllowanceSlotsRenewing,
        renewers: StatementRenewerProviding,
        issues: StatementRenewalIssueDiagnostics,
        logger: LoggerProtocol
    ) {
        self.allowances = allowances
        self.renewers = renewers
        self.issues = issues
        self.logger = logger
    }
}

extension StatementDurabilityRenewalService: StatementDurabilityRenewing {
    func renewAll() async -> StatementDurabilityRenewalReport {
        let run = liveRun()

        let report = await withTaskCancellationHandler {
            await run.value
        } onCancel: {
            run.cancel()
        }

        if inFlight == run {
            inFlight = nil
        }

        return report
    }
}

private extension StatementDurabilityRenewalService {
    /// A cancelled run was expired or torn down, and the next caller still needs a real one.
    func liveRun() -> Task<StatementDurabilityRenewalReport, Never> {
        if let inFlight, !inFlight.isCancelled {
            return inFlight
        }

        let run = Task { await performRun() }
        inFlight = run
        return run
    }

    func performRun() async -> StatementDurabilityRenewalReport {
        await allowances.renewAllowanceSlots()

        guard !Task.isCancelled else { return .cancelled }

        async let chatRequests = renew(.chatRequests)
        async let chatAcceptances = renew(.chatAcceptances)

        let report = await StatementDurabilityRenewalReport(
            chatRequests: chatRequests,
            chatAcceptances: chatAcceptances
        )
        issues.record(report)
        return report
    }

    enum StatementKind {
        case chatRequests
        case chatAcceptances
    }

    func renew(_ kind: StatementKind) async -> OutgoingStatementRenewalSummary {
        do {
            let renewer =
                switch kind {
                case .chatRequests: try await renewers.makeChatRequestRenewer()
                case .chatAcceptances: try await renewers.makeChatAcceptanceRenewer()
                }

            return await renewer.renew()
        } catch {
            logger.error("Statement renewer unavailable: \(error)")
            return .incomplete
        }
    }
}
