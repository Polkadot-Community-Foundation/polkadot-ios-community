import Foundation
import StatementDelivery

protocol StatementDurabilityRenewing: Sendable {
    /// Renews allowances first, then every outgoing statement kind. A caller arriving while a run is live joins it.
    func renewAll() async -> StatementDurabilityRenewalReport
}

protocol AllowanceSlotsRenewing: Sendable {
    /// Releases allowances no feature needs any more, then renews every remaining one.
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

/// The single entry point for keeping statements and their allowances alive: the hourly loop, the foreground hook and
/// the background task all call it, so concurrent triggers share one run instead of publishing twice.
actor StatementDurabilityRenewalService {
    private let allowances: AllowanceSlotsRenewing
    private let renewers: StatementRenewerProviding
    private let logger: LoggerProtocol

    private var inFlight: Task<StatementDurabilityRenewalReport, Never>?

    init(allowances: AllowanceSlotsRenewing, renewers: StatementRenewerProviding, logger: LoggerProtocol) {
        self.allowances = allowances
        self.renewers = renewers
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
    /// A cancelled run is never handed out: it was expired by the OS or torn down, and the caller still needs one.
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

        return await StatementDurabilityRenewalReport(chatRequests: chatRequests, chatAcceptances: chatAcceptances)
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
