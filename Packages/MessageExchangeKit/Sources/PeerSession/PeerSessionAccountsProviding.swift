import Foundation

/// Per-peer accounts for device-route statements and uploads. A session built with a provider
/// leaves the identity route unsigned.
public protocol PeerSessionAccountsProviding {
    func statementSignKeyId(for request: MessageExchange.SessionRequest) throws -> String
    func uploadSignKeyId(for request: MessageExchange.SessionRequest) throws -> String
}
