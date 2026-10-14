import Foundation

/// Per-peer device-route statement accounts and the shared upload account. A session built with a provider
/// leaves the identity route unsigned.
public protocol PeerSessionAccountsProviding {
    func statementSignKeyId(for request: MessageExchange.SessionRequest) throws -> String
    func uploadSignKeyId() throws -> String
}
