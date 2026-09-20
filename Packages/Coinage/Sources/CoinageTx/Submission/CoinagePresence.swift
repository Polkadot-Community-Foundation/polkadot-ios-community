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
