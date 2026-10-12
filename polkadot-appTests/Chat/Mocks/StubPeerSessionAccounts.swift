import Foundation
import MessageExchangeKit

struct StubPeerSessionAccounts: PeerSessionAccountsProviding {
    let statementKeyId: String
    let uploadKeyId: String

    func statementSignKeyId(for _: MessageExchange.SessionRequest) throws -> String {
        statementKeyId
    }

    func uploadSignKeyId(for _: MessageExchange.SessionRequest) throws -> String {
        uploadKeyId
    }
}
