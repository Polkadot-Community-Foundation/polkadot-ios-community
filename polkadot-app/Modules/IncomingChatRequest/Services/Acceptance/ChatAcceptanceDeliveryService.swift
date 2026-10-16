import BackgroundExecution
import Foundation
import Individuality

protocol ChatAcceptanceDelivering: Sendable {
    /// Publishes a recorded acceptance for the first time, retrying with backoff while it is still unpublished.
    func deliverUntilDone(messageId: String) async
}

struct ChatAcceptanceDeliveryDependencies {
    let store: ChatAcceptanceStoring
    let allocator: NotificationStatementAccountAllocating
    let signers: ChatAcceptanceSigning
    let statementService: ChatAcceptanceStatementServicing
    let notifier: ChatAcceptanceNotifying
    let fallback: NonPrivateSigningFallbacking
}

/// First publication of acceptances from the current period's one-shot account, or from the username account
/// with the user's consent when no slot is free.
final class ChatAcceptanceDeliveryService: @unchecked Sendable {
    private static let firstRetryDelay: Duration = .seconds(2)
    private static let maxRetryDelay: Duration = .seconds(5 * 60)
    private static let maxBackoffDoublings = 8

    private let dependencies: ChatAcceptanceDeliveryDependencies
    private let execution: ChatRequestDeliveryExecution
    private let issueDiagnostics: ChatAcceptanceIssueDiagnostics
    private let logger: LoggerProtocol

    init(
        dependencies: ChatAcceptanceDeliveryDependencies,
        execution: ChatRequestDeliveryExecution,
        issueDiagnostics: ChatAcceptanceIssueDiagnostics,
        logger: LoggerProtocol
    ) {
        self.dependencies = dependencies
        self.execution = execution
        self.issueDiagnostics = issueDiagnostics
        self.logger = logger
    }
}

extension ChatAcceptanceDeliveryService: ChatAcceptanceDelivering {
    func deliverUntilDone(messageId: String) async {
        var attempt = 0

        while await isAwaitingPublication(messageId) {
            do {
                try await execution.backgroundExecutor.execute { try await self.deliver(messageId: messageId) }
                issueDiagnostics.publishFailing.recordRecovery(for: messageId)
                return
            } catch ChatSigningConsentError.declined {
                await markFailedAfterDecline(messageId)
                return
            } catch {
                attempt += 1
                logger.error("Chat acceptance \(messageId) attempt \(attempt) failed: \(error)")
                issueDiagnostics.publishFailing.recordFailure(for: messageId, error: error, counters: [:])

                do {
                    try await execution.clock.sleep(for: Self.retryDelay(forAttempt: attempt))
                } catch {
                    return
                }
            }
        }
    }
}

private extension ChatAcceptanceDeliveryService {
    func deliver(messageId: String) async throws {
        guard let candidate = try await dependencies.store.acceptance(messageId: messageId) else { return }

        let period = try await dependencies.allocator.currentPeriod()
        let oneShot = try dependencies.signers.signer(requestId: candidate.requestId, period: period)
        let signer = try await dependencies.fallback.claimedOrIdentity(
            oneShot.signer,
            allocator: dependencies.allocator,
            session: candidate.session
        )

        try await dependencies.statementService.send(candidate, signer: signer)
        try await dependencies.store.markPublished(candidate, period: period)
        await dependencies.notifier.notify(candidate)
    }

    func markFailedAfterDecline(_ messageId: String) async {
        logger.debug("Chat acceptance \(messageId) declined to sign with the username")

        do {
            guard let candidate = try await dependencies.store.acceptance(messageId: messageId) else { return }
            try await dependencies.store.markFailed(candidate)
        } catch {
            logger.error("Chat acceptance \(messageId) not marked failed: \(error)")
        }
    }

    func isAwaitingPublication(_ messageId: String) async -> Bool {
        guard !Task.isCancelled else { return false }

        do {
            return try await dependencies.store.isAwaitingPublication(messageId: messageId)
        } catch {
            logger.error("Chat acceptance \(messageId) state unreadable: \(error)")
            return false
        }
    }

    static func retryDelay(forAttempt attempt: Int) -> Duration {
        let doublings = min(attempt, maxBackoffDoublings)
        return min(firstRetryDelay * (1 << doublings), maxRetryDelay)
    }
}
