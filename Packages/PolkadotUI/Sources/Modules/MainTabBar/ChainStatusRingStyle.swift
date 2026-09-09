import SwiftUI
import DesignSystem

/// The single place that says how an indication is drawn. A normal chain is monochrome — a filled
/// `.fgPrimary` disc with the icon knocked out — so anything muted on the strip reads as a chain
/// the app cannot reach.
enum ChainStatusRingStyle {
    static func isFilled(for indication: ChainStatusIndication) -> Bool {
        indication == .normal
    }

    static func arcColor(for indication: ChainStatusIndication) -> Color {
        switch indication {
        case .normal:
            .fgPrimary
        case .dead:
            .fgTertiary
        }
    }

    static func trackColor(for indication: ChainStatusIndication) -> Color {
        switch indication {
        case .normal:
            .fgPrimary.opacity(0.2)
        case .dead:
            .fgTertiary
        }
    }

    static func iconColor(for indication: ChainStatusIndication) -> Color {
        switch indication {
        case .normal:
            .bgSurfaceMain
        case .dead:
            .fgTertiary
        }
    }
}
