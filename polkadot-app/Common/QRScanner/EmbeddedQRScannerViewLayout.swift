import UIKit
import UIKit_iOS
import PolkadotUI
import DesignSystem

/// Bare camera preview for the tab bar panel: no dimmed cutout and no frame border, with the
/// message label drawn straight over the preview.
final class EmbeddedQRScannerViewLayout: QRScannerViewLayout {
    override func setupLayout() {
        backgroundColor = .clear

        // The panel measures this view, so the square preview is declared here rather than by
        // whatever hosts it.
        heightAnchor.constraint(equalTo: widthAnchor).isActive = true

        addSubview(qrFrameView)
        qrFrameView.layer.cornerRadius = DSRadii.extraLarge
        qrFrameView.layer.masksToBounds = true

        qrFrameView.fillColor = .clear
        qrFrameView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(DSSpacings.tiny)
        }

        messageLabel.textColor = .fgPrimary
        addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.leading.trailing.equalTo(qrFrameView).inset(DSSpacings.mediumIncreased)
            make.centerY.equalTo(qrFrameView)
        }
    }
}
