import UIKit
import UIKit_iOS
import PolkadotUI
import DesignSystem

/// Bare camera preview for the tab bar panel: no dimmed cutout, no frame border, no labels.
/// `fillColor` is what draws the dimming in `CameraFrameView`, so clearing it removes the
/// window entirely and the preview fills the view.
final class EmbeddedQRScannerViewLayout: QRScannerViewLayout {
    override func setupLayout() {
        // The base init paints `bgSurfaceMain`; the panel's glass must show through the inset.
        backgroundColor = .clear

        // The panel measures this view, so the square preview is declared here rather than by
        // whatever hosts it.
        heightAnchor.constraint(equalTo: widthAnchor).isActive = true

        addSubview(qrFrameView)

        qrFrameView.fillColor = .clear
        qrFrameView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(DSSpacings.tiny)
        }
    }
}
