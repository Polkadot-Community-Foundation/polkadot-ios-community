import Foundation
import ChainRegistry

/// Vends the given sockets in order, then nil, recording every request.
final class MockChainSocketResolver: @unchecked Sendable {
    private(set) var vended: [MockChainSocket] = []
    private(set) var requests: [(genesisHash: Data, attempt: Int)] = []
    private var remaining: [MockChainSocket]

    init(_ sockets: [MockChainSocket]) {
        remaining = sockets
    }

    func next(genesisHash: Data, attempt: Int) -> ChainSocketProtocol? {
        requests.append((genesisHash, attempt))
        guard !remaining.isEmpty else { return nil }
        let socket = remaining.removeFirst()
        vended.append(socket)
        return socket
    }
}
