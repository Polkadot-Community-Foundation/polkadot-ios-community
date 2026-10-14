import CoreData
import Foundation
import MessageExchangeKit
import Operation_iOS
import SubstrateSdk

protocol LeaveChatServicing {
    func leaveChat(_ chat: Chat.LocalModel) async throws
}

enum LeaveChatServiceError: Error {
    case personChatExpected
}

final class LeaveChatService {
    private let outboxService: ChatOutboxServicing
    private let chatRepository: AnyDataProviderRepository<Chat.LocalModel>
    private let contactRepository: AnyDataProviderRepository<Chat.Contact>
    private let removedChatRepository: AnyDataProviderRepository<Chat.RemovedChat>
    private let allowanceCleanupService: AllowanceCleanupServicing

    init(
        outboxService: ChatOutboxServicing,
        allowanceCleanupService: AllowanceCleanupServicing,
        storageFacade: StorageFacadeProtocol = UserDataStorageFacade.shared
    ) {
        self.outboxService = outboxService
        self.allowanceCleanupService = allowanceCleanupService

        chatRepository = AnyDataProviderRepository(
            storageFacade.createRepository(
                filter: nil,
                sortDescriptors: [],
                mapper: AnyCoreDataMapper(ChatModelMapper())
            )
        )

        contactRepository = AnyDataProviderRepository(
            storageFacade.createRepository(
                filter: nil,
                sortDescriptors: [],
                mapper: AnyCoreDataMapper(ChatContactMapper())
            )
        )

        removedChatRepository = AnyDataProviderRepository(
            storageFacade.createRepository(
                filter: nil,
                sortDescriptors: [],
                mapper: AnyCoreDataMapper(RemovedChatMapper())
            )
        )
    }
}

extension LeaveChatService: LeaveChatServicing {
    func leaveChat(_ chat: Chat.LocalModel) async throws {
        guard case let .person(contact) = chat.peer else {
            throw LeaveChatServiceError.personChatExpected
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            outboxService.sendPeerLeftMessage(to: contact) {
                continuation.resume()
            }
        }

        try await chatRepository.saveOperation({ [] }, { [chat.chatId.rawRepresentation] }).asyncExecute()
        try await contactRepository.saveOperation({ [] }, { [contact.identifier] }).asyncExecute()

        try await saveRemovedChatTombstoneIfNeeded(for: contact)

        await allowanceCleanupService.cleanup()
    }
}

private extension LeaveChatService {
    func saveRemovedChatTombstoneIfNeeded(for contact: Chat.Contact) async throws {
        let tombstone = Chat.RemovedChat(
            accountId: contact.accountId,
            removedAt: Date()
        )
        try await removedChatRepository.saveOperation({ [tombstone] }, { [] }).asyncExecute()
    }
}
