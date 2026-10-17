import CoreData
import Foundation
import MessageExchangeKit
import Operation_iOS

struct ChatAcceptanceCandidate {
    let message: Chat.LocalMessage
    let requestId: String
    let contact: Chat.Contact
    let session: MessageExchange.SessionRequest
    /// Period of the last publication; nil until published.
    let period: UInt32?
}

protocol ChatAcceptanceStoring {
    func acceptance(messageId: String) async throws -> ChatAcceptanceCandidate?

    /// True while the acceptance has never been published.
    func isAwaitingPublication(messageId: String) async throws -> Bool

    /// Published acceptances the requester has not acknowledged yet.
    func sentAcceptances() async throws -> [ChatAcceptanceCandidate]

    func markPublished(_ candidate: ChatAcceptanceCandidate, period: UInt32) async throws

    func markAcknowledged(_ candidate: ChatAcceptanceCandidate) async throws

    func markFailed(_ candidate: ChatAcceptanceCandidate) async throws

    /// The requester spoke on the device route after the acceptance, or answered one of our device-route messages.
    func isAcknowledged(_ candidate: ChatAcceptanceCandidate) async throws -> Bool
}

final class ChatAcceptanceStore {
    private let databaseService: CoreDataServiceProtocol

    init(storageFacade: StorageFacadeProtocol) {
        databaseService = storageFacade.databaseService
    }
}

extension ChatAcceptanceStore: ChatAcceptanceStoring {
    func acceptance(messageId: String) async throws -> ChatAcceptanceCandidate? {
        try await databaseService.performRead { context in
            let fetchRequest = CDChatMessage.fetchRequest()
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                .messages(withIds: [messageId]),
                .localDeviceChatAcceptances()
            ])
            fetchRequest.fetchLimit = 1

            return try context.fetch(fetchRequest).first.flatMap { try Self.candidate(from: $0, in: context) }
        }
    }

    func isAwaitingPublication(messageId: String) async throws -> Bool {
        try await databaseService.performRead { context in
            let fetchRequest = CDChatMessage.fetchRequest()
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                .messages(withIds: [messageId]),
                .newLocalDeviceChatAcceptances()
            ])
            fetchRequest.fetchLimit = 1

            return try context.count(for: fetchRequest) > 0
        }
    }

    func sentAcceptances() async throws -> [ChatAcceptanceCandidate] {
        try await databaseService.performRead { context in
            let fetchRequest = CDChatMessage.fetchRequest()
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                .localDeviceChatAcceptances(),
                .byStatus(.outgoing(.sent))
            ])

            return try context.fetch(fetchRequest).compactMap { try Self.candidate(from: $0, in: context) }
        }
    }

    func markPublished(_ candidate: ChatAcceptanceCandidate, period: UInt32) async throws {
        try await databaseService.performWrite { context in
            try context.setOutgoingStatementPeriod(period, for: candidate.message.messageId)
            try Self.updateStatus(of: candidate, to: .outgoing(.sent), in: context)
        }
    }

    func markAcknowledged(_ candidate: ChatAcceptanceCandidate) async throws {
        try await databaseService.performWrite { context in
            try Self.updateStatus(of: candidate, to: .outgoing(.delivered), in: context)
        }
    }

    func markFailed(_ candidate: ChatAcceptanceCandidate) async throws {
        try await databaseService.performWrite { context in
            try Self.updateStatus(of: candidate, to: .outgoing(.failed), in: context)
        }
    }

    func isAcknowledged(_ candidate: ChatAcceptanceCandidate) async throws -> Bool {
        try await databaseService.performRead { context in
            let fetchRequest = CDChatMessage.fetchRequest()
            fetchRequest.predicate = Self.acknowledgementPredicate(for: candidate)
            fetchRequest.fetchLimit = 1

            return try context.count(for: fetchRequest) > 0
        }
    }
}

private extension ChatAcceptanceStore {
    static func acknowledgementPredicate(for candidate: ChatAcceptanceCandidate) -> NSPredicate {
        let incoming = [Chat.LocalMessage.Status.incoming(.new), .incoming(.seen)].map(\.rawValue)
        let delivered = Chat.LocalMessage.Status.outgoing(.delivered).rawValue

        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            .localMessages(from: candidate.message.chatId),
            NSPredicate(
                format: "%K > %lld",
                #keyPath(CDChatMessage.timestamp),
                Int64(bitPattern: candidate.message.timestamp)
            ),
            NSPredicate(
                format: "%K IN %@ OR (%K == %d AND %K != %@)",
                #keyPath(CDChatMessage.status),
                incoming,
                #keyPath(CDChatMessage.status),
                delivered,
                #keyPath(CDChatMessage.messageId),
                candidate.message.messageId
            )
        ])
    }

    static func candidate(from entity: CDChatMessage, in context: NSManagedObjectContext) throws
        -> ChatAcceptanceCandidate? {
        let message = try ChatMessageEntityMapper().transform(entity: entity)

        guard
            case let .multiChatAccepted(acceptance) = message.content,
            let contactEntity = entity.chat?.contact
        else {
            return nil
        }

        let contact = try ChatContactMapper().transform(entity: contactEntity)
        let period = try context.outgoingStatementPeriod(for: message.messageId)

        return ChatAcceptanceCandidate(
            message: message,
            requestId: acceptance.requestId,
            contact: contact,
            session: contact.toMessageExchangeSessionRequest(),
            period: period
        )
    }

    static func updateStatus(
        of candidate: ChatAcceptanceCandidate,
        to status: Chat.LocalMessage.Status,
        in context: NSManagedObjectContext
    ) throws {
        let fetchRequest = CDChatMessage.fetchRequest()
        fetchRequest.predicate = .messages(withIds: [candidate.message.messageId])
        fetchRequest.fetchLimit = 1

        guard let entity = try context.fetch(fetchRequest).first else { return }

        entity.status = status.rawValue
        entity.touchParent()
    }
}
