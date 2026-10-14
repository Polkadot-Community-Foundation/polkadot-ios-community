import Foundation
import KeyDerivation

protocol AttachmentsSenderProviding {
    func getWallet() async throws -> WalletManaging
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
    func getWallet() async throws -> WalletManaging {
        try DynamicDerivedWallet(derivationPath: peerAccounts.uploadKeyId(), entropyManager: entropyManager)
    }
}
