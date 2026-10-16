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
    }
}
