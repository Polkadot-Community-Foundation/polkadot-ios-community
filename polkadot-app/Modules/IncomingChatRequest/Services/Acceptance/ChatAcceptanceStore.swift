import CoreData
import Foundation
import MessageExchangeKit
import Operation_iOS

struct ChatAcceptanceCandidate {
    let message: Chat.LocalMessage
    let requestId: String
    let session: MessageExchange.SessionRequest
    /// Period of the last publication; nil until published.
    let period: UInt32?
}

protocol ChatAcceptanceStoring {
    /// Acceptances not yet acknowledged by the requester.
    func pendingAcceptances() async throws -> [ChatAcceptanceCandidate]

    func markPublished(_ candidate: ChatAcceptanceCandidate, period: UInt32) async throws

    func markAcknowledged(_ candidate: ChatAcceptanceCandidate) async throws

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
    func pendingAcceptances() async throws -> [ChatAcceptanceCandidate] {
        try await databaseService.performRead { context in
            let fetchRequest = CDChatMessage.fetchRequest()
            fetchRequest.predicate = Self.pendingAcceptancesPredicate()

            return try context.fetch(fetchRequest).compactMap { try Self.candidate(from: $0, in: context) }
        }
    }

    func markPublished(_ candidate: ChatAcceptanceCandidate, period: UInt32) async throws {
        try await databaseService.performWrite { context in
            if let request = try Self.fetchRequest(candidate.requestId, in: context) {
                request.anonymousDeliveryPeriod = NSNumber(value: Int32(bitPattern: period))
            }

            try Self.updateStatus(of: candidate, to: .outgoing(.sent), in: context)
        }
    }

    func markAcknowledged(_ candidate: ChatAcceptanceCandidate) async throws {
        try await databaseService.performWrite { context in
            try Self.updateStatus(of: candidate, to: .outgoing(.delivered), in: context)
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
    static func pendingAcceptancesPredicate() -> NSPredicate {
        let statuses = [Chat.LocalMessage.Status.outgoing(.new), .outgoing(.sent)].map(\.rawValue)

        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            .messageByContentType(.multiChatAccepted),
            .messageByChatType(.person),
            .byCreationSource(.localDevice),
            NSPredicate(format: "%K IN %@", #keyPath(CDChatMessage.status), statuses)
        ])
    }

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
        let period = try fetchRequest(acceptance.requestId, in: context)?.anonymousDeliveryPeriod

        return ChatAcceptanceCandidate(
            message: message,
            requestId: acceptance.requestId,
            session: contact.toMessageExchangeSessionRequest(),
            period: period.map { UInt32(bitPattern: $0.int32Value) }
        )
    }

    static func fetchRequest(_ requestId: String, in context: NSManagedObjectContext) throws -> CDChatRequest? {
        let fetchRequest = CDChatRequest.fetchRequest()
        fetchRequest.predicate = .chatRequestById(requestId)
        fetchRequest.fetchLimit = 1
        return try context.fetch(fetchRequest).first
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
