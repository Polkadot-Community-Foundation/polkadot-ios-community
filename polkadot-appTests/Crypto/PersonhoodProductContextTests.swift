import Foundation
import Individuality
import KeyDerivation
@testable import polkadot_app
import Products
import SubstrateSdk
import Testing

/// Byte-level pins for the personhood product contexts (RFC-0004 / RFC-0022).
///
/// Every expected value here is derived from the **pallet**, not from this app:
/// individuality `support/src/context.rs` at `v0.3.1` defines
///
///     build_product_context(product_name, network_suffix, suffix)
///         = blake2b_256("product/" ++ product_name ++ "." ++ network_suffix ++ "/" ++ suffix.bytes())
///     ProductContextSuffix::Index(n).bytes() = u32_le(n) ++ INDEX_MAGIC
///     INDEX_MAGIC = blake2b_256("product-account-index")[..28]
///     personhood::PRODUCT_NAME = b"peopl"
///     personhood::SCORE        = Index(0)     (pallets/score/src/lib.rs `score_context()`)
///     personhood::RESOURCES    = Index(1)     (pallets/resources/src/lib.rs `resources_context()`)
///
/// The same construction is pinned on Android by `PersonhoodProductContextTest` and
/// `ProductProofContextTest` at `polkadot-android-community@7b0c63e`.
///
/// A wrong byte here produces a valid-looking 32-byte context and a valid-looking alias that only
/// the live chain rejects — there is no type error and no crash. Do not "fix" a failing vector by
/// re-deriving it from this Swift code; re-derive it from the Rust.
@Suite("Personhood product contexts")
struct PersonhoodProductContextTests {
    /// `blake2b256("product-account-index")[..28]`, as asserted by the pallet's own
    /// `index_magic_matches_rfc_derivation` test and by Android's `DerivationIndex32Test`.
    private static let indexMagicHex = "12e86013736c5498f050b03cdc16957dff0e422fb92ca77ec3ab168f"

    // MARK: - Cross-implementation vectors

    /// The pins that matter. Hashes were computed from the Rust definition above and
    /// cross-checked against two independent BLAKE2b implementations.
    ///
    /// `dot` is the suffix our runtime is configured with, so `peopl.dot` matches the reserved
    /// DotNS identity. `paseo` is upstream's genesis default (`DefaultNetworkSuffix` in
    /// `runtimes/next-people-paseo/src/people.rs`) and is pinned too: if the chain ever answered
    /// `paseo`, these are the contexts the app would build, and they are different values.
    @Test(arguments: [
        (
            "dot", PersonhoodProductContext.score,
            "0x21f4e1b44577e6c94b34000247fa4888d9148ec6a5753da33a6e408dbcc08ae0"
        ),
        (
            "dot", PersonhoodProductContext.resources,
            "0x25f866ef352e1fcef9df0bbae08bb0bcf1881b7db959234748ced5de77b5a209"
        ),
        (
            "paseo", PersonhoodProductContext.score,
            "0x99f1920ec7217a74f0a682b5713af915aea099843bab68e74cd6463e5ec6e842"
        ),
        (
            "paseo", PersonhoodProductContext.resources,
            "0xdffa2eae45fa7cefaf20a97e85a6e4fc9beffd6596fdd2e2687015e8e123b072"
        )
    ])
    func contextMatchesPalletVector(
        networkSuffix: String,
        allocation: PersonhoodProductContext,
        expectedHex: String
    ) throws {
        let expected = try Data(hexString: expectedHex)

        #expect(try allocation.context(networkSuffix: networkSuffix) == expected)
    }

    /// The index allocations themselves — `personhood::SCORE = Index(0)`,
    /// `personhood::RESOURCES = Index(1)`. Swapping these silently swaps two aliases.
    @Test
    func indexAllocationsMatchThePallet() {
        #expect(PersonhoodProductContext.score.index == 0)
        #expect(PersonhoodProductContext.resources.index == 1)
    }

    /// `ProductContextSuffix::Index(n).bytes()` — little-endian `u32` then the magic. Mirrors
    /// Android's `index suffix layout is pinned` and the pallet's
    /// `index_suffix_uses_little_endian_index_and_magic`. Big-endian would be silent: index 0
    /// is byte-identical either way, index 1 is not.
    @Test
    func indexSuffixIsLittleEndianFollowedByTheMagic() throws {
        let magic = Self.indexMagicHex

        #expect(try DerivationIndex32(index: 0).bytes == Data(hexString: "0x00000000" + magic))
        #expect(try DerivationIndex32(index: 1).bytes == Data(hexString: "0x01000000" + magic))
        // The pallet's own unit-test vector for a multi-byte index.
        #expect(try DerivationIndex32(index: 0x0102_0304).bytes == Data(hexString: "0x04030201" + magic))
    }

