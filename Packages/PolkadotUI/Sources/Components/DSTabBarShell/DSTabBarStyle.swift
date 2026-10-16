import CoreGraphics
import DesignSystem
import UIKit

/// Geometry and fixed visual values of the tab bar. The bar has one shape, so none of these are configurable.
public enum DSTabBarStyle {
    /// Height of the bar row itself, not counting the gap below it.
    public static let height: CGFloat = 62

    /// Inset of the bar row from each side of the screen.
    public static let horizontalMargin: CGFloat = 10
    /// Widest the bar row grows. Wider screens leave the extra width to either side.
    public static let maxWidth: CGFloat = 440

    /// Smallest gap between the bar row and the bottom of the screen.
    private static let minimumBottomGap: CGFloat = 12
    /// The bottom safe area inset already clears part of the screen, so the gap shrinks by this much of it.
    private static let bottomGapInsetReduction: CGFloat = 7

    /// Gap between the bar row and the bottom of the screen, given the bottom safe area inset.
    public static func bottomGap(bottomSafeAreaInset: CGFloat) -> CGFloat {
        max(minimumBottomGap, bottomSafeAreaInset - bottomGapInsetReduction)
    }

    /// Width of the bar row in a host `availableWidth` wide: inset by the margins and capped at `maxWidth`.
    public static func rowWidth(inAvailableWidth availableWidth: CGFloat) -> CGFloat {
        min(max(0, availableWidth - horizontalMargin * 2), maxWidth)
    }

    /// Height the bar occupies once it has settled, which is what a host publishes as bottom
    /// clearance for its content.
    public static func restingHeight(bottomSafeAreaInset: CGFloat) -> CGFloat {
        height + bottomGap(bottomSafeAreaInset: bottomSafeAreaInset)
    }

    static var cornerRadius: CGFloat { height / 2 }
    static let itemInset: CGFloat = 4
    /// Vertical inset of the selection pill inside the bar row.
    static let selectionInset: CGFloat = 4
    /// Width of the selection pill. It is centred on its slot and may overflow the slot.
    static let selectionWidth: CGFloat = 80
    /// Response of the spring that carries the selection pill between slots.
    static let selectionSpringResponse: Double = 0.4
    static let selectionSpringDamping: Double = 0.8
    /// Corner radius of the selection pill drawn behind a shelf view.
    static let shelfSelectionCornerRadius: CGFloat = DSRadii.mediumIncreased
    static let strokeWidth: CGFloat = 1

    /// Gap between the hole's edge and the centre control sitting in it.
    static let notchRingGap: CGFloat = 2
    /// Radius of the hole cut from the bar: the centre control plus the ring gap around it.
    static var notchRadius: CGFloat { centerButtonSize / 2 + notchRingGap }
    /// Hole centre, measured down from the top of the bar row.
    static let notchCenterY: CGFloat = 22
    /// How far the hole reaches above the bar row, into the shelf.
    static var notchOverhang: CGFloat { notchRadius - notchCenterY }
    /// Gap the two inner slots leave around the notch. It is the cutout's width at the bar's top edge.
    static let notchShoulderWidth: CGFloat = 74

    /// Whether a point in the bar row's coordinate space falls on the centre button, which the
    /// fold gesture must not claim.
    public static func isInCenterHole(_ point: CGPoint, inRowOfWidth width: CGFloat) -> Bool {
        let center = CGPoint(x: width / 2, y: notchCenterY)
        return hypot(point.x - center.x, point.y - center.y) <= notchRadius
    }

    /// Strength of the variable blur. A material property, not a colour.
    static let blurIntensity: Double = 0.35

    /// Opacity of the contrast wash over the blur. Slight enough to read as a wash rather than
    /// a fill, so the bar stays translucent in every theme.
    static let tintOpacity: Double = 0.018

    /// Opacity of the rim at the top of the bar, where it reads as catching the light.
    static let rimTopOpacity: Double = 0.14
    /// Opacity of the rim at the foot, where it has all but faded out.
    static let rimBottomOpacity: Double = 0.035

    static let shadowRadius: CGFloat = 18
    /// Reach of the shadow mask past the bar, so the blurred shadow is not cut off at the bar edge.
    static let shadowMaskSpread: CGFloat = shadowRadius * 4 + 40

    /// Response of the spring that grows and collapses the shelf. Damping sits just under critical,
    /// so the bar settles with at most a slight overshoot. Public because a host driving the shelf
    /// from UIKit has to match its settle.
    public static let shelfSpringResponse: Double = 0.18
    public static let shelfSpringDamping: Double = 0.9

    /// Response of the spring that settles the centre control open or closed. Public because a host
    /// driving the control from UIKit has to match the control's own settle.
    public static let centerSpringResponse: Double = 0.26
    public static let centerSpringDamping: Double = 0.88

