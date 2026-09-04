import UIKit
import PolkadotUI

@MainActor
final class MainTabBarPresenter {
    weak var view: MainTabBarViewProtocol?
    let wireframe: MainTabBarWireframeProtocol
    let interactor: MainTabBarInteractorInputProtocol

    #if FEATURE_PRODUCTS
        let slots: [TabBarSlot] = [
            .tab(.chat), .tab(.wallet), .action(.scan), .tab(.browse), .tab(.settings), .action(.more)
        ]
    #else
        let slots: [TabBarSlot] = [
            .tab(.chat), .tab(.wallet), .action(.scan), .tab(.settings), .action(.more)
        ]
    #endif

    private let chipViewModelFactory: SPATabChipViewModelFactory
    private let tabFactory: TabFactoryProtocol
    private var settingsBadge: TabBarBadge?

    init(
        interactor: MainTabBarInteractorInputProtocol,
        wireframe: MainTabBarWireframeProtocol,
        chipViewModelFactory: SPATabChipViewModelFactory,
        tabFactory: TabFactoryProtocol
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.chipViewModelFactory = chipViewModelFactory
        self.tabFactory = tabFactory
    }
}

extension MainTabBarPresenter: MainTabBarPresenterProtocol {
    func setup() {
        interactor.setup()
    }

    func configureViews() {
        view?.show(slots: slots, selecting: .wallet)
        view?.setBadge(settingsBadge, for: .settings)
    }

    func didRequestContentPanel(for action: TabBarAction) {
        switch action {
        case .scan:
            view?.showTabBarPanelController(tabFactory.makeScanController(), for: action)
        case .more:
            view?.showTabBarPanelContent(TabBarPanelPlaceholderContent.make(), for: action)
        case .spaTabs:
            break
        }
    }
}

extension MainTabBarPresenter: MainTabBarInteractorOutputProtocol {
    func didUpdateSettingsAttention(isVisible: Bool) {
        let nextBadge = isVisible ? TabBarBadge.attention : nil
        guard settingsBadge != nextBadge else {
            return
        }
        settingsBadge = nextBadge
        view?.setBadge(settingsBadge, for: .settings)
    }

    func didReceiveWidget(
        configuration: any HashableContentConfiguration,
        for extensionId: ChatExtension.Id
    ) {
        view?.attachWidget(
            configuration,
            for: AppWidgetID(extensionId)
        )
    }

    func didRemoveWidget(for extensionId: ChatExtension.Id) {
        view?.detachWidget(for: AppWidgetID(extensionId))
    }

    func didReceivePolkadotSignInRequest(with url: URL) {
        wireframe.showPolkadotSignIn(with: url, view: view)
    }

    func didReceiveSPATabs(_ tabs: [SPATab]) {
        view?.showSPATabs(chipViewModelFactory.createViewModels(for: tabs))
    }

    func didReceiveChainStatus(_ rows: [ChainConnectionStatusViewModel]) {
        view?.showChainStatus(rows)
    }
}
