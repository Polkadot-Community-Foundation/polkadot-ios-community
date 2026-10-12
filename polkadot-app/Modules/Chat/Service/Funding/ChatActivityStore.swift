import CoreData
import Foundation
import Operation_iOS
import SubstrateSdk

struct ChatActivity: Equatable {
    let peers: Set<AccountId>
    let activePeers: Set<AccountId>
}

protocol ChatActivityProviding {
    /// Active peers have an unanswered outgoing message or any message since `cutoff`.
    func activity(since cutoff: Date) async throws -> ChatActivity
}

final class ChatActivityStore {
    private let databaseService: CoreDataServiceProtocol

    init(storageFacade: StorageFacadeProtocol) {
        databaseService = storageFacade.databaseService
    }
}

extension ChatActivityStore: ChatActivityProviding {
    func activity(since cutoff: Date) async throws -> ChatActivity {
        try await databaseService.performRead { context in
            let peers = try Self.contactIdentifiers(in: context)
            let pending = try Self.messagePeers(matching: .byStatus(.outgoing(.sent)), in: context)
            let recent = try Self.messagePeers(matching: Self.messages(since: cutoff), in: context)

            return ChatActivity(
                peers: Self.accountIds(from: peers),
                activePeers: Self.accountIds(from: pending.union(recent))
            )
        }
    }
}

private extension ChatActivityStore {
    static let peerKeyPath = #keyPath(CDChatMessage.chat.contact.identifier)

    static func contactIdentifiers(in context: NSManagedObjectContext) throws -> Set<String> {
        try Set(context.fetch(CDChatContact.fetchRequest()).compactMap(\.identifier))
    }

    static func messagePeers(
        matching predicate: NSPredicate,
        in context: NSManagedObjectContext
    ) throws -> Set<String> {
        let request = NSFetchRequest<NSDictionary>(entityName: String(describing: CDChatMessage.self))
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = [peerKeyPath]
        request.returnsDistinctResults = true
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            predicate,
            .messageByChatType(.person)
        ])

        return try Set(context.fetch(request).compactMap { $0[peerKeyPath] as? String })
    }

    static func messages(since cutoff: Date) -> NSPredicate {
        NSPredicate(
            format: "%K >= %lld",
            #keyPath(CDChatMessage.timestamp),
            Int64(bitPattern: cutoff.toChatTimestamp())
        )
    }

    static func accountIds(from identifiers: Set<String>) -> Set<AccountId> {
        Set(identifiers.compactMap { try? $0.fromHex() })
    }
}
