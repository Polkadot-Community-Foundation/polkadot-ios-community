import CoreData
import Coinage
import Foundation

/// Derives the durability overlay (``CoinageAssetState``) for a coin or voucher row from its
/// input/output entry relations.
enum CoinageAssetStateDeriver {
    /// `isRecovered`: the row was allocated by a previous installation. Recovery found it on the
    /// finalized chain; nothing local minted it and nothing local can ever prove that mint failed, so
    /// it reads as a finalized mint. A recorded minting entry, if one exists, is reported as it stands.
    static func state(
        handedOff: Bool,
        isRecovered: Bool,
        inputs: NSSet?,
        output: CDCoinageTxOutput?
    ) -> CoinageAssetState {
        CoinageAssetState(
            handedOff: handedOff,
            consumerStatus: consumerStatus(of: inputs),
            minterStatus: status(of: output?.entry) ?? (isRecovered ? .finalizedSuccess : nil)
        )
    }

    /// At most one non-failure entry consumes an asset (Unique consumer invariant), so its status
    /// is the asset's live consumer status; a released (failed-only) asset has none.
    private static func consumerStatus(of inputs: NSSet?) -> CoinageTxStatus? {
        ((inputs as? Set<CDCoinageTxInput>) ?? [])
            .compactMap { status(of: $0.entry) }
            .first { $0 != .failure }
    }

    private static func status(of entry: CDDurableTx?) -> CoinageTxStatus? {
        entry.flatMap { CoinageTxStatus(rawValue: Int($0.status)) }
    }
}
