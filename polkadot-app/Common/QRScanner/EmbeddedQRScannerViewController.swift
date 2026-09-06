import UIKit
import PolkadotUI

/// Hosted as a child of the tab bar panel rather than presented, so it drops the framed
/// full-screen chrome. With no message label in the layout, presenter messages surface as
/// the standard error toast over the camera preview instead.
final class EmbeddedQRScannerViewController: QRScannerViewController {
    override func loadView() {
        view = EmbeddedQRScannerViewLayout(frame: .zero)
    }

    override func present(message: String, animated _: Bool, autoDismiss _: Bool) {
        showToast(message: message, type: .error, duration: messageVisibilityDuration)
    }
}
