import Foundation
import SubstrateSdk
import MessageExchangeKit

protocol SenderDeviceActivating {
    func activate(requestId: String, peerAccountId: AccountId) async throws
}

/// Stores the requester's device on the contact once our acceptance is published,
/// which moves the session from the identity route to the device route.
final class SenderDeviceActivator {
    private let contactsStorageService: ContactsLocalStorageServicing
    private let chatRequestStoreService: ChatRequestStoreServicing
    private let messageExchangeModeProvider: MessageExchangeModeProviding

    init(
        contactsStorageService: ContactsLocalStorageServicing,
        chatRequestStoreService: ChatRequestStoreServicing,
        messageExchangeModeProvider: MessageExchangeModeProviding
    ) {
        self.contactsStorageService = contactsStorageService
        self.chatRequestStoreService = chatRequestStoreService
        self.messageExchangeModeProvider = messageExchangeModeProvider
    }
}

extension SenderDeviceActivator: SenderDeviceActivating {
    func activate(requestId: String, peerAccountId: AccountId) async throws {
        guard let contact = try await contactsStorageService.getContact(by: peerAccountId).asyncExecute() else {
            throw SenderDeviceActivatorError.noContact
        }

        guard messageExchangeModeProvider.mode(for: contact) == .multidevice else {
            return
        }

        guard let senderDevice = try await chatRequestStoreService.fetchPeerDeviceByRequestId(requestId) else {
            throw SenderDeviceActivatorError.noSenderDevice
        }

        let settings = Chat.ContactDeviceSettings(accountId: peerAccountId, changes: [.added(senderDevice)])
        try await contactsStorageService.updateDeviceSettings([settings]).asyncExecute()
    }
}

enum SenderDeviceActivatorError: Error {
    case noContact
    case noSenderDevice
}
