import MetalKit
import SwiftUI

/// Every holding, as real coins, in one of two arrangements.
///
/// Collapsed, they are the summary strip: a fixed height however many there are, face on with
/// margins while they fit, turning about their vertical axis as they multiply, thinning once fully
/// edge-on. Expanded, the same coins spread into a honeycomb, with runs of alike coins in piles
/// when there are too many to lay out singly.
///
/// One view, one set of coins. A toggle only moves targets, so the coins fly between the two
/// arrangements rather than one view cutting to another.
struct CoinageCoinsView: UIViewRepresentable {
    /// Coins arrive in display order, Clearing first: both arrangements block on runs of one
    /// partition, so ordering them is the presenter's job, not this view's.
    /// What the coins came out as, so the card can grow with them and label the blocks.
    struct Metrics: Equatable {
        var height: CGFloat = CoinageStripLayout.Options().height
        var blocks: [Block] = []
        var piles: [CoinageArrangement.Pile] = []

        struct Block: Equatable, Identifiable {
            let partition: CoinageStripLayout.Partition
            let top: CGFloat
            let count: Int

            var id: String { partition.rawValue }
        }
    }

    let coins: [CoinageScene.Coin]
    let isExpanded: Bool
    @Binding var metrics: Metrics
    var stripHeight: CGFloat = CoinageStripLayout.Options().height

    func makeCoordinator() -> Coordinator {
        Coordinator(coins: coins, isExpanded: isExpanded, stripHeight: stripHeight) { measured in
            metrics = measured
        }
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.clearDepth = 1
        view.isOpaque = false
        view.layer.isOpaque = false
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.preferredFramesPerSecond = 60
        // Driven by the display link, paused the moment the springs settle, so coins at rest cost
        // nothing. `enableSetNeedsDisplay` would switch the link off and leave the view drawing one
        // frame per change, which renders correctly and never animates.
        view.enableSetNeedsDisplay = false
        view.isPaused = true

        // Whatever the pipeline was built for. Asking the device again here could answer
        // differently, and a pipeline and a render pass that disagree on samples fail validation at
        // the draw call rather than anywhere that would explain it.
        view.sampleCount = context.coordinator.sampleCount

        view.delegate = context.coordinator
        context.coordinator.attach(to: view)

        return view
    }

    func updateUIView(_: MTKView, context: Context) {
        context.coordinator.update(coins: coins, isExpanded: isExpanded)
    }

    static func dismantleUIView(_: MTKView, coordinator: Coordinator) {
        coordinator.detach()
    }
}

// MARK: - Coordinator

extension CoinageCoinsView {
    /// Owns the renderer, which owns the meshes and the studio, and the field, which owns where
    /// every coin has got to. It outlives both arrangements, which is what lets coins fly between
    /// them instead of being made afresh.
    final class Coordinator: NSObject, MTKViewDelegate {
        /// The device and its sample count are needed the moment the view is made; the renderer is
        /// not, because a view with nothing to draw simply draws nothing.
        let device = MTLCreateSystemDefaultDevice()
        let sampleCount: Int

        private var renderer: CoinageMetalRenderer?
        private let field = CoinageCoinField()
        private let tilt = CoinageTilt()
        private let report: (Metrics) -> Void
        private let stripHeight: CGFloat
        private var coins: [CoinageScene.Coin]
        private var isExpanded: Bool
        private var laidOut: CGSize = .zero
        private var lastFrame: CFTimeInterval?
        private weak var view: MTKView?

        init(
            coins: [CoinageScene.Coin],
            isExpanded: Bool,
            stripHeight: CGFloat,
            report: @escaping (Metrics) -> Void
        ) {
            self.coins = coins
            self.isExpanded = isExpanded
            self.stripHeight = stripHeight
            self.report = report
            sampleCount = CoinageRendererLoader.sampleCount(for: device)
            super.init()

            CoinageRendererLoader.load { [weak self] renderer in
                guard let self else { return }

                self.renderer = renderer
                // Whatever the field was told while there was nothing to draw it with.
                laidOut = .zero
                run()
            }
        }

