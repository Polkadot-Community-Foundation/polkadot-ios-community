import CryptoKit
import Foundation
import IssueMonitoring
import MessageExchangeKit
import os
import StatementStore
import SubstrateSdk
@testable import polkadot_app

/// Real derivation and identity-route statements over an in-memory statement store.
struct ChatAcceptanceFixture {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let requestId = "request"
    let identityKeyId = "//wallet//main"
    let peerAccountId = Data(repeating: 9, count: 32)
    let statementStore = MockStatementStore()
    let allocator = StubNotificationAllocator()
    let signManager = ChatSignerManager(entropyManager: FixedRootEntropyManager())
    let statementService: ChatAcceptanceStatementService

    init() {
        let identityEncryptionKey = Curve25519.KeyAgreement.PrivateKey()

        statementService = ChatAcceptanceStatementService(
            requestFactory: IdentityRouteRequestFactory(
                encryptionManager: ClosureEncryptionManager { _ in
                    X25519ChaChaPolyEncryptorFactory(privateKey: identityEncryptionKey)
                },
                signerManager: signManager
            ),
            connection: statementStore
        )
    }

    var signers: ChatAcceptanceSigners {
        ChatAcceptanceSigners(signManager: signManager)
    }

    func acceptAccountId(period: UInt32) throws -> AccountId {
        try signers.signer(requestId: requestId, period: period).signer.accountId
    }

    func identityAccountId() throws -> AccountId {
        try signManager.makeSigner(for: identityKeyId).accountId
    }

    func senders() throws -> [AccountId] {
        try statementStore.senderAccountIds()
    }

    func makeCandidate(period: UInt32?, sentAt: Date? = nil) -> ChatAcceptanceCandidate {
        let message = Chat.LocalMessage(
            messageId: "acceptance",
            chatId: .person(peerAccountId),
            origin: .user,
            creationSource: .localDevice,
            status: .outgoing(period == nil ? .new : .sent),
            timestamp: (sentAt ?? now).toChatTimestamp(),
            content: .multiChatAccepted(.init(
                requestId: requestId,
                device: Chat.PeerDevice(
                    statementAccountId: Data(repeating: 2, count: 32),
                    encryptionPublicKey: Data(repeating: 3, count: 32)
                )
            )),
            reactions: [],
            compactionId: nil,
            relatedMessages: []
        )

        let session = MessageExchange.SessionRequest(
            own: MessageExchange.Own(signKeyId: identityKeyId, encryptionKeyId: "", pin: nil),
            peer: MessageExchange.Peer(
                accountId: peerAccountId,
                publicKey: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation,
                pin: nil,
                devices: []
            )
        )

        return ChatAcceptanceCandidate(message: message, requestId: requestId, session: session, period: period)
    }
}

final class InMemoryChatAcceptanceStore: ChatAcceptanceStoring, @unchecked Sendable {
    private let candidates: [ChatAcceptanceCandidate]
    var isAwaiting = true
    /// Stops awaiting after this many reads; nil keeps `isAwaiting` as is.
    var awaitingReadsLeft: Int?
    var isAcknowledged = false
    private(set) var published: [UInt32] = []
    private(set) var acknowledgedCount = 0

    init(candidates: [ChatAcceptanceCandidate]) {
        self.candidates = candidates
    }

    func acceptance(messageId: String) async throws -> ChatAcceptanceCandidate? {
        candidates.first { $0.message.messageId == messageId }
    }

    func isAwaitingPublication(messageId _: String) async throws -> Bool {
        if let left = awaitingReadsLeft {
            awaitingReadsLeft = left - 1
            return left > 0
        }
        return isAwaiting
    }

    func sentAcceptances() async throws -> [ChatAcceptanceCandidate] {
        candidates
    }

    func markPublished(_: ChatAcceptanceCandidate, period: UInt32) async throws {
        published.append(period)
        isAwaiting = false
    }

    func markAcknowledged(_: ChatAcceptanceCandidate) async throws {
        acknowledgedCount += 1
    }

    func isAcknowledged(_: ChatAcceptanceCandidate) async throws -> Bool {
        isAcknowledged
    }
}

final class RecordingIssueDiagnostic: IssueDiagnostic, @unchecked Sendable {
    private let failures = OSAllocatedUnfairLock(initialState: 0)

    var failureCount: Int { failures.withLock { $0 } }

    func recordFailure(for _: String, error _: Error?, counters _: [String: Int]) {
        failures.withLock { $0 += 1 }
    }

    func recordRecovery(for _: String) {}
}

extension ChatAcceptanceIssueDiagnostics {
    static func recording(unacknowledged: IssueDiagnostic = NoopIssueDiagnostic()) -> Self {
        Self(publishFailing: NoopIssueDiagnostic(), unacknowledged: unacknowledged)
    }
}
