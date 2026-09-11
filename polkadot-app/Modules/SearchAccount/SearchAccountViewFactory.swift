import Foundation
import Coinage
import ChainRegistry
import MessageExchangeKit

@MainActor
enum SearchAccountViewFactory {
    static func createView(
        for chainAsset: ChainAsset,
        coinageServicing: CoinageServicing
    ) -> SearchAccountViewProtocol? {
        let logger = Logger.shared
        let operationQueue = OperationManagerFacade.sharedDefaultQueue
        let chainRegistry = ChainRegistryFacade.sharedRegistry
        let recentContactsService = RecentContactsService(
            recentContactsSubscriptionFactory: RecentContactsSubscriptionFactory.shared,
            identityQueryFactory: IdentityPalletQueryFactory(
                operationQueue: operationQueue
            ),
            chainRegistry: chainRegistry,
            usernameChainId: AppConfig.Chains.usernameChain,
            operationQueue: operationQueue,
            logger: logger
        )
        let localContactSearch = LocalContactSearchService(
            repositoryFactory: ChatContactRepositoryFactory()
        )
        let recentRecipientsProvider = RecentRecipientsProvider(
            service: recentContactsService,
            chainFormat: chainAsset.chain.chainFormat,
            logger: logger
        )

        let accountSearching: any AccountSearching<
            RecentContactModelWithUsername,
            ContactSearchPayload
        > = RecipientAccountSearchProvider(
            recentRecipientsProvider: recentRecipientsProvider,
            localContactSearch: localContactSearch,
            remoteContactSearch: RemoteContactOperationFactory(),
            chainFormat: chainAsset.chain.chainFormat,
            logger: logger
        )

        let recipientViewModelFactory = RecipientViewModelFactory()
        let interactor = SearchAccountInteractor(
            accountSearching: accountSearching,
            chatOpenResolver: ChatOpenModelResolver(),
            chainAsset: chainAsset,
            logger: logger
        )
        let wireframe = SearchAccountWireframe(coinageServicing: coinageServicing)
        let presenter = SearchAccountPresenter(
            interactor: interactor,
            wireframe: wireframe,
            recipientViewModelFactory: recipientViewModelFactory,
            chainAsset: chainAsset
        )

        let view = SearchAccountViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }
}
