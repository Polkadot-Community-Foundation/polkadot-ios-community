import Foundation
import Individuality
import MessageExchangeKit
import StatementStore

/// The account that signs a chat request statement, and the period it is funded for.
struct ChatRequestDeliverySigner {
    let signer: StatementStoreSigning
    let period: UInt32
}

protocol ChatRequestDeliveryAccountResolving {
    func maxStatementSize() async throws -> Int
    func resolveFirstDelivery(
        requestId: String,
        session: MessageExchange.SessionRequest
    ) async throws -> ChatRequestDeliverySigner
}

/// Picks the notification-funded account of the current period for a request's first delivery. Without a free
/// slot it signs with the username account, which links the request to us, only after the user consents.
final class ChatRequestDeliveryAccountResolver {
    static let allocationTimeout: Duration = .seconds(5 * 60)

    private let allocator: NotificationStatementAccountAllocating
    private let signerManager: ChatRequestSignerManaging
    private let fallback: NonPrivateSigningFallbacking

    init(
        allocator: NotificationStatementAccountAllocating,
        signerManager: ChatRequestSignerManaging,
        fallback: NonPrivateSigningFallbacking
    ) {
        self.allocator = allocator
        self.signerManager = signerManager
        self.fallback = fallback
    }
}

extension ChatRequestDeliveryAccountResolver: ChatRequestDeliveryAccountResolving {
    func maxStatementSize() async throws -> Int {
        try await allocator.maxStatementSize()
    }

    func resolveFirstDelivery(
        requestId: String,
        session: MessageExchange.SessionRequest
    ) async throws -> ChatRequestDeliverySigner {
        let period = try await allocator.currentPeriod()
        let anonymous = try signerManager.makeChatRequestSigner(for: requestId, period: period)
        let signer = try await fallback.claimedOrIdentity(anonymous, allocator: allocator, session: session)

        return ChatRequestDeliverySigner(signer: signer, period: period)
    }
}
