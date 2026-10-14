import Foundation

/// Per-peer device-route statement accounts and the shared upload account.
public protocol PeerSessionAccountsProviding {
    func statementSignKeyId(for request: MessageExchange.SessionRequest) throws -> String
    func uploadSignKeyId() throws -> String
}
