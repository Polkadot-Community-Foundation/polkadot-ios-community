import Foundation
import KeyDerivation
import SubstrateSdk

enum ChatKeyPathsError: Error, Equatable {
    case invalidJunction(String)
}

enum ChatKeyPaths {
    static func statement(tld: String, peerAccountId: AccountId) -> String {
        perChatPath(tld: tld, role: "peer-statement", peerAccountId: peerAccountId)
    }

    static func hop(tld: String, peerAccountId: AccountId) -> String {
        perChatPath(tld: tld, role: "peer-hop", peerAccountId: peerAccountId)
    }

    static func request(requestId: String, period: UInt32) throws -> String {
        try oneShotPath(namespace: "chat-request", requestId: requestId, period: period)
    }

    static func accept(requestId: String, period: UInt32) throws -> String {
        try oneShotPath(namespace: "chat-accept", requestId: requestId, period: period)
    }
}

private extension ChatKeyPaths {
    // The 0x prefix makes the junction parser take the peer id as raw chain code, not as a number or string.
    static func perChatPath(tld: String, role: String, peerAccountId: AccountId) -> String {
        ProductDerivationPath.builtInRoot(BuiltInProduct.chat(for: tld)) +
            "//\(role)//" + peerAccountId.toHex(includePrefix: true)
    }

    static func oneShotPath(namespace: String, requestId: String, period: UInt32) throws -> String {
        guard !requestId.isEmpty, !requestId.contains("/") else {
            throw ChatKeyPathsError.invalidJunction(requestId)
        }

        return "//\(namespace)//\(requestId)//\(period)"
    }
}
