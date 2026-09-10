import SwiftUI
import DesignSystem

/// Per-chain status indicator: one ring per chain, coloured by `ChainStatusRingStyle` and pulsing
/// its icon while the socket is connecting.
struct ChainStatusRingView: View, Hashable {
    let viewModel: ChainConnectionStatusViewModel

    /// Stroke and dot scale with this, so the two hosts stay visually the same mark at
    /// different sizes — the strip is bound by its 20pt band, the panel is not.
    var diameter: CGFloat = 16

    var body: some View {
        ZStack {
            Circle()
                .fill(arcColor)
                .opacity(isFilled ? 1 : 0)
                .animation(indicationAnimation, value: indication)

            Circle()
                .stroke(trackColor, lineWidth: lineWidth)

            if showsArc {
                Circle()
                    .trim(from: 0, to: arcEnd)
                    .stroke(
                        arcColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(indicationAnimation, value: indication)
            }

            ChainStatusIconView(
                icon: viewModel.icon,
                color: iconColor,
                diameter: dotDiameter,
                isPulsing: viewModel.state == .connecting
            )
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        // A plain interpolated Text("...") would be treated as a localizable format string and
        // register a "%@, %@" entry in the package catalog; verbatim avoids localization.
        .accessibilityLabel(Text(verbatim: "\(viewModel.title), \(viewModel.stateTitle)"))
    }
}

private extension ChainStatusRingView {
    var indication: ChainStatusIndication { viewModel.indication }

    var isFilled: Bool { ChainStatusRingStyle.isFilled(for: indication) }

    var showsArc: Bool {
        switch indication {
        case .normal,
             .outage:
            true
        case .dead:
            false
        }
    }

    var arcEnd: CGFloat {
        switch indication {
        case .normal:
            1
        case let .outage(liveness):
            liveness
        case .dead:
            0
        }
    }

    var arcColor: Color { ChainStatusRingStyle.arcColor(for: indication) }

    var trackColor: Color { ChainStatusRingStyle.trackColor(for: indication) }

    var iconColor: Color { ChainStatusRingStyle.iconColor(for: indication) }

    var indicationAnimation: Animation { .easeOut(duration: 0.3) }

    var lineWidth: CGFloat { diameter / 8 }

    var dotDiameter: CGFloat { diameter * 0.625 }
}

/// Owns the repeating animation's `@State` so `ChainStatusRingView` keeps the synthesized
/// `Hashable` conformance that content reuse depends on.
private struct ChainStatusIconView: View {
    let icon: ChainStatusIcon
    let color: Color
    let diameter: CGFloat
    let isPulsing: Bool

    @State private var isDimmed = false

    var body: some View {
        Image(icon.imageResource)
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
            .frame(width: diameter, height: diameter)
            .opacity(isDimmed ? 0.3 : 1)
            .animation(pulseAnimation, value: isDimmed)
            .onAppear { isDimmed = isPulsing }
            .onChange(of: isPulsing) { _, newValue in isDimmed = newValue }
    }

    private var pulseAnimation: Animation {
        isPulsing
            ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
            : .easeInOut(duration: 0.2)
    }
}

private extension ChainStatusIcon {
    var imageResource: ImageResource {
        switch self {
        case .people:
            .statusIconPeople
        case .bulletin:
            .statusIconBulletin
        case .assetHub:
            .statusIconAssethub
        case .statementStore:
            .statusIconSstore
        }
    }
}
