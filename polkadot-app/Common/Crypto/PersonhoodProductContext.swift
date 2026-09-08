import Foundation
import KeyDerivation
import Products

/// Ring-VRF proof contexts allocated to the personhood product by individuality
/// `support/src/context.rs` (`pub mod personhood`).
///
/// Each case is one `ProductContextSuffix::Index(n)` on chain. The pallets hash it through
/// `build_product_context(personhood::PRODUCT_NAME, &T::Suffix::get(), suffix)`
/// (`pallets/score/src/lib.rs`, `pallets/resources/src/lib.rs`), which is:
///
///     blake2b256("product/" ++ "peopl" ++ "." ++ networkSuffix ++ "/"
///                ++ u32_le(index) ++ blake2b256("product-account-index")[..28])
///
/// `ProductProofContext.contextBytes()` already builds that preimage and
/// `BuiltInProduct.personhood(for:)` already builds the `peopl.<suffix>` product id, so this type
/// only owns the index allocation. `PersonhoodProductContextTests` pins the resulting bytes against
/// the pallet's own vectors — a wrong byte here yields a valid-looking 32-byte context whose alias
/// only the live chain rejects.
///
/// These replace `PalletContext.score` / `PalletContext.resources` as **proof contexts** only.
/// The same constants stay in use as **key derivation paths** in `SelectedWallet` — a different
/// mechanism that decides which account you hold, not which alias it proves. Do not conflate them.
/// After this migration `PalletContext.score` has no remaining use; do not reuse it.
enum PersonhoodProductContext: CaseIterable, Sendable {
    /// `personhood::SCORE` — `ProductContextSuffix::Index(0)`.
    case score
    /// `personhood::RESOURCES` — `ProductContextSuffix::Index(1)`.
    case resources

    /// The chain's context-suffix index allocation. These numbers are consensus: changing one
    /// changes every alias derived through it.
    var index: UInt32 {
        switch self {
        case .score: 0
        case .resources: 1
        }
    }

    /// The 32-byte ring-VRF context for `peopl.<networkSuffix>`.
    ///
    /// `networkSuffix` must come from the runtime's own `NetworkSuffix` storage value — the chain
    /// builds its half from `T::Suffix::get()`, so a hardcoded or guessed suffix silently produces
    /// a context the chain will not accept.
    func context(networkSuffix: String) throws -> Data {
        try ProductProofContext(
            productId: BuiltInProduct.personhood(for: networkSuffix),
            suffix: .index(index)
        ).contextBytes()
    }
}

extension DotNsTldProviding {
    /// Builds a personhood proof context from the cached network suffix.
    ///
    /// The cached value originates in `NetworkSuffixTldReader.readTld()`, which reads the same
    /// `NetworkSuffix` storage item the runtime hashes. It strips one leading `.` and rejects any
    /// value containing `.`, so it equals the raw runtime suffix for every bare-label suffix
    /// (`dot`, `paseo`) — which is the only shape the runtime ships.
    ///
    /// Throws rather than falling back to a default: a guessed suffix produces a valid-looking
    /// context that fails only against the live chain.
    func personhoodContext(for allocation: PersonhoodProductContext) throws -> Data {
        try allocation.context(networkSuffix: currentTldOrError())
    }
}
