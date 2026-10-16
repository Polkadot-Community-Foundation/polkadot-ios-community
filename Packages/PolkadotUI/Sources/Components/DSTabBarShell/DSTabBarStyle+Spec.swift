import SwiftUI

public extension DSTabBarStyle {
    /// Tab bar values with no exact design-system match. They are the same in every theme.
    enum Spec {
        /// A flat fill rather than glass, because glass samples whatever scrolls under the bar and the
        /// selection would drift in colour from screen to screen.
        public static let selectionFill = Color.white.opacity(0.10)
        /// The hairline along the top edge of the selection pill.
        public static let selectionTopLine = Color.white.opacity(0.08)
        /// Icon and label colour of the slots that are neither selected nor active.
        public static let inactiveIcon = Color(hex: 0x999999)
        /// Icon and label colour of the selected or active slot.
        public static let activeIcon = Color(hex: 0xF4F4F5)
        /// The scan frame of the centre button.
        public static let centerGlyph = Color(hex: 0x8C8F98)
        /// The grabber along the top of the open centre panel.
        public static let grabber = Color.white.opacity(0.32)
        /// The tile behind the camera while it starts.
        public static let cameraBacking = Color(hex: 0x1A1B1F)

        /// The light end of the glass wash: the top centre of the bar and the top of the centre control.
        public static let glassLight = Color(hex: 0x919191).opacity(0.2)
        /// The dark end of the glass wash: the edge of the bar and the foot of the centre control.
        public static let glassDark = Color(hex: 0x2B2B2B).opacity(0.2)
        /// The fill the centre control settles to as its panel opens.
        public static let centerOpenFill = Color(hex: 0x080808).opacity(0.3)
        /// The shadow the bar casts onto the screen.
        public static let barShadow = Color.black.opacity(0.5)
        /// The scrim behind the bar while the centre panel is open.
        public static let dimWash = Color.black.opacity(0.3)
        /// The glint along the notch edge, from left to right across the cutout. The colours are evenly spaced.
        public static let notchGlintColors: [Color] = [
            .white.opacity(0.50),
            .white.opacity(0.12),
            .white.opacity(0.03),
            .white.opacity(0.05),
            .white.opacity(0.42),
            .white.opacity(0.20),
            .white.opacity(0.08)
        ]

        /// The rim of the bar outline, lit from the top leading corner.
        public static let barRim = diagonalRim(opacities: [0.55, 0.30, 0.08, 0.05, 0.06, 0.24, 0.36])
        /// Faint white at each horizontal end of the bar rim, fading out by 8 % of the width.
        public static let barRimEnds = LinearGradient(
            stops: [
                .init(color: .white.opacity(0.03), location: 0),
                .init(color: .white.opacity(0), location: 0.08),
                .init(color: .white.opacity(0), location: 0.92),
                .init(color: .white.opacity(0.03), location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        /// The rim of the resting centre button, lit from the top leading corner.
        public static let centerRestingRim = diagonalRim(opacities: [0.62, 0.42, 0.10, 0.04, 0.06, 0.28, 0.44])

        /// A white rim lit from the top leading corner, with `opacities` at the stops both rims share.
        private static func diagonalRim(opacities: [Double]) -> LinearGradient {
            let locations: [CGFloat] = [0, 0.05, 0.12, 0.50, 0.86, 0.95, 1]
            return LinearGradient(
                stops: zip(opacities, locations).map { opacity, location in
                    Gradient.Stop(color: .white.opacity(opacity), location: location)
                },
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
