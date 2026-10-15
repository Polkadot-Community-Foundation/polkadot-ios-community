import Foundation

/// The shared account that signs attachment uploads.
public protocol PeerSessionAccountsProviding {
    func uploadSignKeyId() throws -> String
}
