import Foundation
import FoundationExt
import StatementStore

public protocol OutgoingStatementRenewing: Sendable {
    /// Renews every due statement and returns once done, so a background task can await it.
    func renew() async
}

public struct OutgoingStatementRenewalDependencies<Input: OutgoingStatementInput>: Sendable {
    let store: any OutgoingStatementStoring<Input>
    let resolver: any StatementSignerResolving<Input>
    let service: any OutgoingStatementServicing<Input>
    let delivery: any OutgoingStatementDelivering<Input>

    public init(
        store: any OutgoingStatementStoring<Input>,
        resolver: any StatementSignerResolving<Input>,
        service: any OutgoingStatementServicing<Input>,
        delivery: any OutgoingStatementDelivering<Input>
    ) {
        self.store = store
        self.resolver = resolver
        self.service = service
        self.delivery = delivery
    }
}

/// Keeps published statements in the store: a fresh copy on period rollover, a re-publish when the current copy is
/// missing, and nothing once acknowledged. An optional bound abandons statements nobody acknowledges.
public final class OutgoingStatementRenewer<Input: OutgoingStatementInput>: @unchecked Sendable {
    private static var runKey: String { "run" }

    private let dependencies: OutgoingStatementRenewalDependencies<Input>
    private let bound: TimeInterval?
    private let dateProvider: DateProviding
    private let diagnostics: OutgoingStatementDiagnostics

    public init(
        dependencies: OutgoingStatementRenewalDependencies<Input>,
        bound: TimeInterval?,
        dateProvider: DateProviding,
        diagnostics: OutgoingStatementDiagnostics
    ) {
        self.dependencies = dependencies
        self.bound = bound
        self.dateProvider = dateProvider
        self.diagnostics = diagnostics
    }
}

extension OutgoingStatementRenewer: OutgoingStatementRenewing {
    public func renew() async {
        do {
            let candidates = try await dependencies.store.renewalCandidates()
            let period = try await dependencies.resolver.currentPeriod()
            let due = try await dueStatements(in: candidates, period: period)

            diagnostics.logger.debug("Renewal: \(due.count) of \(candidates.count) due in period \(period)")

            await republish(due, period: period)
            diagnostics.issues.renewalFailing.recordRecovery(for: Self.runKey)
        } catch {
            diagnostics.logger.error("Renewal failed: \(error)")
            diagnostics.issues.renewalFailing.recordFailure(for: Self.runKey, error: error, counters: [:])
        }
    }
}

private extension OutgoingStatementRenewer {
    func dueStatements(in candidates: [PublishedStatement<Input>], period: UInt32) async throws -> [Input] {
        let now = await dateProvider.read()
        var due: [Input] = []

        for candidate in candidates {
            let input = candidate.input

            if try await dependencies.store.isAcknowledged(input) {
                try await dependencies.store.markAcknowledged(input)
            } else if let bound, now.timeIntervalSince(candidate.createdAt) > bound {
                try await dependencies.store.markAbandoned(input)
            } else if candidate.period < period {
                due.append(input)
            } else if await !isStored(input, period: candidate.period) {
                due.append(input)
            }
        }

        return due
    }

    func isStored(_ input: Input, period: UInt32) async -> Bool {
        do {
            return try await dependencies.service.isStored(input, period: period)
        } catch {
            diagnostics.logger.error("Statement \(input.statementId) store check failed: \(error)")
            return true
        }
    }

    func republish(_ due: [Input], period: UInt32) async {
        guard !due.isEmpty else { return }

        let signers: [String: Result<StatementStoreSigning, Error>]

        do {
            signers = try await dependencies.resolver.resolve(due, period: period)
        } catch {
            diagnostics.logger.error("Renewal signers for \(period) not resolved: \(error)")
            return
        }

        await withTaskGroup(of: Void.self) { group in
            for input in due {
                guard let signer = signers[input.statementId] else { continue }

                group.addTask { await self.republish(input, signer: signer, period: period) }
            }
        }
    }

    func republish(_ input: Input, signer: Result<StatementStoreSigning, Error>, period: UInt32) async {
        do {
            try await dependencies.delivery.deliverOnce(input, signer: signer.get(), period: period)
        } catch let error as OutgoingStatementTerminalError {
            diagnostics.logger.debug("Statement \(input.statementId) renewal stopped: \(error)")
            try? await dependencies.store.markFailed(input, failure: .terminal(error))
        } catch {
            diagnostics.logger.error("Statement \(input.statementId) renewal into \(period) failed: \(error)")
            diagnostics.issues.renewalPublishFailed.recordFailure(
                for: "\(input.statementId)-\(period)",
                error: error,
                counters: [:]
            )
        }
    }
}
