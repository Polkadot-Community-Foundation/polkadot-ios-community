import AsyncExtensions
import Foundation

/// The coins of `publicKeys` the chain holds, on every look that could be taken.
///
/// A key that goes absent drops out of the underlying map, so an emission is the whole set visible at
/// that block. A look that cannot be taken is never emitted — the subscription simply does not yield —
/// so a failed read can never erase what the chain last showed.
func coinPresence(
    of publicKeys: Set<PublicKey>,
    reading query: any CoinOnChainQuerying
) -> AnyAsyncSequence<Set<PublicKey>> {
    query
        .subscribeCoinInfos(for: Array(publicKeys))
        .map { Set($0.keys) }
        .eraseToAnyAsyncSequence()
}

/// The vouchers of `indices` the chain currently shows sitting in a recycler, polled on an interval.
///
/// A voucher counts as present while it sits in a recycler: that is where an unload proves it, and one
/// that left was redeemed by something else. Unlike coin presence there is no subscription for this, so
/// it is polled — and a read that fails is simply not emitted, so a failed read never erases what the
/// chain last showed.
func voucherRecyclerPresence(
    of indices: Set<CoinageKeyIndex>,
    reading query: any VoucherOnChainQuerying,
    pollInterval: Duration,
    clock: any Clock<Duration>
) -> AnyAsyncSequence<Set<CoinageKeyIndex>> {
    let ordered = Array(indices)

    return AsyncStream<Set<CoinageKeyIndex>> { continuation in
        let task = Task {
            while !Task.isCancelled {
                if let reads = try? await query.fetchVouchers(for: ordered) {
                    continuation.yield(inRecycler(reads, of: ordered))
                }

                do {
                    try await clock.sleep(for: pollInterval)
                } catch {
                    break
                }
            }

            continuation.finish()
        }

        continuation.onTermination = { _ in task.cancel() }
    }
    .eraseToAnyAsyncSequence()
}

private func inRecycler(
    _ reads: [VoucherOnChainInfo?],
    of indices: [CoinageKeyIndex]
) -> Set<CoinageKeyIndex> {
    zip(indices, reads).reduce(into: Set<CoinageKeyIndex>()) { present, pair in
        guard let read = pair.1, case .inRecycler = read.onChainState else { return }

        present.insert(pair.0)
    }
}
