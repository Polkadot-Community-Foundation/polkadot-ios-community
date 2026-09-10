import Foundation
@testable import polkadot_app

actor MockChainLivenessAnchorProvider: ChainLivenessAnchorProviding {
    private(set) var fetchAnchorCalls: [(target: ChainConnectionTarget, slotCount: Int)] = []
    private var anchorToReturn: ChainLivenessAnchor?
    private var errorToThrow: Error?

    func setAnchor(_ anchor: ChainLivenessAnchor?) {
        anchorToReturn = anchor
    }

    func setError(_ error: Error?) {
        errorToThrow = error
    }

    func fetchAnchor(
        for target: ChainConnectionTarget,
        slotCount: Int
    ) async throws -> ChainLivenessAnchor {
        fetchAnchorCalls.append((target: target, slotCount: slotCount))

        if let error = errorToThrow {
            throw error
        }

        guard let anchor = anchorToReturn else {
            throw NSError(domain: "MockChainLivenessAnchorProvider", code: -1)
        }

        return anchor
    }
}
