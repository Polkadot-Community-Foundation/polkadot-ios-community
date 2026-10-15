import Foundation
import MessageExchangeKit
import Products
import StatementStore
import SubstrateSdk

protocol ChatPeerAccountsProviding {
    func statementKeyId(for peerAccountId: AccountId) throws -> String
    func uploadKeyId() throws -> String
}

struct ChatPeerAccounts {
    let tldProvider: DotNsTldProviding

    init(tldProvider: DotNsTldProviding = DotNsTldProviderFacade.shared) {
        self.tldProvider = tldProvider
    }
}

extension ChatPeerAccounts: ChatPeerAccountsProviding {
    func statementKeyId(for peerAccountId: AccountId) throws -> String {
        try ChatKeyPaths.statement(tld: tldProvider.currentTldOrError(), peerAccountId: peerAccountId)
    }

    func uploadKeyId() throws -> String {
        try ChatKeyPaths.hop(tld: tldProvider.currentTldOrError())
    }
}

extension ChatPeerAccounts: PeerSessionAccountsProviding {
    func uploadSignKeyId() throws -> String {
        try uploadKeyId()
    }
}

protocol ChatStatementSignerResolving {
    /// Signer of the per-chat statement account toward the peer.
    func statementSigner(for peerAccountId: AccountId) throws -> StatementStoreSigning
}

struct ChatStatementSignerResolver: ChatStatementSignerResolving {
    let peerAccounts: ChatPeerAccountsProviding
    let signManager: StatementStoreSignerManaging

    init(
        peerAccounts: ChatPeerAccountsProviding = ChatPeerAccounts(),
        signManager: StatementStoreSignerManaging = ChatSignerManager()
    ) {
        self.peerAccounts = peerAccounts
        self.signManager = signManager
    }

    func statementSigner(for peerAccountId: AccountId) throws -> StatementStoreSigning {
        try signManager.makeSigner(for: peerAccounts.statementKeyId(for: peerAccountId))
    }
}
