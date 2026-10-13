import Foundation
import FoundationExt
import Individuality
import MessageExchangeKit
import StatementStore

protocol ChatAcceptancePublishing: Sendable {
    func sync() async
}

struct ChatAcceptancePublisherDependencies {
    let store: ChatAcceptanceStoring
    let allocator: NotificationStatementAccountAllocating
    let signManager: StatementStoreSignerManaging
    let requestFactory: IdentityRouteRequestMaking
    let submitter: StatementStoreSubmitting
    let deviceActivator: SenderDeviceActivating
}

/// Publishes acceptances on the identity route from a one-shot account per period
/// until the requester's device-route traffic acknowledges them.
actor ChatAcceptancePublisher {
    private let dependencies: ChatAcceptancePublisherDependencies
    private let dateProvider: DateProviding
    private let issueDiagnostics: ChatAcceptanceIssueDiagnostics
    private let logger: LoggerProtocol

    private var isSyncing = false
    private var needsResync = false

    init(
        dependencies: ChatAcceptancePublisherDependencies,
        dateProvider: DateProviding,
        issueDiagnostics: ChatAcceptanceIssueDiagnostics,
        logger: LoggerProtocol
    ) {
        self.dependencies = dependencies
        self.dateProvider = dateProvider
        self.issueDiagnostics = issueDiagnostics
        self.logger = logger
    }
}

extension ChatAcceptancePublisher: ChatAcceptancePublishing {
    // Actor methods interleave at suspension points, so a sync requested mid-run is folded into one more pass.
    func sync() async {
        guard !isSyncing else {
            needsResync = true
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        repeat {
            needsResync = false
            await syncPendingAcceptances()
        } while needsResync
    }
}

private extension ChatAcceptancePublisher {
    static let renewalBound: TimeInterval = 7 * 86_400

    func syncPendingAcceptances() async {
        do {
            let candidates = try await dependencies.store.pendingAcceptances()

            guard !candidates.isEmpty else { return }

            let period = try await dependencies.allocator.currentPeriod()
            let now = await dateProvider.read()

            for candidate in candidates {
                await process(candidate, period: period, now: now)
            }
        } catch {
            logger.error("Chat acceptance sync failed: \(error)")
        }
    }

    func process(_ candidate: ChatAcceptanceCandidate, period: UInt32, now: Date) async {
        let messageId = candidate.message.messageId

        do {
            if try await dependencies.store.isAcknowledged(candidate) {
                try await dependencies.store.markAcknowledged(candidate)
                return
            }

            guard candidate.period != period else { return }

            guard now.timeIntervalSince(Date.fromChatTimestamp(candidate.message.timestamp)) <= Self.renewalBound
            else {
                issueDiagnostics.unacknowledged.recordFailure(for: messageId, error: nil, counters: [:])
                return
            }

            try await publish(candidate, period: period)
            issueDiagnostics.publishFailing.recordRecovery(for: messageId)
        } catch {
            logger.error("Chat acceptance \(messageId) not published in \(period): \(error)")
            issueDiagnostics.publishFailing.recordFailure(for: messageId, error: error, counters: [:])
        }
    }

    func publish(_ candidate: ChatAcceptanceCandidate, period: UInt32) async throws {
        guard let remoteMessage = candidate.message.toRemote() else {
            throw ChatAcceptancePublisherError.notRemote
        }

        let signer = try dependencies.signManager.makeSigner(
            for: ChatKeyPaths.accept(requestId: candidate.requestId, period: period)
        )

        try await dependencies.allocator.allocate(
            signer.accountId,
            timeout: ChatRequestDeliveryAccountResolver.allocationTimeout
        )

        let statement = try dependencies.requestFactory.makeRequestStatement(
            for: candidate.session,
            requestId: candidate.message.messageId,
            message: Chat.OpaqueMessage(remoteMessage: remoteMessage),
            signer: signer
        )

        try await dependencies.submitter.submitStatement(with: statement)

        if candidate.period == nil {
            try await dependencies.deviceActivator.activate(
                requestId: candidate.requestId,
                peerAccountId: candidate.session.peer.accountId
            )
        }

        try await dependencies.store.markPublished(candidate, period: period)
    }
}

enum ChatAcceptancePublisherError: Error {
    case notRemote
}
