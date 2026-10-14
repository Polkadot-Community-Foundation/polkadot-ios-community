import CoreData
import Foundation
import os
import Testing
@testable import polkadot_app

@Suite(.timeLimit(.minutes(1)))
struct ChatAcceptancePublisherTests {
    private let facade = UserDataStorageTestFacade()
    private let peer = Data(repeating: 0x07, count: 32)
    private let delivery = HoldingAcceptanceDelivery()

    @Test func startsOneDeliveryPerNewAcceptance() async throws {
        try await insertChat()
        let publisher = makePublisher()
        publisher.setup()
        defer { publisher.throttle() }

        try await insertAcceptance(id: "first")
        await waitUntil { delivery.started == ["first"] }

        try await insertAcceptance(id: "second")
        await waitUntil { delivery.started.count == 2 }

        #expect(delivery.started == ["first", "second"])
    }
}

private extension ChatAcceptancePublisherTests {
    func makePublisher() -> ChatAcceptancePublisher {
        ChatAcceptancePublisher(
            messageProviderFactory: ChatMessageDataProviderFactory(
                repositoryFactory: ChatMessageRepositoryFactory(storageFacade: facade),
                logger: MockLogger()
            ),
            deliveryService: delivery,
            logger: MockLogger()
        )
    }

    func waitUntil(_ condition: () -> Bool) async {
        while !condition() {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func insertChat() async throws {
        try await facade.databaseService.performWrite { [peer] context in
            let contact = CDChatContact(context: context)
            contact.identifier = peer.toHex()
            contact.username = "peer"
            contact.publicKey = Data(repeating: 1, count: 32)
            contact.ownSignKeyId = "//wallet//main"

            let chat = CDChat(context: context)
            chat.identifier = Chat.Id.person(peer).rawRepresentation
            chat.chatType = Int16(Chat.Id.ChatType.person.rawValue)
            chat.contact = contact
        }
    }

    func insertAcceptance(id: String) async throws {
        let acceptance = Chat.LocalMessage(
            messageId: id,
            chatId: .person(peer),
            origin: .user,
            creationSource: .localDevice,
            status: .outgoing(.new),
            timestamp: Date().toChatTimestamp(),
            content: .multiChatAccepted(.init(
                requestId: "request-\(id)",
                device: Chat.PeerDevice(
                    statementAccountId: Data(repeating: 2, count: 32),
                    encryptionPublicKey: Data(repeating: 3, count: 32)
                )
            )),
            reactions: [],
            compactionId: nil,
            relatedMessages: []
        )

        try await facade.databaseService.performWrite { context in
            try ChatMessageEntityMapper().populate(
                entity: CDChatMessage(context: context),
                from: acceptance,
                using: context
            )
        }
    }
}

/// Never finishes a delivery, so a later snapshot that still lists the acceptance must not restart it.
private final class HoldingAcceptanceDelivery: ChatAcceptanceDelivering, @unchecked Sendable {
    private let calls = OSAllocatedUnfairLock<[String]>(initialState: [])

    var started: [String] { calls.withLock { $0 } }

    func deliverUntilDone(messageId: String) async {
        calls.withLock { $0.append(messageId) }

        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
