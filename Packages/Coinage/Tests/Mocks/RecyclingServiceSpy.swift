import AsyncExtensions
import Foundation
@testable import Coinage

/// Records every recycle batch and reports each given coin as submitted.
actor RecyclingServiceSpy: CoinageRecyclingServicing {
    private(set) var recycledBatches: [[Coin]] = []

    func recycleCoins(_ coins: [Coin], groupId _: CoinageTxGroupId?) async throws -> Int {
        recycledBatches.append(coins)
        return coins.count
    }

    nonisolated func observeRecycling(groupId _: CoinageTxGroupId) -> AnyAsyncSequence<RecyclingStatus> {
        AsyncStream<RecyclingStatus> { $0.finish() }.eraseToAnyAsyncSequence()
    }
}
