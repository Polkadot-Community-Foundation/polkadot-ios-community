import Foundation
import MessageExchangeKit
import Products
import StatementStore
import SubstrateSdk

protocol ChatPeerAccountsProviding {
    func statementKeyId(for peerAccountId: AccountId) throws -> String
    func uploadKeyId(for peerAccountId: AccountId) throws -> String
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

    func uploadKeyId(for peerAccountId: AccountId) throws -> String {
        try ChatKeyPaths.hop(tld: tldProvider.currentTldOrError(), peerAccountId: peerAccountId)
    }
}

extension ChatPeerAccounts: PeerSessionAccountsProviding {
    func statementSignKeyId(for request: MessageExchange.SessionRequest) throws -> String {
        try statementKeyId(for: request.peer.accountId)
    }

    func uploadSignKeyId(for request: MessageExchange.SessionRequest) throws -> String {
        try uploadKeyId(for: request.peer.accountId)
    }
}

protocol ChatStatementAccountResolving {
    func statementAccountId(for peerAccountId: AccountId) throws -> AccountId
}

struct ChatStatementAccountResolver: ChatStatementAccountResolving {
    let peerAccounts: ChatPeerAccountsProviding
    let signManager: StatementStoreSignerManaging

    func statementAccountId(for peerAccountId: AccountId) throws -> AccountId {
        try signManager.makeSigner(for: peerAccounts.statementKeyId(for: peerAccountId)).accountId
    }
}
