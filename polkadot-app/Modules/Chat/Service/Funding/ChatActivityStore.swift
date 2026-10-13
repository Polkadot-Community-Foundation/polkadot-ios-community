import CoreData
import Foundation
import Operation_iOS
import SubstrateSdk

protocol ChatActivityProviding {
    /// Unblocked contacts with an unanswered outgoing message or any message since `cutoff`.
    func activePeers(since cutoff: Date) async throws -> Set<AccountId>
}

final class ChatActivityStore {
    private let databaseService: CoreDataServiceProtocol

    init(storageFacade: StorageFacadeProtocol) {
        databaseService = storageFacade.databaseService
    }
}

extension ChatActivityStore: ChatActivityProviding {
    func activePeers(since cutoff: Date) async throws -> Set<AccountId> {
        try await databaseService.performRead { context in
            let blocked = try Self.blockedContactIdentifiers(in: context)
            let pending = try Self.messagePeers(matching: .byStatus(.outgoing(.sent)), in: context)
            let recent = try Self.messagePeers(matching: Self.messages(since: cutoff), in: context)

            return Self.accountIds(from: pending.union(recent).subtracting(blocked))
        }
    }
}

private extension ChatActivityStore {
    static let peerKeyPath = #keyPath(CDChatMessage.chat.contact.identifier)

    static func blockedContactIdentifiers(in context: NSManagedObjectContext) throws -> Set<String> {
        let request = CDChatContact.fetchRequest()
        request.predicate = NSPredicate(format: "%K == YES", #keyPath(CDChatContact.isBlocked))
        return try Set(context.fetch(request).compactMap(\.identifier))
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
