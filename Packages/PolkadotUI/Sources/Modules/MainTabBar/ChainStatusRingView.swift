import SwiftUI
import DesignSystem

/// Per-chain status indicator: one ring per chain, coloured by `ChainStatusRingStyle`, pulsing
/// its icon while the socket is connecting, and drawing its track as rotating dashes during connection
/// to convey motion and retry.
struct ChainStatusRingView: View, Hashable {
    let viewModel: ChainConnectionStatusViewModel

    /// Stroke and dot scale with this, so the two hosts stay visually the same mark at
    /// different sizes — the strip is bound by its 20pt band, the panel is not.
    var diameter: CGFloat = 20

    var body: some View {
        ZStack {
            if isConnecting {
                ChainStatusTrackView(
                    color: trackColor,
                    lineWidth: lineWidth,
                    isRotating: true
                )
                .transition(.opacity)
            } else {
                // Disc and arc stay mounted across the normal/outage step so the arc grows to
                // full and closes into the disc as a chain recovers, rather than dissolving.
                Circle()
                    .fill(arcColor)
                    .opacity(isFilled ? 1 : 0)
                    .animation(indicationAnimation, value: indication)

                if !isFilled {
                    Group {
                        ChainStatusTrackView(
                            color: trackColor,
                            lineWidth: lineWidth,
                            isRotating: false
                        )

                        if showsArc {
                            Circle()
                                .inset(by: lineWidth / 2)
                                .trim(from: 1 - arcEnd, to: 1)
                                .stroke(
                                    arcColor,
                                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .animation(indicationAnimation, value: indication)
                        }
                    }
                    .transition(.opacity)
                }
            }

            ChainStatusIconView(
                icon: viewModel.icon,
                color: iconColor,
                diameter: iconDiameter,
                isPulsing: viewModel.state == .connecting
            )
        }
        .frame(width: diameter, height: diameter)
        .animation(indicationAnimation, value: isConnecting)
        .animation(indicationAnimation, value: isFilled)
        .accessibilityElement(children: .ignore)
        // A plain interpolated Text("...") would be treated as a localizable format string and
        // register a "%@, %@" entry in the package catalog; verbatim avoids localization.
        .accessibilityLabel(Text(verbatim: "\(viewModel.title), \(viewModel.stateTitle)"))
    }
}

private extension ChainStatusRingView {
    var indication: ChainStatusIndication { viewModel.indication }

    var isFilled: Bool { ChainStatusRingStyle.isFilled(for: indication) }

    var isConnecting: Bool { viewModel.state == .connecting }

    /// Keyed on the socket, not the indication: the arc is a reading of a chain the app is
    /// actually talking to, so connecting and offline both show a bare track.
    var showsArc: Bool { viewModel.state == .connected }

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

    var iconDiameter: CGFloat { diameter * 0.5 }
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

/// Owns the repeating animation's `@State` so `ChainStatusRingView` keeps the synthesized
/// `Hashable` conformance that content reuse depends on.
private struct ChainStatusTrackView: View {
    let color: Color
    let lineWidth: CGFloat
    let isRotating: Bool

    @State private var angle: Double = 0

    var body: some View {
        Circle()
            .inset(by: lineWidth / 2)
            .stroke(color, style: strokeStyle)
            .rotationEffect(.degrees(angle))
            .onAppear { startRotating(isRotating) }
            .onChange(of: isRotating) { _, newValue in startRotating(newValue) }
    }

    private var strokeStyle: StrokeStyle {
        guard isRotating else {
            return StrokeStyle(lineWidth: lineWidth)
        }

        return StrokeStyle(
            lineWidth: lineWidth,
            lineCap: .round,
            dash: [lineWidth * 2, lineWidth * 2]
        )
    }

    private func startRotating(_ isRotating: Bool) {
        guard isRotating else {
            withAnimation(.linear(duration: 0.2)) { angle = 0 }
            return
        }

        withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
            angle = 360
        }
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
        }
    }
}
