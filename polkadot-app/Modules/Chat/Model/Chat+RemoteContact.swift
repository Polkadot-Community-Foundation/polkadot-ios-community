import Foundation
import SubstrateSdk

extension Chat {
    struct RemoteContact {
        let accountId: AccountId
        let username: String
        let chatPublicKey: Chat.PublicKey
        let imageData: Data?
        let source: Chat.Contact.Source
    }
}

extension Chat.RemoteContact {
    init(contact: Chat.Contact) throws {
        try self.init(
            accountId: contact.accountId,
            username: contact.username,
            chatPublicKey: Chat.PublicKey(rawData: contact.publicKey),
            imageData: contact.imageData,
            source: contact.source
        )
    }
}
