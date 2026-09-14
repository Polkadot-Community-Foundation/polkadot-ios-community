import Foundation
import PolkadotUI
import UIKit

@MainActor
enum TransferPrivacyViewFactory {
    static func createGainingPrivacyConfirmation(
        amount: String,
        onSendAnyway: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> UIViewController {
        let wireframe = TransferPrivacyWireframe()
        let presenter = TransferPrivacyPresenter(
            model: TransferPrivacyModel(amount: amount),
            wireframe: wireframe,
            onSendAnyway: onSendAnyway,
            onCancel: onCancel
        )
        let view = TransferPrivacyViewController(presenter: presenter)
        presenter.view = view
        BottomSheetViewFacade.setupBottomSheet(from: view)
        return view
    }
}
