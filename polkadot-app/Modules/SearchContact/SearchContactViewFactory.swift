import Foundation

@MainActor
enum SearchContactViewFactory {
    static func createView(with model: SearchContactModel) -> SearchContactViewProtocol? {
        let walletRepo: WalletManagerRepositoryProtocol = .shared
        guard let ownAccountId = try? walletRepo.main().getRawPublicKey() else {
            assertionFailure()
            return nil
        }

        let localContactSearch = LocalContactSearchService(
            repositoryFactory: ChatContactRepositoryFactory()
        )
        let recentChatsProvider = RecentChatsProvider(
            chatProvider: ChatContactDataProviderFactory()
        )

        let accountSearching: any AccountSearching<Chat.RemoteContact, Chat.RemoteContact> =
            ChatAccountSearchProvider(
                recentChatsProvider: recentChatsProvider,
                localContactSearch: localContactSearch,
                remoteContactSearch: RemoteContactOperationFactory(),
                ownAccountId: ownAccountId
            )

        let interactor = SearchContactInteractor(
            accountSearching: accountSearching
        )
        let wireframe = SearchContactWireframe(model: model)

        let presenter = SearchContactPresenter(
            interactor: interactor,
            wireframe: wireframe
        )

        let view = SearchContactViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }
}
