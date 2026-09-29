import DesignSystem
import PolkadotUI
import SwiftUI

/// Swatch keying one summary figure to its section of the bar above.
///
/// The gaining-privacy swatch is the same ``DSBarberPole`` the bar uses, so there is one striped
/// thing on the screen rather than two that merely resemble each other. It is drawn unanimated:
/// the figures are read once, and a moving texture there is louder than what it labels.
struct CoinageLegendSwatch: View {
    enum Kind {
        case availableNow
        case gainingPrivacy
    }

    let kind: Kind

    var body: some View {
        shape
            .frame(
                width: CoinageStatusMetrics.legendSwatchSize,
                height: CoinageStatusMetrics.legendSwatchSize
            )
            .clipShape(
                RoundedRectangle(cornerRadius: CoinageStatusMetrics.legendSwatchCornerRadius)
            )
            // The white swatch would vanish into a light theme's summary box without it.
            .overlay(
                RoundedRectangle(cornerRadius: CoinageStatusMetrics.legendSwatchCornerRadius)
                    .stroke(
                        CoinageStatusMetrics.markFrame,
                        lineWidth: CoinageStatusMetrics.markFrameWidth
                    )
            )
    }

    @ViewBuilder
    private var shape: some View {
        switch kind {
        case .availableNow: Color.fgStaticWhite
        case .gainingPrivacy: DSBarberPole(isAnimated: false)
        }
    }
}
