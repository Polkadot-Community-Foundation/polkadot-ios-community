#if TESTNET_FEATURE
    import struct TrUAPIHost.ProductId
    import AssetsManagement
    import ChainRegistry
    import Foundation
    import Individuality
    import Products
    import Revive
    import StructuredConcurrency
    import SubstrateSdk
    import SubstrateSdkExt

    enum GetCashClaimSignerError: Error {
        case unexpectedSigningResult
    }

    /// Signs Get CASH's faucet `claim(...)` with its own product account and no signing sheet, as a general
    /// transaction on the Asset Hub pipeline that pays the fee in PGAS. Tops the account up with PGAS first,
    /// without a prompt. Any other request gets `nil` and takes the regular signing flow.
    final class GetCashClaimSigner {
        /// Asset Hub's transaction extension version whose pipeline charges the fee in PGAS.
        static let pgasExtensionVersion: UInt8 = 1

        private let callerProductId: ProductId
        private let matcher: GetCashClaimMatcher
        private let accountManager: ProductsAccountManaging
        private let pgasSponsor: PGasTransactionSponsoring
        private let pgasProvisioner: PGASAccountProvisioning
        private let chainRegistry: ChainRegistryProtocol
        private let requestResultFactory: PolkadotSigningRequestResultMaking
        private let signatureFactory: PolkadotSignatureMaking
        private let logger: LoggerProtocol

        init(
            callerProductId: ProductId,
            matcher: GetCashClaimMatcher,
            accountManager: ProductsAccountManaging,
            pgasSponsor: PGasTransactionSponsoring,
            pgasProvisioner: PGASAccountProvisioning,
            chainRegistry: ChainRegistryProtocol,
            requestResultFactory: PolkadotSigningRequestResultMaking,
            signatureFactory: PolkadotSignatureMaking = PolkadotSignatureFactory(),
            logger: LoggerProtocol
        ) {
            self.callerProductId = callerProductId
            self.matcher = matcher
            self.accountManager = accountManager
            self.pgasSponsor = pgasSponsor
            self.pgasProvisioner = pgasProvisioner
            self.chainRegistry = chainRegistry
            self.requestResultFactory = requestResultFactory
            self.signatureFactory = signatureFactory
            self.logger = logger
        }

        func createTransactionIfClaim(
            _ payload: CreateTransactionPayload<ProductAccountId>
        ) async throws -> CreateTransactionResult? {
            guard await matchesClaim(payload) else { return nil }

            logger.info("Signing Get CASH claim from \(callerProductId.rawValue) without the signing sheet")

            do {
                try await ensurePgas(for: payload.signer)
                return try await sign(payload)
            } catch {
                logger.error("Get CASH claim signing failed: \(error)")
                throw error
            }
        }
    }

    extension GetCashClaimSigner {
        /// `nil` when the claim contract is not a valid H160 or no PGAS allowance manager is registered.
        static func make(
            callerProductId: ProductId,
            accountManager: ProductsAccountManaging,
            pgasSponsor: PGasTransactionSponsoring,
            chainRegistry: ChainRegistryProtocol,
            logger: LoggerProtocol
        ) -> GetCashClaimSigner? {
            guard
                let claimContract = try? EvmAddressFormat.validate(
                    Data(hexString: AppConfig.GetCashFaucet.claimContract)
                ),
                let dependencies: TruApiDependenciesLocator = RootDependencyLocator.getDependency(),
                let allowanceSupport: AllowanceSupport = dependencies.getDependency()
            else {
                return nil
            }

            let pgasProvisioner = PGASAccountProvisioner(
                allowanceManager: allowanceSupport.smartContractManager,
                domain: .product,
                balanceProvider: CoinageDataStorePgasProvider(
                    chainResource: chainRegistry,
                    balanceService: BalanceQueryService(
                        chainResource: chainRegistry,
                        operationQueue: OperationManagerFacade.sharedDefaultQueue
                    )
                ),
                issueDiagnostics: .make(flow: "pgas-allowance", reporter: IssueReportingFacade.shared)
            )

            return GetCashClaimSigner(
                callerProductId: callerProductId,
                matcher: GetCashClaimMatcher(
                    claimContract: claimContract,
                    assetHubChainId: AppConfig.Chains.assethubChain
                ),
                accountManager: accountManager,
                pgasSponsor: pgasSponsor,
                pgasProvisioner: pgasProvisioner,
                chainRegistry: chainRegistry,
                requestResultFactory: PolkadotSigningRequestResultFactory(chainRegistry: chainRegistry),
                logger: logger
            )
        }
    }

    private extension GetCashClaimSigner {
        func matchesClaim(_ payload: CreateTransactionPayload<ProductAccountId>) async -> Bool {
            guard
                let chainId = chainRegistry.getChainByGenesis(for: payload.genesisHash.toHex())?.chainId,
                matcher.isCandidate(callerProductId: callerProductId, signer: payload.signer, chainId: chainId),
                let runtimeProvider = chainRegistry.getRuntimeProvider(for: chainId),
                let codingFactory = try? await runtimeProvider.fetchCoderFactoryOperation().asyncExecute(),
                let call = codingFactory.decodeRuntimeCall(from: payload.callData)
            else {
                return false
            }

            return matcher.isClaim(call)
        }

        /// Claims PGAS into the product account below the threshold the PGAS sponsor uses.
        func ensurePgas(for account: ProductAccountId) async throws {
            let accountId = try accountManager.deriveAccount(account)
            let sufficientBalance = try await pgasSponsor.sufficientBalance()

            try await pgasProvisioner.ensureCovers(account: accountId, required: sufficientBalance)
        }

        func sign(_ payload: CreateTransactionPayload<ProductAccountId>) async throws -> CreateTransactionResult {
            // The product account always signs the claim, so a product-supplied VerifySignature is dropped.
            let claimPayload = CreateTransactionPayload(
                signer: payload.signer,
                genesisHash: payload.genesisHash,
                callData: payload.callData,
                extensions: payload.extensions.filter { $0.id != Extrinsic.TransactionExtensionId.verifySignature },
                txExtVersion: Self.pgasExtensionVersion
            )

            let context = ProductSigningContext(
                requesterName: callerProductId.rawValue,
                signingModel: .createTransaction(claimPayload)
            )

            let parsedResult = try await requestResultFactory.makeParsedResult(signingContext: context)
            let signingResult = try await signatureFactory.makeSignature(
                result: parsedResult,
                chainRegistry: chainRegistry
            )

            guard case let .signedTransaction(encodedTransaction) = signingResult else {
                throw GetCashClaimSignerError.unexpectedSigningResult
            }

            return CreateTransactionResult(signedTransaction: encodedTransaction.toHex(includePrefix: true))
        }
    }
#endif
