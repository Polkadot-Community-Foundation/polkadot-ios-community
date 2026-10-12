import Foundation
import KeyDerivation
import Products

protocol AttachmentsSenderProviding {
    func getWallet(for chatId: Chat.Id) async throws -> WalletManaging
}

enum AttachmentsSenderProviderError: Error, Equatable {
    case unsupportedChat
}

final class AttachmentsSenderProvider {
    let tldProvider: DotNsTldProviding
    let entropyManager: RootEntropyManaging

    init(
        tldProvider: DotNsTldProviding = DotNsTldProviderFacade.shared,
        entropyManager: RootEntropyManaging = RootEntropyManager.shared
    ) {
        self.tldProvider = tldProvider
        self.entropyManager = entropyManager
    }
}

extension AttachmentsSenderProvider: AttachmentsSenderProviding {
    func getWallet(for chatId: Chat.Id) async throws -> WalletManaging {
        guard let peerAccountId = chatId.accountId else {
            throw AttachmentsSenderProviderError.unsupportedChat
        }

        let derivationPath = try ChatKeyPaths.hop(tld: tldProvider.currentTldOrError(), peerAccountId: peerAccountId)

        return DynamicDerivedWallet(derivationPath: derivationPath, entropyManager: entropyManager)
    }
}
