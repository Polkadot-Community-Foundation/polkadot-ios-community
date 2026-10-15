import Foundation
import KeyDerivation
import Products

/// Ring-VRF proof contexts allocated to the personhood product (individuality
/// `support/src/context.rs`, `pub mod personhood`). Each case is one
/// `ProductContextSuffix::Index(n)`, which the pallets hash as
///
///     blake2b256("product/" ++ "peopl" ++ "." ++ networkSuffix ++ "/"
///                ++ u32_le(index) ++ blake2b256("product-account-index")[..28])
///
/// `PersonhoodProductContextTests` pins the bytes against the pallet's vectors. These are proof
/// contexts only: `SelectedWallet` still uses the `PalletContext` values as key derivation paths.
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

    /// The 32-byte ring-VRF context for `peopl.<networkSuffix>`. `networkSuffix` must be the
    /// runtime's `NetworkSuffix` value; any other suffix yields a context the chain rejects.
    func context(networkSuffix: String) throws -> Data {
        try ProductProofContext(
            productId: BuiltInProduct.personhood(for: networkSuffix),
            suffix: .index(index)
        ).contextBytes()
    }
}

extension DotNsTldProviding {
    /// Builds a personhood proof context from the cached `NetworkSuffix`. Throws rather than
    /// guessing a suffix.
    func personhoodContext(for allocation: PersonhoodProductContext) throws -> Data {
        try allocation.context(networkSuffix: currentTldOrError())
    }
}
