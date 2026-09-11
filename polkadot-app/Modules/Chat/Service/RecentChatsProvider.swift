import Foundation
import SubstrateSdk
import AsyncExtensions
import SDKLogger

final class RecentChatsProvider {
    private let chatProvider: ChatContactDataProviderMaking
    private let logger: LoggerProtocol

    init(
        chatProvider: ChatContactDataProviderMaking,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.chatProvider = chatProvider
        self.logger = logger
    }

    func subscribe() -> AnyAsyncSequence<[SearchRow<Chat.RemoteContact>]> {
        chatProvider.subscribeChatsWithPredicate(NSPredicate.chatWithNonBlockedContact())
            .map { chats in
                chats.compactMap { chat -> SearchRow<Chat.RemoteContact>? in
                    guard case let .person(contact) = chat.peer else {
                        return nil
                    }

                    guard !contact.hasIncomingChatRequest else {
                        return nil
                    }

                    do {
                        let remoteContact = try Chat.RemoteContact(contact: contact)
                        return SearchRow(
                            accountId: contact.accountId,
                            username: Username(value: contact.username),
                            matchTerms: [contact.username],
                            payload: remoteContact
                        )
                    } catch {
                        self.logger.error(
                            "Failed to convert contact to remote contact: \(error)"
                        )
                        return nil
                    }
                }
            }
            .eraseToAnyAsyncSequence()
    }
}
