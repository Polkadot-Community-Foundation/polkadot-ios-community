import SwiftUI

public extension DSTabBarStyle {
    /// Tab bar values with no exact design-system match. They are the same in every theme.
    enum Palette {
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

        // MARK: Search field and list

        public static let fieldFill = Color.white.opacity(0.06)
        public static let fieldTopLine = Color.white.opacity(0.18)
        public static let fieldOutline = Color.white.opacity(0.08)
        public static let fieldIcon = Color(hex: 0xECECEC)
        public static let placeholder = Color(hex: 0x999999)
        public static let primaryText = Color(hex: 0xF4F4F5)
        public static let sectionHeader = Color(hex: 0x8E8E96)
        public static let caret = Color(hex: 0x0A84FF)
        public static let clearFill = Color(hex: 0x3A3A3C)
        public static let clearGlyph = Color(hex: 0xE5E5EA)

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

        /// Stops of the bar outline's rim. `DSTabBarStyle.rimGradient` lays them out for each size, so the falloff
        /// follows a 45° line instead of the bar's aspect ratio.
        public static let barRimStops = diagonalRimStops(opacities: [0.55, 0.30, 0.08, 0.05, 0.06, 0.24, 0.36])
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
        /// Stops of the resting centre button's rim, laid out per size like `barRimStops`.
        public static let centerRestingRimStops = diagonalRimStops(
            opacities: [0.62, 0.42, 0.10, 0.04, 0.06, 0.28, 0.44]
        )

        /// The stops of a white rim, with `opacities` at the locations both rims share.
        private static func diagonalRimStops(opacities: [Double]) -> [Gradient.Stop] {
            let locations: [CGFloat] = [0, 0.05, 0.12, 0.50, 0.86, 0.95, 1]
            return zip(opacities, locations).map { opacity, location in
                Gradient.Stop(color: .white.opacity(opacity), location: location)
            }
        }
    }
}

extension DSTabBarStyle {
    enum SearchTypography {
        static let sectionHeader = LabelStyle(
            font: interFont(.interMedium, size: 12),
            lineHeight: 16,
            tracking: 0.72
        )
        static let rowName = LabelStyle(font: interFont(.interSemiBold, size: 16), lineHeight: 22)
        static let query = LabelStyle(font: interFont(.interRegular, size: 16), lineHeight: 22)
        static var avatarInitial: Font { Font(interFont(.interSemiBold, size: 20)) }
    }
}

private extension DSTabBarStyle.SearchTypography {
    static func interFont(_ font: CustomFont, size: CGFloat) -> UIFont {
        UIFont.registerAllFontsIfNeeded()
        return UIFont(name: font.name, size: size) ?? .systemFont(ofSize: size)
    }
}
