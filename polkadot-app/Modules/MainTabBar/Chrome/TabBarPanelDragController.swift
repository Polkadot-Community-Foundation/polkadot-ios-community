import UIKit
import PolkadotUI

/// Handles interactive dragging of the scan panel. Close decision is taken on release only,
/// never mid-drag.
@MainActor
final class TabBarPanelDragController {
    private enum Constants {
        static let closeFraction: CGFloat = 0.3
        static let minimumCloseDistance: CGFloat = 44
    }

    private unowned let surface: TabBarChromeSurfaceView
    private unowned let panelController: TabBarPanelController
    private var openHeight: CGFloat?

    init(surface: TabBarChromeSurfaceView, panelController: TabBarPanelController) {
        self.surface = surface
        self.panelController = panelController
    }

    func dragChanged(translation: CGFloat) {
        guard panelController.open != nil else { return }

        if self.openHeight == nil {
            panelController.cancelHeightAnimation()
        }

        let openHeight = openHeight ?? surface.panelHeight
        self.openHeight = openHeight

        let newHeight = max(
            min(openHeight - translation, openHeight),
            DSTabBarView.capsuleHeight
        )
        surface.setPanelHeight(newHeight)
    }

    func dragEnded(translation: CGFloat) {
        defer { openHeight = nil }

        guard let openHeight else { return }

        let closeThreshold = max(
            openHeight * Constants.closeFraction,
            Constants.minimumCloseDistance
        )

        if translation >= closeThreshold {
            panelController.setPanel(nil, animated: true)
        } else {
            panelController.restoreOpenHeight()
        }
    }
}
