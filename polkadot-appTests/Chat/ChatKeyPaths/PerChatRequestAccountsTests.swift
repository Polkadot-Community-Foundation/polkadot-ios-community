import CryptoKit
import Foundation
import MessageExchangeKit
import StatementStore
import SubstrateSdk
import Testing
@testable import polkadot_app

struct PerChatRequestAccountsTests {
    private let entropyManager = FixedRootEntropyManager()
    private let peerAccountId = Data(repeating: 0xAB, count: 32)
    private let peerAccounts = ChatPeerAccounts(tldProvider: StubDotNsTldProvider(tld: "dot"))

    private var signerResolver: ChatStatementSignerResolver {
        ChatStatementSignerResolver(
            peerAccounts: peerAccounts,
            signManager: ChatSignerManager(entropyManager: entropyManager)
        )
    }

    @Test func innerRequestProofIsSignedByPerChatAccount() throws {
        let acceptorKey = Curve25519.KeyAgreement.PrivateKey()
        let factory = ChatRequestFactory(
            encryptionManager: ChatEncryptionManager(entropyManager: entropyManager),
            signManager: ChatSignerManager(entropyManager: entropyManager),
            remoteContactResolver: MockRemoteContactResolver(result: .success(nil)),
            statementSignerResolver: signerResolver
        )

        let encrypted = try factory.createRemoteRequest(
            from: Chat.RequestMessage(
                messageId: UUID().uuidString,
                timestamp: Date().toChatTimestamp(),
                content: .v1(Chat.RequestContentV1(pushToken: nil, welcomeMessage: nil))
            ),
            peerEncryptionPubKey: acceptorKey.publicKey.rawRepresentation,
            peerAccountId: peerAccountId
        )

        let decrypted = try X25519ChaChaPolyEncryptorFactory(privateKey: acceptorKey)
            .makeEncryptor(remotePublicKey: encrypted.encryptionPubKey)
            .decrypt(encrypted.encryptedData)
        let remote = try ChatRequest.RemoteModel(scaleDecoder: ScaleDecoder(data: decrypted))

        guard case let .sr25519(_, signer) = remote.proof else {
            Issue.record("Unexpected proof type")
            return
        }

        #expect(try signer == statementAccountId())
    }

    @Test func acceptorRejectsRequestWithoutDevice() async throws {
        let acceptorKey = Curve25519.KeyAgreement.PrivateKey()
        let ownKeyId = Chat.Contact.Own(
            signKeyId: WalletDerivationPath.main(for: "dot"),
            encryptionKeyId: ChatEncryptionDomain.mainChat.rawValue
        )
        let acceptorAccountId = try ChatSignerManager(entropyManager: entropyManager)
            .makeSigner(for: ownKeyId.signKeyId)
            .accountId

        let encrypted = try makeRequestFactory().createRemoteRequest(
            from: Chat.RequestMessage(
                messageId: UUID().uuidString,
                timestamp: Date().toChatTimestamp(),
                content: .v1(Chat.RequestContentV1(pushToken: nil, welcomeMessage: nil))
            ),
            peerEncryptionPubKey: acceptorKey.publicKey.rawRepresentation,
            peerAccountId: acceptorAccountId
        )

        let acceptorFactory = ChatRequestFactory(
            encryptionManager: ClosureEncryptionManager { _ in
                X25519ChaChaPolyEncryptorFactory(privateKey: acceptorKey)
            },
            signManager: ChatSignerManager(entropyManager: entropyManager),
            remoteContactResolver: MockRemoteContactResolver(result: .success(nil)),
            statementSignerResolver: signerResolver
        )

        await #expect(throws: ChatRequestFactoryError.unsupportedRequestVersion) {
            try await acceptorFactory.decodeAndValidate(remotePayload: encrypted.scaleEncoded(), ownKeyId: ownKeyId)
        }
    }

    @Test func acceptorAdvertisesPerChatAccountAsDevice() throws {
        let deviceKeyManager = StubDeviceEncryptionKeyManager()
        let service = ChatRequestStoreService(
            storageFacade: UserDataStorageTestFacade(),
            pushIdFactory: ChatPushIdFactory(
                encryptionManager: ChatEncryptionManager(entropyManager: entropyManager),
                signManager: ChatSignerManager(entropyManager: entropyManager),
                sessionIdFactory: PeerSessionIdFactory(),
                logger: MockLogger()
            ),
            deviceEncryptionKeyManager: deviceKeyManager,
            encryptionManager: ChatEncryptionManager(entropyManager: entropyManager),
            statementSignerResolver: signerResolver
        )
        let device = try service.buildLocalAcceptorDevice(peerAccountId: peerAccountId)

        #expect(try device.statementAccountId == statementAccountId())
        #expect(try device.encryptionPublicKey == (deviceKeyManager.getPublicKey()))
    }
}

private extension PerChatRequestAccountsTests {
    func makeRequestFactory() -> ChatRequestFactory {
        ChatRequestFactory(
            encryptionManager: ChatEncryptionManager(entropyManager: entropyManager),
            signManager: ChatSignerManager(entropyManager: entropyManager),
            remoteContactResolver: MockRemoteContactResolver(result: .success(nil)),
            statementSignerResolver: signerResolver
        )
    }

    func statementAccountId() throws -> AccountId {
        try ChatSignerManager(entropyManager: entropyManager)
            .makeSigner(for: peerAccounts.statementKeyId(for: peerAccountId))
            .accountId
    }
}