        func attach(to view: MTKView) {
            self.view = view
            // The studio turns with the phone even when nothing else is moving, and the view sleeps
            // whenever nothing is moving, so motion has to wake it rather than be waited for.
            tilt.onMove = { [weak self] in self?.run() }
            tilt.start()
            run()
        }

        func detach() {
            tilt.stop()
            view = nil
        }

        func update(coins: [CoinageScene.Coin], isExpanded: Bool) {
            guard coins != self.coins || isExpanded != self.isExpanded else { return }

            self.coins = coins
            self.isExpanded = isExpanded
            laidOut = .zero
            run()
        }

        func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {
            laidOut = .zero
            run()
        }

        func draw(in view: MTKView) {
            // Nothing to draw with yet. The loader wakes the view when there is.
            guard let renderer else {
                view.isPaused = true
                return
            }

            let size = view.bounds.size

            guard size.width > 0 else { return }

            if abs(size.width - laidOut.width) > 0.5 {
                retarget(width: size.width, designs: renderer.store.designs)
                laidOut = size
            }

            let moved = advance()

            let batches = CoinageScene.batches(
                for: field,
                frame: CoinageScene.Frame(dpr: view.contentScaleFactor),
                designs: renderer.store.designs
            )

            renderer.draw(
                batches,
                in: view,
                viewport: size,
                dpr: view.contentScaleFactor,
                light: tilt.turn
            )

            if !field.isMoving, !moved {
                view.isPaused = true
                lastFrame = nil
            }
        }
    }
}

// MARK: - Driving

private extension CoinageCoinsView.Coordinator {
    /// Wakes the view. Everything else is the springs' business.
    func run() {
        lastFrame = nil
        view?.isPaused = false
    }

    /// A real elapsed time rather than a nominal frame: the spring is exact for any step, and a
    /// dropped frame should not slow the motion down.
    /// Returns whether the studio is still turning, so a field at rest keeps drawing only while
    /// the phone is actually being moved.
    func advance() -> Bool {
        let now = CACurrentMediaTime()
        let elapsed = lastFrame.map { min(now - $0, 1.0 / 20) } ?? 1.0 / 60
        lastFrame = now

        field.advance(by: CGFloat(elapsed))

        return tilt.advance(by: CGFloat(elapsed))
    }

    /// How tall the grid is allowed to get before it starts stacking alike coins into piles.
    ///
    /// The grid has to be packed against a real height or nothing ever fails to fit: it would keep
    /// the largest coins, never pile, and five hundred holdings would lay out about five thousand
    /// points tall. Past sixteen thousand device pixels the drawable is clamped and scaled, which
    /// is what turned the five hundred coin grid into a blur.
    ///
    /// A screenful is the right budget because the grid is meant to be taken in at a glance; past
    /// that the reference's own answer is piles, not scrolling.
    var gridBudget: CGFloat {
        let screen = view?.window?.windowScene?.screen.bounds.height ?? 800

        return max(screen * 0.62, 240)
    }

    func retarget(width: CGFloat, designs: [CoinageAssetStore.Design]) {
        let result = CoinageArrangement.targets(
            for: coins,
            arrangement: isExpanded ? .grid : .strip,
            area: CGSize(width: width, height: gridBudget),
            designs: designs,
            stripHeight: stripHeight
        )

        field.retarget(
            result.targets,
            spawningFrom: width,
            // Spreading out, the last coins have furthest to travel; gathering back in, the first
            // ones do. Either way the long haul sets off first.
            stagger: isExpanded ? .fromBack : .fromFront
        )
        report(
            CoinageCoinsView.Metrics(
                height: result.height,
                blocks: result.blocks.map {
                    CoinageCoinsView.Metrics.Block(
                        partition: $0.partition,
                        top: $0.top,
                        count: $0.count
                    )
                },
                piles: result.piles
            )
        )
        run()
    }
}
