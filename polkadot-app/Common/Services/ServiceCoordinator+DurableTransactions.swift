import BackgroundExecution
import DurableTransactions
import Foundation

extension ServiceCoordinator {
    /// The one durable transaction engine every domain shares. Built once; a domain registers its oracle
    /// with `engine.oracles` before it submits anything, and the first domain to start it drives the
    /// head-driven recovery for all of them.
    static func createDurableTransactionEngine(
        chainViewFactory: any PinnedChainViewFactoryProtocol
    ) -> DurableTxService {
        let chainRegistry = ChainRegistryFacade.sharedRegistry
        let operationQueue = OperationManagerFacade.sharedDefaultQueue

        let extrinsicFacade = ExtrinsicSubmissionMonitorFacade(
            chainRegistry: chainRegistry,
            substrateStorageFacade: SubstrateDataStorageFacade.shared,
            operationQueue: operationQueue
        )

        return DurableTxService.make(
            store: DurableTxCoreDataRepository(
                storageFacade: UserDataStorageFacade.shared,
                rowObservers: [CoinageTxRowObserver()]
            ),
            chainViewFactory: chainViewFactory,
            chainTools: DurableChainToolsProvider(chainRegistry: chainRegistry, extrinsicFacade: extrinsicFacade),
            backgroundExecutor: ConnectionRetainingExecutor(provider: chainRegistry),
            logger: Logger.shared
        )
    }
}
