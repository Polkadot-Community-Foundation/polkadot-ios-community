import Foundation
import Individuality
import MessageExchangeKit
import StatementStore

/// Notification-funded statements (requests, acceptances) toward the session's peer.
extension NonPrivateSigningFallbacking {
    /// `oneShot` once its notification slot is claimed; the identity account, with consent, when no slot is free.
    func claimedOrIdentity(
        _ oneShot: StatementStoreSigning,
        allocator: NotificationStatementAccountAllocating,
        session: MessageExchange.SessionRequest
    ) async throws -> StatementStoreSigning {
        do {
            try await allocator.allocate(
                oneShot.accountId,
                timeout: ChatRequestDeliveryAccountResolver.allocationTimeout
            )
            return oneShot
        } catch NotificationAllocationError.noFreeSlotInPeriod {
            return try await identitySigner(for: session)
        }
    }

    func identitySigner(for session: MessageExchange.SessionRequest) async throws -> StatementStoreSigning {
        try await identitySigner(for: session.peer.accountId, ownSignKeyId: session.own.signKeyId)
    }

    func consentedSigner(for session: MessageExchange.SessionRequest) async throws -> StatementStoreSigning? {
        try await consentedSigner(for: session.peer.accountId, ownSignKeyId: session.own.signKeyId)
    }
}
