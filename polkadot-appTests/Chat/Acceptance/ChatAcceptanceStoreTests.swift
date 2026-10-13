import CoreData
import Foundation
import Testing
@testable import polkadot_app

struct ChatAcceptanceStoreTests {
    private let facade = UserDataStorageTestFacade()
    private let peer = Data(repeating: 0x07, count: 32)
    private let requestId = "request"
    private let acceptanceTimestamp: UInt64 = 1_000

    @Test func unpublishedAcceptanceIsPendingWithoutPeriod() async throws {
        try await insertAcceptance()

        let candidates = try await makeStore().pendingAcceptances()

        #expect(candidates.map(\.requestId) == [requestId])
        #expect(candidates.first?.period == nil)
        #expect(candidates.first?.session.peer.accountId == peer)
    }

    @Test func markPublishedRecordsPeriodAndKeepsAcceptancePending() async throws {
        try await insertAcceptance()
        let store = makeStore()
        let candidate = try #require(try await store.pendingAcceptances().first)

        try await store.markPublished(candidate, period: 42)

        let republished = try await store.pendingAcceptances()
        #expect(republished.map(\.period) == [42])
        #expect(republished.first?.message.status == .outgoing(.sent))
    }

    @Test func markAcknowledgedEndsRenewal() async throws {
        try await insertAcceptance()
        let store = makeStore()
        let candidate = try #require(try await store.pendingAcceptances().first)

        try await store.markAcknowledged(candidate)

        #expect(try await store.pendingAcceptances().isEmpty)
    }

    @Test func laterIncomingMessageAcknowledges() async throws {
        try await insertAcceptance()
        try await insertMessage(status: .incoming(.new), timestamp: acceptanceTimestamp + 1)

        #expect(try await isAcknowledged())
    }

    @Test func deliveredOutgoingMessageAcknowledges() async throws {
        try await insertAcceptance()
        try await insertMessage(status: .outgoing(.delivered), timestamp: acceptanceTimestamp + 1)

        #expect(try await isAcknowledged())
    }

    @Test func earlierOrUnconfirmedTrafficDoesNotAcknowledge() async throws {
        try await insertAcceptance()
        try await insertMessage(status: .incoming(.seen), timestamp: acceptanceTimestamp - 1)
        try await insertMessage(status: .outgoing(.sent), timestamp: acceptanceTimestamp + 1)

        #expect(try await !isAcknowledged())
    }
}

private extension ChatAcceptanceStoreTests {
    var chatId: Chat.Id { .person(peer) }

    func makeStore() -> ChatAcceptanceStore {
        ChatAcceptanceStore(storageFacade: facade)
    }

    func isAcknowledged() async throws -> Bool {
        let store = makeStore()
        let candidate = try #require(try await store.pendingAcceptances().first)
        return try await store.isAcknowledged(candidate)
    }

    func insertAcceptance() async throws {
        let acceptance = Chat.LocalMessage(
            messageId: UUID().uuidString,
            chatId: chatId,
            origin: .user,
            creationSource: .localDevice,
            status: .outgoing(.new),
            timestamp: acceptanceTimestamp,
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

        try await facade.databaseService.performWrite { [peer, chatId, requestId] context in
            let contact = CDChatContact(context: context)
            contact.identifier = peer.toHex()
            contact.username = "peer"
            contact.publicKey = Data(repeating: 1, count: 32)
            contact.ownSignKeyId = "//wallet//main"

            let chat = CDChat(context: context)
            chat.identifier = chatId.rawRepresentation
            chat.chatType = Int16(Chat.Id.ChatType.person.rawValue)
            chat.contact = contact

            let request = CDChatRequest(context: context)
            request.identifier = requestId
            request.status = Chat.RequestStatus.incoming(.accepted).rawValue

            try ChatMessageEntityMapper().populate(
                entity: CDChatMessage(context: context),
                from: acceptance,
                using: context
            )
        }
    }

    func insertMessage(status: Chat.LocalMessage.Status, timestamp: UInt64) async throws {
        let message = Chat.LocalMessage(
            messageId: UUID().uuidString,
            chatId: chatId,
            origin: .user,
            creationSource: .localDevice,
            status: status,
            timestamp: timestamp,
            content: .text("hi"),
            reactions: [],
            compactionId: nil,
            relatedMessages: []
        )

        try await facade.databaseService.performWrite { context in
            try ChatMessageEntityMapper().populate(
                entity: CDChatMessage(context: context),
                from: message,
                using: context
            )
        }
    }
}
