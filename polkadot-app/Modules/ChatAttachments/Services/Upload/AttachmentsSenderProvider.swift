import Foundation
import KeyDerivation

protocol AttachmentsSenderProviding {
    func getWallet(for chatId: Chat.Id) async throws -> WalletManaging
}

enum AttachmentsSenderProviderError: Error, Equatable {
    case unsupportedChat
}

final class AttachmentsSenderProvider {
    let peerAccounts: ChatPeerAccountsProviding
    let entropyManager: RootEntropyManaging

    init(
        peerAccounts: ChatPeerAccountsProviding = ChatPeerAccounts(),
        entropyManager: RootEntropyManaging = RootEntropyManager.shared
    ) {
        self.peerAccounts = peerAccounts
        self.entropyManager = entropyManager
    }
}

extension AttachmentsSenderProvider: AttachmentsSenderProviding {
    func getWallet(for chatId: Chat.Id) async throws -> WalletManaging {
        guard let peerAccountId = chatId.accountId else {
            throw AttachmentsSenderProviderError.unsupportedChat
        }

        return try DynamicDerivedWallet(
            derivationPath: peerAccounts.uploadKeyId(for: peerAccountId),
            entropyManager: entropyManager
        )
    }
}
