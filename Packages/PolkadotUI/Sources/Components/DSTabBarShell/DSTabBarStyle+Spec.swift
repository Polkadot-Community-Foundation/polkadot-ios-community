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
    }
}
