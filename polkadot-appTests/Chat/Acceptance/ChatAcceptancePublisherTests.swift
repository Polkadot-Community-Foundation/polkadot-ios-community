import CryptoKit
import Foundation
import IssueMonitoring
import MessageExchangeKit
import os
import StatementStore
import SubstrateSdk
import Testing
@testable import polkadot_app

struct ChatAcceptancePublisherTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let requestId = "request"
    private let identityKeyId = "//wallet//main"
    private let peerAccountId = Data(repeating: 9, count: 32)
    private let statementStore = MockStatementStore()
    private let allocator = StubNotificationAllocator()
    private let activator = RecordingSenderDeviceActivator()
    private let unacknowledged = RecordingIssueDiagnostic()
    private let signManager = ChatSignerManager(entropyManager: FixedRootEntropyManager())

    @Test func firstPublishActivatesRequesterDeviceAndRecordsPeriod() async throws {
        let store = InMemoryChatAcceptanceStore(candidates: [makeCandidate(period: nil)])

        await makePublisher(store: store).sync()

        #expect(try statementStore.senderAccountIds() == [acceptAccountId(period: allocator.period)])
        #expect(try allocator.initiatedTargets == [acceptAccountId(period: allocator.period)])
        #expect(activator.activations == [requestId])
        #expect(store.published == [allocator.period])
    }

    @Test func stalePeriodRepublishesFromFreshAccountWithoutReactivating() async throws {
        let store = InMemoryChatAcceptanceStore(candidates: [makeCandidate(period: allocator.period - 1)])

        await makePublisher(store: store).sync()

        #expect(try statementStore.senderAccountIds() == [acceptAccountId(period: allocator.period)])
        #expect(activator.activations.isEmpty)
        #expect(store.published == [allocator.period])
    }

    @Test func currentPeriodIsNotRepublished() async throws {
        let store = InMemoryChatAcceptanceStore(candidates: [makeCandidate(period: allocator.period)])

        await makePublisher(store: store).sync()

        #expect(try statementStore.senderAccountIds().isEmpty)
        #expect(store.published.isEmpty)
    }

    @Test func acknowledgedAcceptanceIsMarkedWithoutPublishing() async throws {
        let store = InMemoryChatAcceptanceStore(candidates: [makeCandidate(period: allocator.period - 1)])
        store.isAcknowledged = true

        await makePublisher(store: store).sync()

        #expect(try statementStore.senderAccountIds().isEmpty)
        #expect(store.acknowledgedCount == 1)
    }

    @Test func stopsRenewingAfterSevenDaysAndReportsIt() async throws {
        let sentAt = now.addingTimeInterval(-7 * 86_400 - 1)
        let store = InMemoryChatAcceptanceStore(candidates: [makeCandidate(period: 1, sentAt: sentAt)])

        await makePublisher(store: store).sync()

        #expect(try statementStore.senderAccountIds().isEmpty)
        #expect(unacknowledged.failureCount == 1)
    }

    @Test func noFreeSlotPublishesNothing() async throws {
        allocator.hasFreeSlot = false
        let store = InMemoryChatAcceptanceStore(candidates: [makeCandidate(period: nil)])

        await makePublisher(store: store).sync()

        #expect(try statementStore.senderAccountIds().isEmpty)
        #expect(activator.activations.isEmpty)
        #expect(store.published.isEmpty)
    }

    @Test func identityAccountNeverSignsAcceptance() async throws {
        let store = InMemoryChatAcceptanceStore(candidates: [makeCandidate(period: nil)])

        await makePublisher(store: store).sync()

        let identityAccountId = try signManager.makeSigner(for: identityKeyId).accountId
        #expect(try !statementStore.senderAccountIds().contains(identityAccountId))
    }
}

private extension ChatAcceptancePublisherTests {
    func acceptAccountId(period: UInt32) throws -> AccountId {
        try signManager.makeSigner(for: ChatKeyPaths.accept(requestId: requestId, period: period)).accountId
    }

    func makePublisher(store: ChatAcceptanceStoring) -> ChatAcceptancePublisher {
        let identityEncryptionKey = Curve25519.KeyAgreement.PrivateKey()

        return ChatAcceptancePublisher(
            dependencies: ChatAcceptancePublisherDependencies(
                store: store,
                allocator: allocator,
                signManager: signManager,
                requestFactory: IdentityRouteRequestFactory(
                    encryptionManager: ClosureEncryptionManager { _ in
                        X25519ChaChaPolyEncryptorFactory(privateKey: identityEncryptionKey)
                    },
                    signerManager: signManager
                ),
                submitter: statementStore,
                deviceActivator: activator
            ),
            dateProvider: MockDateProvider(now: now),
            issueDiagnostics: ChatAcceptanceIssueDiagnostics(
                publishFailing: NoopIssueDiagnostic(),
                unacknowledged: unacknowledged
            ),
            logger: MockLogger()
        )
    }

    func makeCandidate(period: UInt32?, sentAt: Date? = nil) -> ChatAcceptanceCandidate {
        let message = Chat.LocalMessage(
            messageId: UUID().uuidString,
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

private final class InMemoryChatAcceptanceStore: ChatAcceptanceStoring, @unchecked Sendable {
    private let candidates: [ChatAcceptanceCandidate]
    var isAcknowledged = false
    private(set) var published: [UInt32] = []
    private(set) var acknowledgedCount = 0

    init(candidates: [ChatAcceptanceCandidate]) {
        self.candidates = candidates
    }

    func pendingAcceptances() async throws -> [ChatAcceptanceCandidate] {
        candidates
    }

    func markPublished(_: ChatAcceptanceCandidate, period: UInt32) async throws {
        published.append(period)
    }

    func markAcknowledged(_: ChatAcceptanceCandidate) async throws {
        acknowledgedCount += 1
    }

    func isAcknowledged(_: ChatAcceptanceCandidate) async throws -> Bool {
        isAcknowledged
    }
}

private final class RecordingSenderDeviceActivator: SenderDeviceActivating, @unchecked Sendable {
    private(set) var activations: [String] = []

    func activate(requestId: String, peerAccountId _: AccountId) async throws {
        activations.append(requestId)
    }
}

private final class RecordingIssueDiagnostic: IssueDiagnostic, @unchecked Sendable {
    private let failures = OSAllocatedUnfairLock(initialState: 0)

    var failureCount: Int { failures.withLock { $0 } }

    func recordFailure(for _: String, error _: Error?, counters _: [String: Int]) {
        failures.withLock { $0 += 1 }
    }

    func recordRecovery(for _: String) {}
}
