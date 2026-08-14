import UIKit
import Products

@MainActor
protocol ModuleNavigating: AnyObject {
    func openChat(_ model: ChatOpenModel)
    func presentModally(_ viewController: UIViewController)
    func openProduct(page: ProductPage)
}

extension ModuleNavigating {
    func openChat(_ chat: Chat.Id) {
        openChat(.existingChat(chat))
    }
}

final class ModuleNavigator {}

extension ModuleNavigator: ModuleNavigating {
    func presentModally(_ viewController: UIViewController) {
        let navigationController = AppNavigationController(rootViewController: viewController)
        navigationController.modalPresentationStyle = .pageSheet
        UIWindow.topWindow?.topmostViewController?.present(navigationController, animated: true)
    }

    func openChat(_ model: ChatOpenModel) {
        guard let view = UIApplication.shared.mainTabBarController else {
            return
        }

        let navigate = { [weak view] in
            guard let view else { return }

            view.select(tab: .chat)
            let tabNavigation = view.view(for: .chat) as? UINavigationController

            if case let .existingChat(chat) = model {
                let existing = tabNavigation?.viewControllers
                    .compactMap { $0 as? ChatViewController }
                    .first(where: { $0.presenter.chatId == chat })
                if let existing {
                    tabNavigation?.popToViewController(existing, animated: true)
                    return
                }
            }

            guard
                let contactList = tabNavigation?.viewControllers.first as? ContactsListViewController
            else {
                return
            }
            let contactListPresenter = contactList.presenter as? ContactsListPresenter
            contactListPresenter?.wireframe.showChat(from: contactList, for: model)

            // removing intermediate chats
            guard
                let tabNavigation,
                tabNavigation.viewControllers.count > 2,
                let rootViewController = tabNavigation.viewControllers.first,
                let topViewController = tabNavigation.viewControllers.last
            else {
                return
            }
            tabNavigation.viewControllers = [rootViewController, topViewController]
        }

        // A chat notification tap must land on the conversation even when a
        // Browse/product page is presented modally on top of the tab bar.
        // Dismiss it first, otherwise the chat is selected *behind* the open
        // page and nothing appears to happen — see products-devnet-issues#2.
        ModalDismiss.dismissingPresented(on: view, then: navigate)
    }

    func openProduct(page: ProductPage) {
        guard let tabBar = UIWindow.keyWindow?.rootViewController as? MainTabBarViewController else {
            return
        }

        // The de-duplication this used to do by hand is now upstream's
        // (`browserCoordinator.findOrCreateTab`), but the SPA is still mounted *inside* the
        // tab bar, so a page presented modally on top would hide it. Keep dismissing first,
        // for the same reason as `openChat` above — see products-devnet-issues#2.
        ModalDismiss.dismissingPresented(on: tabBar) { [weak tabBar] in
            tabBar?.openProduct(page: page)
        }
    }
}
