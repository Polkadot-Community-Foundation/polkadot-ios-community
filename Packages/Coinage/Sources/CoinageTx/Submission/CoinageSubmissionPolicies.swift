import DurableTransactions
import Foundation
import NovaCrypto
import SDKLogger
import SubstrateSdk

/// Builds and registers coinage's three submission policies.
///
/// They must be registered before anything carrying one is submitted: a row naming an unregistered
/// policy is abandoned by the executor rather than left waiting, and a failure for it is written as the
/// failure it already was instead of being offered a rebuild.
enum CoinageSubmissionPolicies {
    struct Dependencies {
        let chainId: ChainId
        let ledger: any CoinageAssetLedgerProtocol
        let coinService: any CoinServiceProtocol
        let voucherService: any VoucherServiceProtocol
        let coinQuery: any CoinOnChainQuerying
        let voucherQuery: any VoucherOnChainQuerying
        let splitBuilder: SplitExtrinsicBuilder
        let unloadBuilder: UnloadExtrinsicBuilder
        let claimBuilder: ClaimExtrinsicBuilder
        let snKeyFactory: any SNKeyFactoryProtocol
        let logger: SDKLoggerProtocol?
    }

    /// How often voucher presence is polled while a rebuild waits. Vouchers have no subscription, and
    /// an unload waits on the order of blocks, not milliseconds.
    static let voucherPollInterval: Duration = .seconds(6)

    static func register(into registry: DurableSubmissionPolicyRegistry, using deps: Dependencies) {
        registry.register(split(deps), for: CoinageSubmissionParams.splitPolicyId)
        registry.register(unload(deps), for: CoinageSubmissionParams.unloadPolicyId)
        registry.register(claim(deps), for: CoinageSubmissionParams.claimPolicyId)
    }
}

private extension CoinageSubmissionPolicies {
    static func split(_ deps: Dependencies) -> InputGatedSubmissionPolicy<SplitRebuild> {
        InputGatedSubmissionPolicy(
            policyId: CoinageSubmissionParams.splitPolicyId,
            chainId: deps.chainId,
            rebuild: SplitRebuild(
                coinService: deps.coinService,
                coinQuery: deps.coinQuery,
                builder: deps.splitBuilder
            ),
            ledger: deps.ledger,
            logger: deps.logger
        )
    }

    static func unload(_ deps: Dependencies) -> InputGatedSubmissionPolicy<UnloadRebuild> {
        InputGatedSubmissionPolicy(
            policyId: CoinageSubmissionParams.unloadPolicyId,
            chainId: deps.chainId,
            rebuild: UnloadRebuild(
                coinService: deps.coinService,
                voucherService: deps.voucherService,
                voucherQuery: deps.voucherQuery,
                builder: deps.unloadBuilder,
                pollInterval: voucherPollInterval,
                clock: ContinuousClock(),
                now: { Date() }
            ),
            ledger: deps.ledger,
            logger: deps.logger
        )
    }

    static func claim(_ deps: Dependencies) -> InputGatedSubmissionPolicy<ClaimRebuild> {
        InputGatedSubmissionPolicy(
            policyId: CoinageSubmissionParams.claimPolicyId,
            chainId: deps.chainId,
            rebuild: ClaimRebuild(
                coinQuery: deps.coinQuery,
                builder: deps.claimBuilder,
                snKeyFactory: deps.snKeyFactory
            ),
            ledger: deps.ledger,
            logger: deps.logger
        )
    }
}
