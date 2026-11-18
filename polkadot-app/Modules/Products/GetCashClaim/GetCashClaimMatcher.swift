#if TESTNET_FEATURE
    import struct TrUAPIHost.ProductId
    import func TrUAPIHost.productIdName
    import BigInt
    import ChainRegistry
    import Foundation
    import Products
    import Revive
    import SubstrateSdk

    /// Recognises Get CASH calling `claim(...)` on its faucet contract from its own product account on
    /// Asset Hub, with no value attached.
    struct GetCashClaimMatcher {
        private static let productName = "getcash"

        /// Selector of `claim(uint8,bytes32,uint32,uint128,bytes,bytes32,uint32,uint32)`.
        static let claimSelector = Data([0xEC, 0x7E, 0xBC, 0x62])

        let claimContract: EvmAddress
        let assetHubChainId: ChainModel.Id

        /// The checks that need no runtime: the contract is set, the caller is Get CASH, it signs with its
        /// own product account, and the transaction is for Asset Hub.
        func isCandidate(
            callerProductId: ProductId,
            signer: ProductAccountId,
            chainId: ChainModel.Id
        ) -> Bool {
            claimContract != EvmAddressFormat.zero
                && productIdName(productId: callerProductId) == Self.productName
                && signer.productId == callerProductId
                && chainId == assetHubChainId
        }

        func isClaim(_ call: RuntimeCall<JSON>) -> Bool {
            guard
                call.moduleName == RevivePallet.name,
                call.callName == RevivePallet.callName,
                let args = try? call.args.map(to: ClaimCallArgs.self)
            else {
                return false
            }

            return args.dest == claimContract
                && args.value == 0
                && args.data.starts(with: Self.claimSelector)
        }
    }

    private extension GetCashClaimMatcher {
        /// The `Revive.call` arguments the rule checks.
        struct ClaimCallArgs: Decodable {
            @BytesCodable var dest: EvmAddress
            @StringCodable var value: BigUInt
            @BytesCodable var data: Data
        }
    }
#endif
