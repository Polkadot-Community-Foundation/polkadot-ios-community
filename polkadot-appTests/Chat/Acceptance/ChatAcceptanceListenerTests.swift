import CryptoKit
import Foundation
import MessageExchangeKit
import NovaCrypto
import StatementStore
import SubstrateSdk
import Testing
@testable import polkadot_app

@Suite(.timeLimit(.minutes(1)))
struct ChatAcceptanceListenerTests {
    private let store = MockStatementStore()
    private let acceptor: ListenerParticipant
    private let requester: ListenerParticipant
    private let device = Chat.PeerDevice(
        statementAccountId: Data(repeating: 0x0A, count: 32),
        encryptionPublicKey: Data(repeating: 0x0B, count: 32)
    )

    init() throws {
        acceptor = try ListenerParticipant()
        requester = try ListenerParticipant()
    }

    @Test func requesterReceivesAcceptanceFromAnySigner() async throws {
        try await publishAcceptance(requestId: "request")

        let listener = ChatAcceptanceListener(
            requestFactory: requester.requestFactory(),
            connection: store,
            logger: MockLogger()
        )

        var iterator = listener.subscribe(to: [requester.request(toward: acceptor)]).makeAsyncIterator()
        let received = try await iterator.next()

        #expect(received == ReceivedChatAcceptance(
            peerAccountId: acceptor.identityAccountId,
            requestId: "request",
            device: device
        ))
    }
}

private extension ChatAcceptanceListenerTests {
    func publishAcceptance(requestId: String) async throws {
        let message = Chat.LocalMessage(
            messageId: UUID().uuidString,
            chatId: .person(requester.identityAccountId),
            origin: .user,
            creationSource: .localDevice,
            status: .outgoing(.new),
            timestamp: Date().toChatTimestamp(),
            content: .multiChatAccepted(.init(requestId: requestId, device: device)),
            reactions: [],
            compactionId: nil,
            relatedMessages: []
        )
        let oneShot = try SNKeyFactory().createKeypair(fromSeed: Data.randomOrError(of: 32))
        let input = OutgoingChatAcceptanceInput(
            message: message,
            requestId: requestId,
            contact: acceptor.contact(of: requester)
        )

        let statement = try acceptor.statementBuilder()
            .makeUnsignedStatement(for: input)
            .signed(by: StatementStoreKeypairSigner(keypair: oneShot))

        try await store.submitStatement(with: statement)
    }
}

private struct ListenerParticipant {
    let identityKeypair: SNKeypairProtocol
    let encryptionKey = Curve25519.KeyAgreement.PrivateKey()

    init() throws {
        identityKeypair = try SNKeyFactory().createKeypair(fromSeed: Data.randomOrError(of: 32))
    }

    var identityAccountId: AccountId { identityKeypair.publicKey().rawData() }

    func requestFactory() -> IdentityRouteRequestFactory {
        IdentityRouteRequestFactory(
            encryptionManager: ClosureEncryptionManager { [encryptionKey] _ in
                X25519ChaChaPolyEncryptorFactory(privateKey: encryptionKey)
            },
            signerManager: ClosureSignerManager { [identityKeypair] _ in
                StatementStoreKeypairSigner(keypair: identityKeypair)
            }
        )
    }

    func statementBuilder() -> ChatAcceptanceStatementBuilder {
        ChatAcceptanceStatementBuilder(
            encryptionManager: ClosureEncryptionManager { [encryptionKey] _ in
                X25519ChaChaPolyEncryptorFactory(privateKey: encryptionKey)
            },
            signerManager: ClosureSignerManager { [identityKeypair] _ in
                StatementStoreKeypairSigner(keypair: identityKeypair)
            }
        )
    }

    func contact(of peer: ListenerParticipant) -> Chat.Contact {
        Chat.Contact(
            accountId: peer.identityAccountId,
            username: "peer",
            publicKey: peer.encryptionKey.publicKey.rawRepresentation,
            pin: nil,
            pushId: nil,
            pushToken: nil,
            voipPushToken: nil,
            peerPlatform: nil,
            lastOwnToken: nil,
            voipLastOwnToken: nil,
            chatRequest: nil,
            ownKeyId: .init(signKeyId: "identity", encryptionKeyId: ""),
            imageData: nil,
            isBlocked: false,
            devices: [],
            pendingDevicesFanOut: false
        )
    }

    func request(toward peer: ListenerParticipant) -> MessageExchange.SessionRequest {
        MessageExchange.SessionRequest(
            own: .init(signKeyId: "identity", encryptionKeyId: "", pin: nil),
            peer: .init(
                accountId: peer.identityAccountId,
                publicKey: peer.encryptionKey.publicKey.rawRepresentation,
                pin: nil,
                devices: []
            )
        )
    }
}
