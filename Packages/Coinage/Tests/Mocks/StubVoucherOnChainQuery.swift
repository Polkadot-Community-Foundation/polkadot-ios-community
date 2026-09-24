import Foundation
import os
@testable import Coinage

/// A voucher query answering from a per-block table and recording the block hash each read asked for.
///
/// `nil` as a block key stands for "best head" (a read with `atBlockHash: nil`).
final class StubVoucherOnChainQuery: VoucherOnChainQuerying, @unchecked Sendable {
    struct Read: Equatable {
        let indices: [CoinageKeyIndex]
        let atBlockHash: Data?
    }

    private let state = OSAllocatedUnfairLock<(
        infos: [Data?: [CoinageKeyIndex: VoucherOnChainInfo]],
        reads: [Read]
    )>(initialState: ([:], []))

    var reads: [Read] { state.withLock { $0.reads } }

    func setInfo(_ info: VoucherOnChainInfo, for index: CoinageKeyIndex, atBlockHash blockHash: Data?) {
        state.withLock { $0.infos[blockHash, default: [:]][index] = info }
    }

    func fetchVouchers(
        for derivationIndices: [CoinageKeyIndex],
        atBlockHash: Data?
    ) async throws -> [VoucherOnChainInfo?] {
        state.withLock { state in
            state.reads.append(Read(indices: derivationIndices, atBlockHash: atBlockHash))
            let table = state.infos[atBlockHash] ?? [:]
            return derivationIndices.map { table[$0] }
        }
    }
}
