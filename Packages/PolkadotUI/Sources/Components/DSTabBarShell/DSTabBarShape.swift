import SwiftUI

/// Bar outline with the notch cut from its top edge at centre.
struct DSTabBarShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: DSTabBarStyle.cornerRadius, style: .continuous)
            .subtracting(.notchCut(in: rect))
    }
}

/// Everything outside the hole, extended past the bar by `DSTabBarStyle.shadowMaskSpread`.
/// Used as a mask: the bar's shadow is a blurred silhouette behind the bar, so without this
/// it would blur into the hole and show through it.
struct DSTabBarShadowMask: Shape {
    func path(in rect: CGRect) -> Path {
        let spread = DSTabBarStyle.shadowMaskSpread
        return Path(rect.insetBy(dx: -spread, dy: -spread)).subtracting(.notchCut(in: rect))
    }
}

/// The brief's notch outline as offsets from the bar's centre line (x) and down from the bar row's top edge (y).
/// The bowl's radius and centre come from `DSTabBarStyle`, so the outline stays round when those change.
private enum NotchOutline {
    /// Where the cut meets the bar's top edge on the left. The right end is the last segment's `end`.
    static let start = CGPoint(x: -37, y: 0)

    /// Six cubic segments from the left top corner, round the bowl, to the right top corner.
    static var segments: [(control1: CGPoint, control2: CGPoint, end: CGPoint)] {
        let bowlRadius = DSTabBarStyle.notchRadius
        let bowlCentreY = DSTabBarStyle.notchCenterY
        let bowlBottomY = bowlCentreY + bowlRadius
        return [
            (CGPoint(x: -33, y: 0), CGPoint(x: -31, y: 5), CGPoint(x: -32, y: 9)),
            (CGPoint(x: -33, y: 13), CGPoint(x: -bowlRadius, y: 17), CGPoint(x: -bowlRadius, y: bowlCentreY)),
            (CGPoint(x: -bowlRadius, y: 41), CGPoint(x: -19, y: bowlBottomY), CGPoint(x: 0, y: bowlBottomY)),
            (CGPoint(x: 19, y: bowlBottomY), CGPoint(x: bowlRadius, y: 41), CGPoint(x: bowlRadius, y: bowlCentreY)),
            (CGPoint(x: bowlRadius, y: 17), CGPoint(x: 33, y: 13), CGPoint(x: 32, y: 9)),
            (CGPoint(x: 31, y: 5), CGPoint(x: 33, y: 0), CGPoint(x: 37, y: 0))
        ]
    }
}

private extension Path {
    /// The notch the centre control sits in. The cut is positioned against the bar row at the bottom of the rect,
    /// not the top. The rect grows upward while the shelf is open, and the notch must stay with the row rather than
    /// float at the shelf's top edge.
    static func notchCut(in rect: CGRect) -> Path {
        let rowTop = rect.maxY - DSTabBarStyle.height
        func point(_ offset: CGPoint) -> CGPoint {
            CGPoint(x: rect.midX + offset.x, y: rowTop + offset.y)
        }
        var cut = Path()
        cut.move(to: point(NotchOutline.start))
        for segment in NotchOutline.segments {
            cut.addCurve(to: point(segment.end), control1: point(segment.control1), control2: point(segment.control2))
        }
        cut.closeSubpath()
        guard rect.minY < rowTop else { return cut }
        return cut.union(bowlAboveRow(in: rect, rowTop: rowTop))
    }

    /// The part of the bowl above the bar row. While the shelf is open, the resting centre button's ring reaches into
    /// it, so the shelf must not paint over that ring.
    static func bowlAboveRow(in rect: CGRect, rowTop: CGFloat) -> Path {
        let radius = DSTabBarStyle.notchRadius
        let centre = CGPoint(x: rect.midX, y: rowTop + DSTabBarStyle.notchCenterY)
        let bowl = Path(ellipseIn: CGRect(
            x: centre.x - radius,
            y: centre.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        let aboveRow = Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rowTop - rect.minY))
        return bowl.intersection(aboveRow)
    }
}