    // MARK: - Composition

    /// Rebuilds the preimage literally, the way `build_product_context` does, and checks the
    /// helper agrees. This pins the *composition* (`product/`, the `.` before the suffix, the
    /// trailing `/`, the order of the parts) independently of the hex vectors above — a wrong
    /// separator would otherwise only show up as four simultaneously wrong hashes.
    @Test(arguments: ["dot", "paseo"])
    func contextIsHashOfTheRfcPreimage(networkSuffix: String) throws {
        for allocation in PersonhoodProductContext.allCases {
            var preimage = Data("product/peopl.\(networkSuffix)/".utf8)
            preimage += DerivationIndex32(index: allocation.index).bytes

            #expect(try allocation.context(networkSuffix: networkSuffix) == preimage.blake2b32())
        }
    }

    /// The helper must build its product id as `peopl.<suffix>` — the reserved DotNS identity —
    /// and must route through the shared `ProductProofContext` hashing rather than its own copy.
    @Test(arguments: ["dot", "paseo", "ksm"])
    func productIdIsThePersonhoodReservedIdentity(networkSuffix: String) throws {
        #expect(BuiltInProduct.personhood(for: networkSuffix) == "peopl.\(networkSuffix)")

        for allocation in PersonhoodProductContext.allCases {
            let viaProductProofContext = ProductProofContext(
                productId: "peopl.\(networkSuffix)",
                suffix: .index(allocation.index)
            )

            #expect(try allocation.context(networkSuffix: networkSuffix)
                == viaProductProofContext.contextBytes())
        }
    }

    // MARK: - Discrimination

    /// The unlinkability properties the product prefix exists for: a different allocation and a
    /// different network must both yield a different context.
    @Test
    func contextsAreDiscriminatedByAllocationAndNetwork() throws {
        let scoreDot = try PersonhoodProductContext.score.context(networkSuffix: "dot")
        let resourcesDot = try PersonhoodProductContext.resources.context(networkSuffix: "dot")
        let scorePaseo = try PersonhoodProductContext.score.context(networkSuffix: "paseo")

        #expect(scoreDot != resourcesDot)
        #expect(scoreDot != scorePaseo)
        #expect(scoreDot.count == 32)
        #expect(resourcesDot.count == 32)
    }

    /// The migration is a real byte change, not a rename: the new contexts share nothing with the
    /// padded pallet strings the app used before the RFC-0004 runtime. Guards against a partial
    /// revert that leaves one call site on the legacy constant.
    @Test
    func newContextsDifferFromTheLegacyPaddedStrings() throws {
        #expect(try PersonhoodProductContext.score.context(networkSuffix: "dot")
            != Data(PalletContext.score.utf8))
        #expect(try PersonhoodProductContext.resources.context(networkSuffix: "dot")
            != Data(PalletContext.resources.utf8))
    }

    // MARK: - Suffix resolution

    /// The suffix is read from chain, never hardcoded: the provider decides the bytes.
    @Test
    func providerSuffixDrivesTheContext() throws {
        let dotProvider = StubDotNsTldProvider(tld: "dot")
        let paseoProvider = StubDotNsTldProvider(tld: "paseo")

        #expect(try dotProvider.personhoodContext(for: .score)
            == PersonhoodProductContext.score.context(networkSuffix: "dot"))
        #expect(try paseoProvider.personhoodContext(for: .resources)
            == PersonhoodProductContext.resources.context(networkSuffix: "paseo"))
        #expect(try dotProvider.personhoodContext(for: .score)
            != paseoProvider.personhoodContext(for: .score))
    }

    /// With no cached suffix the call must throw rather than fall back to a default. A guessed
    /// suffix would submit an alias the chain rejects, which is worse than a visible failure.
    @Test
    func missingSuffixThrowsInsteadOfGuessing() {
        let provider = StubDotNsTldProvider(tld: nil)

        #expect(throws: DotNsTldError.self) { try provider.personhoodContext(for: .score) }
        #expect(throws: DotNsTldError.self) { try provider.personhoodContext(for: .resources) }
    }
}
