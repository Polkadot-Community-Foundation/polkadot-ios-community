import Foundation
import SDKLogger
import StatementStore

public protocol IdentityRouteRequestMaking {
    /// The topic the peer publishes its identity-route requests under.
    func peerRequestTopic(for request: MessageExchange.SessionRequest) throws -> Data

    /// Decodes a peer's identity-route request; nil when the payload is not a request.
    func decodePeerRequest<M: MessageExchange.CodableMessage>(
        _ scaleEncodedPayload: Data,
        for request: MessageExchange.SessionRequest
    ) throws -> MessageExchange.Request<M>?
}

public final class IdentityRouteRequestFactory {
    private let encryptionManager: MessageExchangeEncryptionManaging
    private let signerManager: StatementStoreSignerManaging
    private let sessionIdFactory: PeerSessionIdFactoryProtocol
    private let logger: SDKLoggerProtocol?

    public init(
        encryptionManager: MessageExchangeEncryptionManaging,
        signerManager: StatementStoreSignerManaging,
        sessionIdFactory: PeerSessionIdFactoryProtocol = PeerSessionIdFactory(),
        logger: SDKLoggerProtocol? = nil
    ) {
        self.encryptionManager = encryptionManager
        self.signerManager = signerManager
        self.sessionIdFactory = sessionIdFactory
        self.logger = logger
    }
}

extension IdentityRouteRequestFactory: IdentityRouteRequestMaking {
    public func peerRequestTopic(for request: MessageExchange.SessionRequest) throws -> Data {
        try makeSessionId(for: request, encryptor: makeEncryptor(for: request)).peer.fixedStatementFieldData()
    }

    public func decodePeerRequest<M: MessageExchange.CodableMessage>(
        _ scaleEncodedPayload: Data,
        for request: MessageExchange.SessionRequest
    ) throws -> MessageExchange.Request<M>? {
        let result: StatementDataDecodingResult<M> = try StatementDataCoder(
            encryptor: makeEncryptor(for: request),
            logger: logger
        )
        .decodeFromScaleEncodedPayload(scaleEncodedPayload, senderAccountId: nil, route: .identity)

        guard case let .statementData(.request(peerRequest)) = result else { return nil }

        return peerRequest
    }
}

private extension IdentityRouteRequestFactory {
    func makeEncryptor(for request: MessageExchange.SessionRequest) throws -> MessageExchangeEncrypting {
        try encryptionManager
            .makeEncryptorFactory(ownEncryptionKeyId: request.own.encryptionKeyId)
            .makeEncryptor(remotePublicKey: request.peer.publicKey)
    }

    func makeSessionId(
        for request: MessageExchange.SessionRequest,
        encryptor: MessageExchangeEncrypting
    ) throws -> MessageExchange.SessionId {
        try sessionIdFactory.createSessionId(
            for: .init(
                ownAccountId: signerManager.makeSigner(for: request.own.signKeyId).accountId,
                ownPin: request.own.pin,
                peerAccountId: request.peer.accountId,
                peerPin: request.peer.pin,
                sharedSecret: encryptor.sharedSecret
            )
        )
    }
}