    /// Length of the eased shelf reveal under Reduce Motion, growth and fade together. Matches
    /// the centre control's.
    static let shelfFadeDuration: Double = 0.2

    /// Diameter of the centre control at rest. It sits in the hole with a ring gap.
    static let centerButtonSize: CGFloat = 64
    static let centerPanelCornerRadius: CGFloat = 32
    /// Depth of the lobe hanging below the panel's body. It holds the centre glyph.
    static let centerLobeDepth: CGFloat = 31
    /// Half the lobe's width once the panel is 88 pt wide. Narrower panels scale it down with their width.
    static let centerLobeHalfWidth: CGFloat = 44
    /// How far a drag can stretch the open panel past its full height before the resistance holds it.
    static let centerStretchLimit: CGFloat = 32
    /// How quickly the stretch builds. A larger value stretches the panel further for the same pull.
    static let centerStretchCoefficient: CGFloat = 0.55

    /// Width the open centre panel takes in a bar row of `width`: the full width of the bar.
    public static func centerPanelWidth(inRowOfWidth width: CGFloat) -> CGFloat {
        max(centerButtonSize, width)
    }

    /// Height the open centre panel takes for content of `contentHeight`, lobe included. The grabber
    /// floats over the content, so the caller provides its clearance inside `contentHeight`.
    /// The body's corner arcs need vertical room of their own, so the panel never drops below them.
    public static func centerPanelHeight(contentHeight: CGFloat) -> CGFloat {
        let minimumHeight = centerPanelCornerRadius * 2 + centerLobeDepth
        return max(minimumHeight, contentHeight + centerLobeDepth)
    }

    /// Foot of the centre button, measured down from the top of the bar row. The open panel's lobe keeps it.
    public static var centerButtonFootFromRowTop: CGFloat { notchCenterY + centerButtonSize / 2 }

    /// How far the resting centre button stands above the bar row. A host's touch region has to reach this
    /// high, or the top of the button passes touches through.
    public static var centerButtonRestingRise: CGFloat { centerButtonSize / 2 - notchCenterY }

    /// How far the open centre panel stands above the bar row.
    public static func centerPanelRise(contentHeight: CGFloat) -> CGFloat {
        centerPanelHeight(contentHeight: contentHeight) - centerButtonFootFromRowTop
    }

    /// The tallest content a centre panel can host without standing more than `rise` above the bar row.
    /// The inverse of `centerPanelRise(contentHeight:)`, for a host that has to cap the panel.
    public static func centerContentHeight(fittingRise rise: CGFloat) -> CGFloat {
        max(0, rise + centerButtonFootFromRowTop - centerButtonSize / 2)
    }

    /// Runs `changes` on the centre control's spring and lays out `view` inside the same animation, so UIKit
    /// moves whatever `changes` touches in step with the control. Snaps under Reduce Motion.
    public static func animateCenterChange(in view: UIView, _ changes: @escaping () -> Void) {
        guard !UIAccessibility.isReduceMotionEnabled else {
            changes()
            return
        }
        UIView.animate(
            withDuration: centerSpringResponse,
            delay: 0,
            usingSpringWithDamping: centerSpringDamping,
            initialSpringVelocity: 0
        ) {
            changes()
            view.layoutIfNeeded()
        }
    }

    /// Opacity of the centre control's rim at its top edge.
    static let centerRimTopOpacity: Double = 0.252
    /// Opacity of the centre control's rim at its foot, where it has faded out.
    static let centerRimBottomOpacity: Double = 0.042

    /// Distance the grabber sits below the top of the open panel.
    static let centerGrabberTopInset: CGFloat = 6
    static let centerGrabberWidth: CGFloat = 36
    static let centerGrabberThickness: CGFloat = 5

    /// Distance the camera sits below the top of the open scan panel with search unfocused.
    public static let scanCameraTopInset: CGFloat = 19
    /// Side of the square camera in the open scan panel with search unfocused.
    public static let scanCameraSide: CGFloat = 110
    /// Gap from the camera's bottom edge to the search field's top edge.
    public static let scanFieldTopGap: CGFloat = 9
    /// Height of the search field in the open scan panel.
    public static let scanFieldHeight: CGFloat = 48
    /// Gap from the search field's bottom edge to the bottom of the panel body.
    public static let scanFieldBottomInset: CGFloat = 18

    /// Content height of the open scan panel with search unfocused. The same at every panel width.
    public static var scanStateHeight: CGFloat {
        scanCameraTopInset + scanCameraSide + scanFieldTopGap + scanFieldHeight + scanFieldBottomInset
    }

    static let centerShadowRadius: CGFloat = 10
    static let centerShadowY: CGFloat = 4
}
