import UIKit

/// A view controller that may be presenting another controller modally.
///
/// Abstracts the two `UIViewController` members navigation code needs when it
/// has to route somewhere while a page is presented on top of the tab bar, so
/// the behaviour can be unit tested without a live window hierarchy.
@MainActor
protocol ModalPresenting: AnyObject {
    var presentedViewController: UIViewController? { get }
    func dismiss(animated flag: Bool, completion: (() -> Void)?)
}

extension UIViewController: ModalPresenting {}

/// Helper that dismisses an open modal page before performing navigation.
///
/// Without it, navigation from a notification tap selects its destination behind a
/// Browse/product page presented over the tab bar.
@MainActor
enum ModalDismiss {
    /// Runs `action` after ensuring nothing is presented on `presenter`.
    ///
    /// - If `presenter` currently shows a modally-presented controller, it is
    ///   dismissed without animation and `action` runs on completion.
    /// - Otherwise `action` runs immediately.
    static func dismissingPresented(
        on presenter: ModalPresenting?,
        then action: @escaping () -> Void
    ) {
        guard let presenter, presenter.presentedViewController != nil else {
            action()
            return
        }

        presenter.dismiss(animated: false, completion: action)
    }
}
