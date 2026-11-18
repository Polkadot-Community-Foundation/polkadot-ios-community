#if TESTNET_FEATURE
    import struct TrUAPIHost.ProductId
    import ChainRegistry
    import Foundation
    import Products
    import Revive
    import SubstrateSdk
    import Testing

    @testable import polkadot_app

    @Suite("GetCashClaimMatcher")
    struct GetCashClaimMatcherTests {
        private static let contract = EvmAddress(repeating: 0x5A, count: EvmAddressFormat.size)
        private static let assetHub = "asset-hub"
        private static let getCash = try! ProductId("getcash.dot")

        @Test("A claim from Get CASH's own product account on Asset Hub matches")
        func ownAccountClaimMatches() {
            let matcher = makeMatcher()

            #expect(isCandidate(matcher))
            #expect(matcher.isClaim(reviveCall()))
        }

        @Test("Any account index in Get CASH's own product subtree matches")
        func otherIndexOfOwnAccountMatches() {
            let signer = ProductAccountId(productId: Self.getCash, derivationIndex: .index(7))

            #expect(isCandidate(makeMatcher(), signer: signer))
        }

        @Test("Other products do not match", arguments: ["faucet.dot", "getcash-next.dot", "app.getcash.dot"])
        func otherProductsDoNotMatch(name: String) throws {
            let caller = try ProductId(name)

            #expect(!isCandidate(makeMatcher(), caller: caller))
        }

        @Test("Get CASH signing with another product's account does not match")
        func otherProductAccountDoesNotMatch() throws {
            let signer = try account(of: ProductId("faucet.dot"))

            #expect(!isCandidate(makeMatcher(), signer: signer))
        }

        @Test("Chains other than Asset Hub do not match")
        func otherChainDoesNotMatch() {
            #expect(!isCandidate(makeMatcher(), chainId: "people"))
        }

        @Test("The zero contract address turns the rule off")
        func zeroContractNeverMatches() {
            #expect(!isCandidate(makeMatcher(contract: EvmAddressFormat.zero)))
        }

        @Test("Calls to another contract do not match")
        func otherContractDoesNotMatch() {
            let otherContract = EvmAddress(repeating: 0x11, count: EvmAddressFormat.size)

            #expect(!makeMatcher().isClaim(reviveCall(dest: otherContract)))
        }

        @Test("Calls that carry value do not match")
        func callWithValueDoesNotMatch() {
            #expect(!makeMatcher().isClaim(reviveCall(value: "1")))
        }

        @Test("Other contract functions do not match")
        func otherSelectorDoesNotMatch() {
            let otherFunction = Data([0x01, 0x02, 0x03, 0x04]) + Data(repeating: 0x01, count: 32)

            #expect(!makeMatcher().isClaim(reviveCall(data: otherFunction)))
            #expect(!makeMatcher().isClaim(reviveCall(data: Data([0xEC, 0x7E]))))
        }

        @Test("Other calls do not match")
        func otherCallsDoNotMatch() {
            #expect(!makeMatcher().isClaim(reviveCall(callName: "instantiate")))
            #expect(!makeMatcher().isClaim(reviveCall(moduleName: "Balances", callName: "transfer_keep_alive")))
        }
    }

    private extension GetCashClaimMatcherTests {
        func makeMatcher(contract: EvmAddress = Self.contract) -> GetCashClaimMatcher {
            GetCashClaimMatcher(claimContract: contract, assetHubChainId: Self.assetHub)
        }

        func account(of productId: ProductId) -> ProductAccountId {
            ProductAccountId(productId: productId, derivationIndex: .index(0))
        }

        /// Defaults to Get CASH signing with its own product account on Asset Hub.
        func isCandidate(
            _ matcher: GetCashClaimMatcher,
            caller: ProductId = Self.getCash,
            signer: ProductAccountId? = nil,
            chainId: ChainModel.Id = Self.assetHub
        ) -> Bool {
            matcher.isCandidate(callerProductId: caller, signer: signer ?? account(of: caller), chainId: chainId)
        }

        /// `Revive.call` arguments in the shape the runtime decoder produces: `H160` and `Vec<u8>` as arrays
        /// of decimal byte strings, compact balances as decimal strings.
        func reviveCall(
            moduleName: String = "Revive",
            callName: String = "call",
            dest: EvmAddress = Self.contract,
            value: String = "0",
            data: Data = GetCashClaimMatcher.claimSelector + Data(repeating: 0x01, count: 32)
        ) -> RuntimeCall<JSON> {
            RuntimeCall(
                moduleName: moduleName,
                callName: callName,
                args: .dictionaryValue([
                    "dest": bytes(dest),
                    "value": .stringValue(value),
                    "weight_limit": .dictionaryValue([
                        "ref_time": .stringValue("1000000000"),
                        "proof_size": .stringValue("100000")
                    ]),
                    "storage_deposit_limit": .stringValue("0"),
                    "data": bytes(data)
                ])
            )
        }

        func bytes(_ data: Data) -> JSON {
            .arrayValue(data.map { .stringValue(String($0)) })
        }
    }
#endif
