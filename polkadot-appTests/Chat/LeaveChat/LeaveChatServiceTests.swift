import CoreData
import Foundation
import MessageExchangeKit
import SubstrateSdk
import Testing
@testable import polkadot_app

struct LeaveChatServiceTests {
    private let facade = UserDataStorageTestFacade()
    private let cleanupService = SpyAllowanceCleanupService()
    private let peerAccountId = Data(repeating: 0x01, count: 32)

    @Test func cleansUpAllowancesAfterContactIsDeleted() async throws {
        try await insertContact()
        var contactsAtCleanup: Int?
        cleanupService.onCleanup = { [self] in contactsAtCleanup = try? await contactCount() }

        try await makeService().leaveChat(.init(
            peer: .person(makeContact()),
            message: nil,
            unreadDisplayMessageCount: 0,
            hasIncomingReaction: false,
            createdAt: nil,
            roomMetadata: nil
        ))

        #expect(cleanupService.cleanupCount == 1)
        #expect(contactsAtCleanup == 0)
    }
}

private extension LeaveChatServiceTests {
    func makeService() -> LeaveChatService {
        LeaveChatService(
            outboxService: StubLeaveOutbox(),
            allowanceCleanupService: cleanupService,
            storageFacade: facade
        )
    }

    func makeContact() -> Chat.Contact {
        Chat.Contact(
            accountId: peerAccountId,
            username: "peer",
            publicKey: Data(repeating: 0x02, count: 32),
            pin: nil,
            pushId: nil,
            pushToken: nil,
            voipPushToken: nil,
            peerPlatform: nil,
            lastOwnToken: nil,
            voipLastOwnToken: nil,
            chatRequest: nil,
            ownKeyId: .init(signKeyId: "//wallet//main", encryptionKeyId: "main"),
            imageData: nil,
            isBlocked: false,
            devices: [],
            pendingDevicesFanOut: false
        )
    }

    func insertContact() async throws {
        try await facade.databaseService.performWrite { [peerAccountId] context in
            let contact = CDChatContact(context: context)
            contact.identifier = peerAccountId.toHex()
            contact.username = "peer"
            contact.publicKey = Data(repeating: 0x02, count: 32)
            contact.ownSignKeyId = "//wallet//main"
        }
    }

    func contactCount() async throws -> Int {
        try await facade.databaseService.performRead { context in
            try context.count(for: CDChatContact.fetchRequest())
        }
    }
}

private final class StubLeaveOutbox: ChatOutboxServicing {
    var exchangeService: AnyMessageExchangeService<Chat.OpaqueMessage>?

    func setupCallCoordinator(_: CallCoordinating) {}
    func setContactsByAccountId(_: [AccountId: Chat.Contact]) {}
    func syncPendingRemoteMessages(_: [Chat.RemoteMessage], for _: MessageExchange.Peer) {}
    func schedulePendingMessages() {}

    func handleSentMessages(
        _: [Chat.RemoteMessage],
        to _: Chat.Contact,
        withError _: MessageExchange.OutgoingMessageError?
    ) {}

    func handleDeliveredMessages(
        _: [Chat.RemoteMessage],
        to _: Chat.Contact,
        withError _: MessageExchange.OutgoingMessageError?
    ) {}

    func handleCompactedMessages(
        compactedMessage _: Chat.RemoteMessage,
        originalMessages _: [Chat.RemoteMessage],
        for _: MessageExchange.Peer
    ) {}

    func sendPeerLeftMessage(to _: Chat.Contact, completion: @escaping () -> Void) {
        completion()
    }

    func sendDirectly(_: Chat.RemoteMessage, to _: AccountId) {}
}
