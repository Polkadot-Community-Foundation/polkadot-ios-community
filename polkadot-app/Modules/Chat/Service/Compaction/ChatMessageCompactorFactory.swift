import Foundation
import MessageExchangeKit
import ChainRegistry
import KeyDerivation
import Individuality

protocol ChatMessageCompactorMaking: MessageCompactorMaking
    where Message == Chat.OpaqueMessage {}

final class ChatMessageCompactorFactory: @unchecked Sendable {
    let hopNodeProvider: HOPNodeProviding
    let hopLoaderFactory: HOPFileLoaderMaking
    let allowanceManager: AllowanceManaging
    let peerAccounts: ChatPeerAccountsProviding
    let logger: LoggerProtocol

    init(
        chainRegistry: ChainRegistryProtocol = ChainRegistryFacade.sharedRegistry,
        allowanceManager: AllowanceManaging,
        peerAccounts: ChatPeerAccountsProviding = ChatPeerAccounts(),
        logger: LoggerProtocol = Logger.shared
    ) {
        hopNodeProvider = HOPNodeProvider(chainRegistry: chainRegistry)
        hopLoaderFactory = HOPFileLoaderFactory(logger: logger)
        self.allowanceManager = allowanceManager
        self.peerAccounts = peerAccounts
        self.logger = logger
    }
}

extension ChatMessageCompactorFactory: ChatMessageCompactorMaking {
    // Uploads are signed by the shared HOP account, never by the identity account.
    func createCompactor() throws -> AnyMessageCompactor<Chat.OpaqueMessage>? {
        let proofWallet = try DynamicDerivedWallet(derivationPath: peerAccounts.uploadKeyId())

        let compactor = ChatMessageCompactor(
            nodeProvider: hopNodeProvider,
            loaderFactory: hopLoaderFactory,
            proofWallet: proofWallet,
            allowanceManager: allowanceManager,
            logger: logger
        )

        return AnyMessageCompactor(compactor)
    }
}
