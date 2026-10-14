import AsyncExtensions
import Foundation
import MessageExchangeKit
import SDKLogger
import StatementStore
import SubstrateSdk

struct ReceivedChatAcceptance: Equatable {
    let peerAccountId: AccountId
    let requestId: String
    let device: Chat.PeerDevice
}

protocol ChatAcceptanceListening {
    /// Acceptances the peers of pending outgoing requests publish on the identity route.
    func subscribe(to requests: [MessageExchange.SessionRequest]) -> AnyAsyncSequence<ReceivedChatAcceptance>
}

/// Receives acceptances outside chat sessions: a requester has no session until it knows the acceptor's device.
final class ChatAcceptanceListener {
    private let requestFactory: IdentityRouteRequestMaking
    private let connection: StatementStoreConnecting
    private let logger: SDKLoggerProtocol
    private let workQueue = DispatchQueue(label: "io.chat.acceptance.listener.queue")

    init(requestFactory: IdentityRouteRequestMaking, connection: StatementStoreConnecting, logger: SDKLoggerProtocol) {
        self.requestFactory = requestFactory
        self.connection = connection
        self.logger = logger
    }
}

extension ChatAcceptanceListener: ChatAcceptanceListening {
    func subscribe(to requests: [MessageExchange.SessionRequest]) -> AnyAsyncSequence<ReceivedChatAcceptance> {
        AsyncStream<ReceivedChatAcceptance> { continuation in
            let subscriptions = requests.compactMap { request in
                startSubscription(for: request) { continuation.yield($0) }
            }

            continuation.onTermination = { _ in
                subscriptions.forEach { $0.stop() }
            }
        }
        .eraseToAnyAsyncSequence()
    }
}

private extension ChatAcceptanceListener {
    func startSubscription(
        for request: MessageExchange.SessionRequest,
        onAcceptance: @escaping (ReceivedChatAcceptance) -> Void
    ) -> StatementSubscription? {
        do {
            let subscription = try StatementSubscription(
                connection: connection,
                topicFilter: .matchAll([requestFactory.peerRequestTopic(for: request)]),
                proofVerifier: StatementPermissiveProofVerifier(),
                workQueue: workQueue,
                logger: logger
            )

            subscription.start { [weak self] statement in
                self?.acceptances(in: statement, for: request).forEach(onAcceptance)
                return true
            }

            return subscription
        } catch {
            logger.error("Can't listen for acceptance from \(request.peer.accountId.toHex()): \(error)")
            return nil
        }
    }

    // Routed by topic only: every period's copy comes from a different one-shot signer.
    func acceptances(in statement: Statement, for request: MessageExchange.SessionRequest) -> [ReceivedChatAcceptance] {
        do {
            guard let payload = statement.getScaleEncodedPayload() else { return [] }

            let peerRequest: MessageExchange.Request<Chat.OpaqueMessage>? = try requestFactory.decodePeerRequest(
                payload,
                for: request
            )

            return (peerRequest?.messages ?? []).compactMap { message in
                guard case let .multiChatAccepted(accepted) = message.remoteMessage.versioned.ensureV1()?.content else {
                    return nil
                }

                return ReceivedChatAcceptance(
                    peerAccountId: request.peer.accountId,
                    requestId: accepted.requestId,
                    device: accepted.device
                )
            }
        } catch {
            logger.error("Can't decode acceptance statement: \(error)")
            return []
        }
    }
}
