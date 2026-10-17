import Foundation
import Individuality
import IssueMonitoring
import StatementDelivery
import StatementStore

/// Picks request signers: the period's one-shot account when a notification slot can be claimed, otherwise the
/// username account, which links the request to us, only after the user consents.
final class ChatRequestSignerResolver: @unchecked Sendable {
    private let allocator: NotificationStatementAccountAllocating
    private let signerManager: StatementStoreSignerManaging
    private let fallback: NonPrivateSigningFallbacking
    private let renewalStarved: IssueDiagnostic
    private let logger: LoggerProtocol

    init(
        allocator: NotificationStatementAccountAllocating,
        signerManager: StatementStoreSignerManaging,
        fallback: NonPrivateSigningFallbacking,
        renewalStarved: IssueDiagnostic,
        logger: LoggerProtocol
    ) {
        self.allocator = allocator
        self.signerManager = signerManager
        self.fallback = fallback
        self.renewalStarved = renewalStarved
        self.logger = logger
    }
}

extension ChatRequestSignerResolver: StatementSignerResolving {
    func currentPeriod() async throws -> UInt32 {
        try await allocator.currentPeriod()
    }

    func maxStatementSize() async throws -> Int {
        try await allocator.maxStatementSize()
    }

    func resolve(
        _ inputs: [OutgoingChatRequestInput],
        period: UInt32
    ) async throws -> [String: Result<StatementStoreSigning, Error>] {
        let oneShots = try inputs.map { input in
            try (input, signerManager.makeSigner(for: input.oneShotKeyId(period: period)))
        }

        // One batch in the given order, so the newest requests win when slots run short.
        let claimed = try await Set(allocator.initiateAllocations(for: oneShots.map(\.1.accountId)))

        let resolved = await withTaskGroup(of: (String, Result<StatementStoreSigning, Error>).self) { group in
            for (input, oneShot) in oneShots {
                let isClaimed = claimed.contains(oneShot.accountId)
                group.addTask { await (input.statementId, self.resolve(input, oneShot: oneShot, isClaimed: isClaimed)) }
            }

            return await group.reduce(into: [String: Result<StatementStoreSigning, Error>]()) { $0[$1.0] = $1.1 }
        }

        reportStarvation(in: resolved, period: period)

        return resolved
    }
}

private extension ChatRequestSignerResolver {
    func resolve(
        _ input: OutgoingChatRequestInput,
        oneShot: StatementStoreSigning,
        isClaimed: Bool
    ) async -> Result<StatementStoreSigning, Error> {
        guard isClaimed else { return await identitySigner(for: input) }

        do {
            try await allocator.awaitAllocated(oneShot.accountId, timeout: ChatNotificationSlots.allocationTimeout)
            return .success(oneShot)
        } catch NotificationAllocationError.noFreeSlotInPeriod {
            return await identitySigner(for: input)
        } catch {
            return .failure(error)
        }
    }

    func identitySigner(for input: OutgoingChatRequestInput) async -> Result<StatementStoreSigning, Error> {
        do {
            return try await .success(fallback.identitySigner(for: input.session))
        } catch {
            return .failure(error)
        }
    }

    // Requests left with neither a slot nor the username account miss this period's copy.
    func reportStarvation(in resolved: [String: Result<StatementStoreSigning, Error>], period: UInt32) {
        let starved = resolved.values.filter { result in
            guard case let .failure(error) = result else { return false }
            return !(error is OutgoingStatementTerminalError)
        }.count

        guard starved > 0 else { return }

        logger.warning("\(starved) chat request(s) without a signer in period \(period)")
        renewalStarved.recordFailure(
            for: "\(period)",
            error: nil,
            counters: ["skipped": starved, "period": Int(period)]
        )
    }
}
