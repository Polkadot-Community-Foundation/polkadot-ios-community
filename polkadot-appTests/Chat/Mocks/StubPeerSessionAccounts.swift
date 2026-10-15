import Foundation
import MessageExchangeKit

struct StubPeerSessionAccounts: PeerSessionAccountsProviding {
    let uploadKeyId: String

    func uploadSignKeyId() throws -> String {
        uploadKeyId
    }
}
