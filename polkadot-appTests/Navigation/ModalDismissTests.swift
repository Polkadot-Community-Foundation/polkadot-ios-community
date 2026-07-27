import Testing
import UIKit

@testable import polkadot_app

@Suite("ModalDismiss")
@MainActor
struct ModalDismissTests {
    private final class MockPresenter: ModalPresenting {
        var stubbedPresented: UIViewController?
        private(set) var dismissCallCount = 0
        private(set) var lastDismissAnimated: Bool?

        var presentedViewController: UIViewController? { stubbedPresented }

        func dismiss(animated flag: Bool, completion: (() -> Void)?) {
            dismissCallCount += 1
            lastDismissAnimated = flag
            completion?()
        }
    }

    @Test("Runs the action immediately when no page is presented")
    func runsImmediatelyWhenNothingPresented() {
        let presenter = MockPresenter()
        var didNavigate = false

        ModalDismiss.dismissingPresented(on: presenter) { didNavigate = true }

        #expect(didNavigate)
        #expect(presenter.dismissCallCount == 0)
    }

    // Regression for products-devnet-issues#2: tapping a chat notification while a
    // Browse/product page is open must dismiss that page before navigating, so the
    // conversation is not selected behind the still-visible page.
    @Test("Dismisses the open page without animation, then runs the action")
    func dismissesPresentedThenRuns() {
        let presenter = MockPresenter()
        presenter.stubbedPresented = UIViewController()
        var events: [String] = []

        ModalDismiss.dismissingPresented(on: presenter) { events.append("navigated") }

        #expect(presenter.dismissCallCount == 1)
        #expect(presenter.lastDismissAnimated == false)
        #expect(events == ["navigated"])
    }

    @Test("Still runs the action when the presenter is nil")
    func runsWhenPresenterNil() {
        var didNavigate = false

        ModalDismiss.dismissingPresented(on: nil) { didNavigate = true }

        #expect(didNavigate)
    }
}
