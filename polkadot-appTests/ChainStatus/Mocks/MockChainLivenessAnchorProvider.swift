import Foundation
@testable import polkadot_app

actor MockChainLivenessAnchorProvider: ChainLivenessAnchorProviding {
    private(set) var fetchAnchorCalls: [(target: ChainConnectionTarget, slotCount: Int)] = []
    private var anchorToReturn: ChainLivenessAnchor?
    private var errorToThrow: Error?
    private var isGateClosed = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func setAnchor(_ anchor: ChainLivenessAnchor?) {
        anchorToReturn = anchor
    }

    func setError(_ error: Error?) {
        errorToThrow = error
    }

    /// Parks every subsequent fetch until `release()`, so a test can observe the provider while a
    /// probe is genuinely outstanding. Without this the mock answers immediately and the hold
    /// cannot be exercised at all — a test would only be racing the completion.
    func closeGate() {
        isGateClosed = true
    }

    func openGate() {
        isGateClosed = false
    }

    /// Resumes everything parked so far. Does not change whether new calls park.
    func release() {
        let resumed = waiters
        waiters = []
        resumed.forEach { $0.resume() }
    }

    /// Waits until at least `count` fetches have been recorded, so a test never reads the call
    /// log before the spawned probe tasks have reached it.
    func waitForCallCount(atLeast count: Int, timeout: Duration = .seconds(5)) async {
        let deadline = ContinuousClock.now + timeout
        while fetchAnchorCalls.count < count, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func fetchAnchor(
        for target: ChainConnectionTarget,
        slotCount: Int
    ) async throws -> ChainLivenessAnchor {
        fetchAnchorCalls.append((target: target, slotCount: slotCount))

        if isGateClosed {
            await withCheckedContinuation { waiters.append($0) }
        }

        if let error = errorToThrow {
            throw error
        }

        guard let anchor = anchorToReturn else {
            throw NSError(domain: "MockChainLivenessAnchorProvider", code: -1)
        }

        return anchor
    }
}
