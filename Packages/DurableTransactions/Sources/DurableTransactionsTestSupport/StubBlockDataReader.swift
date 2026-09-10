import AsyncExtensions
import DurableTransactions
import Foundation
import SubstrateOperation
import SubstrateSdk

/// Test stub for the block-outcome lookup closure ``BlockBodyScan`` scans with; records all calls and
/// returns configured responses. A hash absent from the map returns `.unreadable`.
public actor StubBlockDataReader {
    private let lookups: [Data: BlockLookup]
    public private(set) var reads: [Data] = []

    public init(lookups: [Data: BlockLookup] = [:]) {
        self.lookups = lookups
    }

    public func lookUp(_: Data, at blockHash: Data) async -> BlockLookup {
        reads.append(blockHash)
        return lookups[blockHash] ?? .unreadable
    }
}

/// Test stub for ``BlockInfoProviding`` that returns configured block hashes. Throws when a block
/// number is not in the configured mapping, simulating a failed hash fetch.
public final class StubBlockInfoProvider: BlockInfoProviding {
    private let hashes: [UInt32: Data]

    public init(hashes: [UInt32: Data] = [:]) {
        self.hashes = hashes
    }

    public func fetchCurrentHash() async throws -> BlockHashData {
        Data()
    }

    public func fetchCurrent() async throws -> BlockNumber {
        BlockNumber(0)
    }

    public func fetchFinalized() async throws -> BlockNumber {
        BlockNumber(0)
    }

    public func fetchFinalizedHash() async throws -> BlockHashData {
        Data()
    }

    public func fetchBlockHash(_ number: BlockNumber) async throws -> BlockHashData {
        guard let hash = hashes[UInt32(number)] else {
            throw BlockFetchError.blockNotFound
        }
        return hash
    }

    public func subscribeFinalizedHeads() -> AnyAsyncSequence<Block.Header> {
        AsyncStream<Block.Header> { _ in }.eraseToAnyAsyncSequence()
    }

    public func subscribeNewHeads() -> AnyAsyncSequence<Block.Header> {
        AsyncStream<Block.Header> { $0.finish() }.eraseToAnyAsyncSequence()
    }
}

private enum BlockFetchError: Error {
    case blockNotFound
}
