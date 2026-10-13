import CoreData
import Foundation
import Testing
@testable import polkadot_app

struct ChatActivityStoreTests {
    private let facade = UserDataStorageTestFacade()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let pendingPeer = Data(repeating: 0x01, count: 32)
    private let recentPeer = Data(repeating: 0x02, count: 32)
    private let idlePeer = Data(repeating: 0x03, count: 32)
    private let blockedPeer = Data(repeating: 0x04, count: 32)

    @Test func activePeersHavePendingOrRecentMessages() async throws {
        let old = now.addingTimeInterval(-10 * 86_400)
        try await insertChat(with: pendingPeer, status: .outgoing(.sent), at: old)
        try await insertChat(with: recentPeer, status: .incoming(.seen), at: now)
        try await insertChat(with: idlePeer, status: .outgoing(.delivered), at: old)

        let activePeers = try await ChatActivityStore(storageFacade: facade)
            .activePeers(since: now.addingTimeInterval(-3 * 86_400))

        #expect(activePeers == [pendingPeer, recentPeer])
    }

    @Test func blockedContactsAreNeverActive() async throws {
        try await insertChat(with: blockedPeer, status: .incoming(.seen), at: now, isBlocked: true)

        let activePeers = try await ChatActivityStore(storageFacade: facade)
            .activePeers(since: now.addingTimeInterval(-3 * 86_400))

        #expect(activePeers.isEmpty)
    }
}

private extension ChatActivityStoreTests {
    func insertChat(
        with peer: Data,
        status: Chat.LocalMessage.Status,
        at date: Date,
        isBlocked: Bool = false
    ) async throws {
        try await facade.databaseService.performWrite { context in
            let contact = CDChatContact(context: context)
            contact.identifier = peer.toHex()
            contact.username = "peer"
            contact.publicKey = Data(repeating: 1, count: 32)
            contact.isBlocked = isBlocked

            let chat = CDChat(context: context)
            chat.identifier = UUID().uuidString
            chat.chatType = Int16(Chat.Id.ChatType.person.rawValue)
            chat.contact = contact

            let message = CDChatMessage(context: context)
            message.messageId = UUID().uuidString
            message.status = status.rawValue
            message.timestamp = Int64(bitPattern: date.toChatTimestamp())
            message.chat = chat
        }
    }
}
